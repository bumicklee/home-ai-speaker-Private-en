import 'dart:convert';
import 'dart:typed_data';

import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/network/device_api_client.dart';
import 'package:aispeaker/core/network/device_endpoint.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake HTTP that decides the response per address
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions o) handler;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    seen.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

class FakeResolver implements DeviceResolver {
  FakeResolver(this.newHost);
  final String? newHost;
  int calls = 0;

  @override
  Future<DeviceEndpoint?> resolve(DeviceEndpoint stale) async {
    calls++;
    return newHost == null ? null : stale.copyWith(host: newHost);
  }
}

const ep = DeviceEndpoint(deviceId: 'A1B2C3D4E5F6', host: '192.168.0.10', token: 'tok');

void main() {
  test('토큰을 Bearer로 붙이고 JSON을 돌려준다', () async {
    final adapter = FakeAdapter((o) => json(200, {'fw': '0.5.0'}));
    final client = DeviceApiClient(ep, dio: Dio()..httpClientAdapter = adapter);
    final status = await client.get<Map<String, dynamic>>('/api/v1/status');
    expect(status['fw'], '0.5.0');
    expect(adapter.seen.single.headers['Authorization'], 'Bearer tok');
    expect(adapter.seen.single.uri.toString(), 'http://192.168.0.10/api/v1/status');
  });

  test('오류 본문 {"error": code} → DeviceApiException', () async {
    final client = DeviceApiClient(ep, dio: Dio()..httpClientAdapter = FakeAdapter((o) => json(409, {'error': 'VOICE_ACTIVE'})));
    await expectLater(client.post<void>('/api/v1/system/reboot'),
        throwsA(isA<DeviceApiException>().having((e) => e.status, 'status', 409).having((e) => e.code, 'code', 'VOICE_ACTIVE')));
  });

  test('오류 본문 전체를 data에 담는다 (메모 409 CONFLICT의 note)', () async {
    final client = DeviceApiClient(ep,
        dio: Dio()..httpClientAdapter = FakeAdapter((o) => json(409, {'error': 'CONFLICT', 'note': {'id': 'n_1', 'rev': 9}})));
    await expectLater(
        client.put<void>('/api/v1/notes/n_1', {'base_rev': 3}),
        throwsA(isA<DeviceApiException>()
            .having((e) => e.code, 'code', 'CONFLICT')
            .having((e) => (e.data?['note'] as Map)['rev'], 'note.rev', 9)));
  });

  test('연결 실패 → mDNS로 새 IP를 찾아 한 번 재시도, 바뀐 주소를 알린다', () async {
    final adapter = FakeAdapter((o) {
      if (o.uri.host == '192.168.0.10') {
        throw DioException.connectionError(requestOptions: o, reason: 'refused');
      }
      return json(200, {'ok': true});
    });
    final resolver = FakeResolver('192.168.0.23');
    DeviceEndpoint? changed;
    final client = DeviceApiClient(ep, resolver: resolver, dio: Dio()..httpClientAdapter = adapter,
        onEndpointChanged: (e) => changed = e);
    expect((await client.get<Map<String, dynamic>>('/x'))['ok'], isTrue);
    expect(resolver.calls, 1);
    expect(changed?.host, '192.168.0.23');
    expect(adapter.seen.map((o) => o.uri.host), ['192.168.0.10', '192.168.0.23']);
  });

  test('새 IP를 못 찾으면 NetworkException', () async {
    final adapter = FakeAdapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'refused'));
    final client = DeviceApiClient(ep, resolver: FakeResolver(null), dio: Dio()..httpClientAdapter = adapter);
    await expectLater(client.get<void>('/x'), throwsA(isA<NetworkException>()));
  });

  test('401은 재시도하지 않는다', () async {
    final resolver = FakeResolver('192.168.0.23');
    final client = DeviceApiClient(ep, resolver: resolver, dio: Dio()..httpClientAdapter = FakeAdapter((o) => json(401, {})));
    await expectLater(client.get<void>('/x'), throwsA(isA<DeviceApiException>().having((e) => e.status, 's', 401)));
    expect(resolver.calls, 0);
  });
}
