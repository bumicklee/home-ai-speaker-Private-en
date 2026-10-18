import 'dart:async';
import 'dart:convert';

import 'package:aispeaker/core/ble/ble_command_channel.dart';
import 'package:aispeaker/core/ble/ble_frame.dart';
import 'package:aispeaker/core/ble/ble_secret_writer.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/repository/guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake device that collects request chunks and returns [handler]'s response in chunks
class FakeDevice implements BleCommandTransport {
  FakeDevice(this.handler, {this.payloadSize = 20});

  final Map<String, dynamic>? Function(Map<String, dynamic> request) handler;
  final _responses = StreamController<List<int>>.broadcast();
  final _rx = BleFrameReassembler();
  final requests = <Map<String, dynamic>>[];

  @override
  final int payloadSize;

  @override
  Stream<List<int>> get responses => _responses.stream;

  @override
  Future<void> writeFrame(List<int> frame) async {
    final msg = _rx.add(frame);
    if (msg == null) return;
    final req = jsonDecode(utf8.decode(msg)) as Map<String, dynamic>;
    requests.add(req);
    final res = handler(req);
    if (res == null) return; // no response (timeout test)
    scheduleMicrotask(() {
      for (final f in BleFrameCodec.encode(utf8.encode(jsonEncode(res)), payloadSize)) {
        _responses.add(f);
      }
    });
  }

  void push(Map<String, dynamic> res) {
    for (final f in BleFrameCodec.encode(utf8.encode(jsonEncode(res)), payloadSize)) {
      _responses.add(f);
    }
  }
}

void main() {
  test('sends with a request id and receives the response with the same id (multiple chunks)', () async {
    final dev = FakeDevice((r) => {'id': r['id'], 'ok': true, 'token': 't' * 43, 'phone_id': r['phone_id']});
    final writer = BleSecretWriter(BleCommandChannel(dev));
    final r = await writer.pair(phoneId: 'p-1', phoneName: "Mom's phone");
    expect(r.token, 't' * 43);
    expect(dev.requests.single, {'id': 1, 'op': BleOp.apiPair, 'phone_id': 'p-1', 'phone_name': "Mom's phone"});
  });

  test('ok:false → BleCommandException (whole response as data)', () async {
    final dev = FakeDevice((r) => {'id': r['id'], 'ok': false, 'error': 'PHONES_FULL', 'phones': [{'phone_id': 'a'}]});
    final ch = BleCommandChannel(dev);
    await expectLater(
      ch.request(BleOp.apiPair, {'phone_id': 'x', 'phone_name': 'y'}),
      throwsA(isA<BleCommandException>()
          .having((e) => e.code, 'code', BleCmdError.phonesFull)
          .having((e) => e.data!['phones'], 'phones', hasLength(1))),
    );
  });

  test('requests go one at a time, in order (device answers BUSY to concurrent requests)', () async {
    var inFlight = 0, maxInFlight = 0;
    late FakeDevice dev;
    dev = FakeDevice((r) {
      inFlight++;
      maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
      Timer(const Duration(milliseconds: 5), () {
        inFlight--;
        dev.push({'id': r['id'], 'ok': true});
      });
      return null;
    });
    final ch = BleCommandChannel(dev);
    await Future.wait([ch.request('a'), ch.request('b'), ch.request('c')]);
    expect(dev.requests.map((r) => r['op']), ['a', 'b', 'c']);
    expect(maxInFlight, 1);
  });

  test('no response times out, the next request works (a late stale response is dropped)', () async {
    late FakeDevice dev;
    var first = true;
    dev = FakeDevice((r) {
      if (first) {
        first = false;
        return null;
      }
      dev.push({'id': 1, 'ok': false, 'error': 'BUSY'}); // late response to an old request
      return {'id': r['id'], 'ok': true, 'v': 2};
    });
    final ch = BleCommandChannel(dev, timeout: const Duration(milliseconds: 30));
    await expectLater(ch.request('slow'),
        throwsA(isA<BleException>().having((e) => e.code, 'code', BleErrorCode.timeout)));
    expect((await ch.request('next'))['v'], 2);
  });

  test('parses device.info', () async {
    final dev = FakeDevice((r) => {
          'id': r['id'],
          'ok': true,
          'protocol_version': 2,
          'fw': '0.5.0',
          'mac': 'A1B2C3D4E5F6',
          'provisioned': true,
          'wifi_connected': false,
          'secrets': {'openai_key': true, 'tg_bot_token': false},
        });
    final info = await BleSecretWriter(BleCommandChannel(dev)).deviceInfo();
    expect(info.mac, 'A1B2C3D4E5F6');
    expect(info.secrets, {'openai_key': true, 'tg_bot_token': false});
    expect(info.needsAppUpdate, isTrue);
  });

  test('gemini_key: secret.set/secret.erase, stored flag in device.info', () async {
    const value = 'AIzaSyA1234567890abcdefghijklmnopqrstu';
    final dev = FakeDevice((r) => r['op'] == BleOp.deviceInfo
        ? {
            'id': r['id'],
            'ok': true,
            'protocol_version': 1,
            'mac': 'A1B2C3D4E5F6',
            'secrets': {'openai_key': false, 'gemini_key': true},
          }
        : {'id': r['id'], 'ok': true});
    final writer = BleSecretWriter(BleCommandChannel(dev));
    await writer.setSecret(SecretKey.gemini, value);
    await writer.eraseSecret(SecretKey.gemini);
    final info = await writer.deviceInfo();
    expect(dev.requests[0], {'id': 1, 'op': BleOp.secretSet, 'key': 'gemini_key', 'value': value});
    expect(dev.requests[1], {'id': 2, 'op': BleOp.secretErase, 'key': 'gemini_key'});
    expect(info.secrets['gemini_key'], isTrue);
  });

  test('settings.set assistant: AI without a key gives NO_API_KEY → deviceNoApiKey', () async {
    final dev = FakeDevice((r) => {'id': r['id'], 'ok': false, 'error': 'NO_API_KEY'});
    final writer = BleSecretWriter(BleCommandChannel(dev));
    final r = await guard(() => writer.setSettings('assistant', {'ai_provider': 'gemini', 'mode_gemini': 'saver'}));
    expect(dev.requests.single, {
      'id': 1,
      'op': BleOp.settingsSet,
      'group': 'assistant',
      'value': {'ai_provider': 'gemini', 'mode_gemini': 'saver'},
    });
    final f = r.fold((f) => f, (_) => null);
    expect(f?.code, BleCmdError.noApiKey);
    expect(f?.errorKey, ErrorKeys.deviceNoApiKey);
  });

  test('on disconnect, the pending request fails as disconnected', () async {
    final ch = BleCommandChannel(FakeDevice((_) => null));
    final pending = ch.request('x');
    await Future<void>.delayed(Duration.zero);
    await ch.close();
    await expectLater(pending, throwsA(isA<BleException>().having((e) => e.code, 'code', BleErrorCode.disconnected)));
  });
}
