import 'dart:async';

import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/network/device_endpoint.dart';
import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/devices/data/repositories/device_control_repository.dart';
import 'package:aispeaker/features/devices/domain/entities/device_status.dart';
import 'package:aispeaker/features/devices/domain/repositories/devices_repository.dart';
import 'package:aispeaker/features/devices/presentation/bloc/home_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDevices extends Mock implements DevicesRepository {}

class MockControl extends Mock implements DeviceControlRepository {}

class MockCurrent extends Mock implements CurrentDevice {}

class MockEvents extends Mock implements DeviceEventService {}

const ep = DeviceEndpoint(deviceId: 'A1B2C3EB1650', host: '192.168.0.156', token: 't');
const status = DeviceStatus(
  firmware: '0.5.0',
  uptime: Duration(minutes: 3),
  wifiRssi: -51,
  voiceState: 'idle',
  media: MediaNow(),
  volume: 40,
  secrets: {'openai_key': true},
  telegramState: 'ok',
  telegramUnread: 0,
  spotifyState: 'off',
);

void main() {
  late MockDevices devices;
  late MockControl control;
  late MockCurrent current;
  late MockEvents events;
  late StreamController<DeviceEvent> stream;

  setUpAll(() => registerFallbackValue(ep));

  setUp(() {
    devices = MockDevices();
    control = MockControl();
    current = MockCurrent();
    events = MockEvents();
    stream = StreamController<DeviceEvent>.broadcast();
    when(() => events.events).thenAnswer((_) => stream.stream);
    when(() => current.endpoint).thenReturn(ep);
    when(() => current.deviceId).thenReturn(ep.deviceId);
    when(() => devices.status(any())).thenAnswer((_) async => const Right(status));
  });

  HomeCubit build() => HomeCubit(devices, control, current, events);

  test('loads status and updates on live events', () async {
    final c = build();
    await c.refresh();
    expect(c.state.status?.volume, 40);

    stream.add(const DeviceEvent('volume', {'value': 55}));
    stream.add(const DeviceEvent('voice_state', {'state': 'live'}));
    stream.add(const DeviceEvent('media_state', {'source': 'radio', 'state': 'playing', 'station': 'CNN'}));
    stream.add(const DeviceEvent('tg_message', {'unread': 2}));
    await Future<void>.delayed(Duration.zero);
    expect(c.state.status?.volume, 55);
    expect(c.state.status?.isTalking, isTrue);
    expect(c.state.status?.media.station, 'CNN');
    expect(c.state.status?.telegramUnread, 2);
    await c.close();
  });

  test('401 puts it in the re-register prompt state', () async {
    when(() => devices.status(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(401, null)));
    final c = build();
    await c.refresh();
    expect(c.state.unauthorized, isTrue);
    await c.close();
  });

  test('while talking, the button ends the conversation', () async {
    when(() => devices.status(any())).thenAnswer((_) async => Right(status.copyWith(voiceState: 'live')));
    when(() => control.stopVoice()).thenAnswer((_) async => const Right(unit));
    final c = build();
    await c.refresh();
    await c.toggleVoice();
    verify(() => control.stopVoice()).called(1);
    verifyNever(() => control.startVoice());
    await c.close();
  });

  test('reloads when setting volume fails', () async {
    when(() => control.setVolume(70))
        .thenAnswer((_) async => const Left(DeviceFailure(errorKey: ErrorKeys.deviceTimeout)));
    final c = build();
    await c.refresh();
    await c.setVolume(70);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.status?.volume, 40);
    verify(() => devices.status(any())).called(2);
    await c.close();
  });
}
