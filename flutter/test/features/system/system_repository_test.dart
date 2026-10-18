import 'package:aispeaker/core/ble/ble_speaker.dart';
import 'package:aispeaker/core/constants/api_paths.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/network/device_api_client.dart';
import 'package:aispeaker/core/network/device_endpoint.dart';
import 'package:aispeaker/features/system/data/repositories/system_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCurrent extends Mock implements CurrentDevice {}

class MockClient extends Mock implements DeviceApiClient {}

class MockBle extends Mock implements BleSpeakerDataSource {}

class MockSession extends Mock implements BleSpeakerSession {}

const ep = DeviceEndpoint(deviceId: 'A1B2C3EB1650', host: '192.168.0.156', token: 't');
const key = 'sk-proj-abcdefghijklmnopqrstuvwx';

void main() {
  late MockCurrent current;
  late MockClient client;
  late MockBle ble;
  late MockSession session;
  late SystemRepositoryImpl repo;

  setUp(() {
    current = MockCurrent();
    client = MockClient();
    ble = MockBle();
    session = MockSession();
    when(() => current.endpoint).thenReturn(ep);
    when(() => current.deviceId).thenReturn(ep.deviceId);
    when(() => current.client).thenReturn(client);
    when(() => ble.connectById(ep.deviceId)).thenAnswer((_) async => session);
    when(() => session.setSecret(any(), any())).thenAnswer((_) async {});
    when(() => session.closeWindow()).thenAnswer((_) async {});
    when(() => session.disconnect()).thenAnswer((_) async {});
    repo = SystemRepositoryImpl(current, ble);
  });

  test('host = selected device IP', () => expect(repo.host, '192.168.0.156'));

  test('phones: GET /system/phones', () async {
    when(() => client.get<dynamic>(ApiPaths.phones)).thenAnswer((_) async => {
          'phones': [
            {'phone_id': 'p1', 'name': 'Mom', 'created': 0, 'self': true},
          ],
        });
    final r = await repo.phones();
    expect(r.getOrElse(() => []).single.self, isTrue);
  });

  test('revokePhone: DELETE /system/phones/{id}', () async {
    when(() => client.delete<dynamic>(any())).thenAnswer((_) async => {'ok': true});
    expect((await repo.revokePhone('p2')).isRight(), isTrue);
    verify(() => client.delete<dynamic>('/api/v1/system/phones/p2')).called(1);
  });

  test('reboot: 409 VOICE_ACTIVE → DeviceFailure', () async {
    when(() => client.post<dynamic>(ApiPaths.reboot)).thenThrow(const DeviceApiException(409, 'VOICE_ACTIVE'));
    final r = await repo.reboot();
    final f = r.fold((f) => f, (_) => null);
    expect(f, isA<DeviceFailure>());
    expect(f?.errorKey, ErrorKeys.deviceVoiceActive);
  });

  test('deleteSpeakerKey: DELETE /keys/{key}', () async {
    when(() => client.delete<dynamic>(any())).thenAnswer((_) async => {'ok': true});
    await repo.deleteSpeakerKey(SecretKey.openai);
    verify(() => client.delete<dynamic>('/api/v1/keys/openai_key')).called(1);
  });

  test('sendKeyOverBle: finds by device ID, secret.set → prov.close → disconnect (no LAN)', () async {
    final r = await repo.sendKeyOverBle(SecretKey.openai, key);
    expect(r.isRight(), isTrue);
    verifyInOrder([
      () => ble.connectById(ep.deviceId),
      () => session.setSecret(SecretKey.openai, key),
      () => session.closeWindow(),
      () => session.disconnect(),
    ]);
    verifyNever(() => current.client);
  });

  test('sendKeyOverBle: disconnects even if the write fails', () async {
    when(() => session.setSecret(any(), any()))
        .thenThrow(const BleCommandException(BleCmdError.notAllowed));
    final r = await repo.sendKeyOverBle(SecretKey.openai, key);
    expect(r.fold((f) => f.errorKey, (_) => null), ErrorKeys.bleWindowClosed);
    verifyNever(() => session.closeWindow());
    verify(() => session.disconnect()).called(1);
  });

  test('sendKeyOverBle: bleNotFound when no advertisement is seen', () async {
    when(() => ble.connectById(any())).thenThrow(const BleException(BleErrorCode.notFound));
    final r = await repo.sendKeyOverBle(SecretKey.openai, key);
    expect(r.fold((f) => f, (_) => null), isA<BleFailure>());
    expect(r.fold((f) => f.errorKey, (_) => null), ErrorKeys.bleNotFound);
  });
}
