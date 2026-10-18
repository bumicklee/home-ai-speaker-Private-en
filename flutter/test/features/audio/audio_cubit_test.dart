import 'dart:async';

import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/audio/data/models/audio_settings_model.dart';
import 'package:aispeaker/features/audio/data/repositories/audio_repository.dart';
import 'package:aispeaker/features/audio/domain/entities/audio_settings.dart';
import 'package:aispeaker/features/audio/presentation/bloc/audio_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements AudioRepository {}

class MockEvents extends Mock implements DeviceEventService {}

const audio = AudioSettings(volume: 40, micGain: 36, autoGain: false, duckDb: 20);
const wake = WakeSettings(enabled: true, phrase: WakePhrase.computer, sensitivity: 80, gainDb: 12);
const timeout = DeviceFailure(errorKey: ErrorKeys.deviceTimeout);

void main() {
  late MockRepo repo;
  late MockEvents events;
  late StreamController<DeviceEvent> stream;

  setUp(() {
    repo = MockRepo();
    events = MockEvents();
    stream = StreamController<DeviceEvent>.broadcast();
    when(() => events.on(any())).thenAnswer((i) {
      final type = i.positionalArguments.first as String;
      return stream.stream.where((e) => e.type == type);
    });
    when(() => repo.audio()).thenAnswer((_) async => const Right(audio));
    when(() => repo.wake()).thenAnswer((_) async => const Right(wake));
    when(() => repo.ledBrightness()).thenAnswer((_) async => const Right(60));
  });

  tearDown(() => stream.close());

  AudioCubit build({Duration tick = const Duration(seconds: 1)}) => AudioCubit(repo, events, tick: tick);

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('loads all three groups', () async {
    final c = build();
    await c.load();
    expect(c.state.audio, audio);
    expect(c.state.wake, wake);
    expect(c.state.ledBrightness, 60);
    expect(c.state.loaded, isTrue);
    await c.close();
  });

  test('shows the failure screen if any one fails', () async {
    when(() => repo.ledBrightness()).thenAnswer((_) async => const Left(timeout));
    final c = build();
    await c.load();
    expect(c.state.loaded, isFalse);
    expect(c.state.failure, timeout);
    await c.close();
  });

  test('PUTs only the one changed key', () async {
    when(() => repo.updateAudio(any())).thenAnswer((_) async => Right(audio.copyWith(duckDb: 30)));
    when(() => repo.updateWake(any())).thenAnswer((_) async => Right(wake.copyWith(phrase: WakePhrase.alexa)));
    when(() => repo.setLedBrightness(any())).thenAnswer((_) async => const Right(25));
    final c = build();
    await c.load();

    await c.setDuck(30);
    verify(() => repo.updateAudio({'duck_db': 30})).called(1);
    expect(c.state.audio?.duckDb, 30);

    await c.setPhrase(WakePhrase.alexa);
    verify(() => repo.updateWake({'phrase': 0})).called(1);
    expect(c.state.wake?.phrase, WakePhrase.alexa);

    await c.setLedBrightness(25);
    verify(() => repo.setLedBrightness(25)).called(1);
    expect(c.state.ledBrightness, 25);
    await c.close();
  });

  test('reverts to the device value and reports the error when saving fails', () async {
    when(() => repo.updateWake(any())).thenAnswer((_) async => const Left(timeout));
    final c = build();
    await c.load();

    c.preview(wake: wake.copyWith(sensitivity: 30)); // while dragging
    expect(c.state.wake?.sensitivity, 30);
    await c.setSensitivity(30);
    verify(() => repo.updateWake({'sensitivity': 30})).called(1);
    expect(c.state.wake?.sensitivity, 80);
    expect(c.state.error?.failure, timeout);
    await c.close();
  });

  test('mic gain offers only values the device accepts (0–30 in steps of 3, 36)', () {
    expect(AudioSettings.micGainSteps, [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 36]);
    expect(AudioSettings.micGainSteps.contains(33), isFalse);
  });

  test('saves mic gain', () async {
    when(() => repo.updateAudio(any())).thenAnswer((_) async => Right(audio.copyWith(micGain: 24)));
    final c = build();
    await c.load();
    await c.setMicGain(24);
    verify(() => repo.updateAudio({'mic_gain': 24})).called(1);
    expect(c.state.audio?.micGain, 24);
    await c.close();
  });

  test('a volume event updates the slider value', () async {
    final c = build();
    await c.load();
    stream.add(const DeviceEvent('volume', {'value': 65}));
    await pump();
    expect(c.state.audio?.volume, 65);
    await c.close();
  });

  test('detection test: counts events and ends after 60 seconds', () async {
    when(() => repo.startWakeTest()).thenAnswer((_) async => const Right(unit));
    final c = build(tick: const Duration(milliseconds: 2));
    await c.load();
    await c.startWakeTest();
    expect(c.state.wakeTest, const WakeTest(remaining: 60));

    // The firmware's detections is cumulative since boot, so count events, not the value
    stream.add(const DeviceEvent('wake_test', {'detections': 7}));
    stream.add(const DeviceEvent('wake_test', {'detections': 8}));
    await pump();
    expect(c.state.wakeTest?.detections, 2);
    expect(c.state.wakeTest?.running, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(c.state.wakeTest?.remaining, 0);
    expect(c.state.wakeTest?.running, isFalse);

    // events after it ends are not counted
    stream.add(const DeviceEvent('wake_test', {'detections': 9}));
    await pump();
    expect(c.state.wakeTest?.detections, 2);
    await c.close();
  });

  test('detection test: 409 error while a conversation is active', () async {
    when(() => repo.startWakeTest())
        .thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'VOICE_ACTIVE')));
    final c = build();
    await c.load();
    await c.startWakeTest();
    expect(c.state.wakeTest, isNull);
    expect(c.state.error?.failure.errorKey, ErrorKeys.deviceVoiceActive);
    await c.close();
  });

  test('parses firmware JSON (phrase 0 Alexa / 1 Computer)', () {
    expect(
      AudioSettingsModel.wakeFromJson({'enabled': false, 'phrase': 0, 'sensitivity': 50, 'gain_db': 6}),
      const WakeSettings(enabled: false, phrase: WakePhrase.alexa, sensitivity: 50, gainDb: 6),
    );
    expect(
      AudioSettingsModel.audioFromJson(
          {'volume': 45, 'mic_gain': 30, 'auto_gain': true, 'duck_db': 10, 'spotify_pause_on_voice': true}),
      const AudioSettings(volume: 45, micGain: 30, autoGain: true, duckDb: 10),
    );
  });
}
