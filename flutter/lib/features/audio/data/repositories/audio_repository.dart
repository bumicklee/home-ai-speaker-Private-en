import 'package:dartz/dartz.dart';

import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../domain/entities/audio_settings.dart';
import '../models/audio_settings_model.dart';

/// Audio, wake word, and LED settings (design document, Section 2.14). Sent to the selected device.
/// PUT sends only the changed keys (the device leaves missing keys as they are, and after saving returns the whole group)
class AudioRepository {
  AudioRepository(this._device);

  final CurrentDevice _device;

  Future<Either<Failure, AudioSettings>> audio() =>
      guard(() async => AudioSettingsModel.audioFromJson(await _get(SettingsGroup.audio)));

  Future<Either<Failure, WakeSettings>> wake() =>
      guard(() async => AudioSettingsModel.wakeFromJson(await _get(SettingsGroup.wake)));

  Future<Either<Failure, int>> ledBrightness() =>
      guard(() async => AudioSettingsModel.ledFromJson(await _get(SettingsGroup.led)));

  /// Keys: volume, mic_gain, auto_gain, duck_db
  Future<Either<Failure, AudioSettings>> updateAudio(Map<String, Object> change) =>
      guard(() async => AudioSettingsModel.audioFromJson(await _put(SettingsGroup.audio, change)));

  /// Keys: enabled, phrase(0/1), sensitivity, gain_db
  Future<Either<Failure, WakeSettings>> updateWake(Map<String, Object> change) =>
      guard(() async => AudioSettingsModel.wakeFromJson(await _put(SettingsGroup.wake, change)));

  Future<Either<Failure, int>> setLedBrightness(int brightness) =>
      guard(() async => AudioSettingsModel.ledFromJson(await _put(SettingsGroup.led, {'brightness': brightness})));

  Future<Either<Failure, Unit>> testTone() => _post(ApiPaths.testTone);

  /// Starts the 60-second detection test. WS `wake_test` on each detection. 409 VOICE_ACTIVE during a conversation
  Future<Either<Failure, Unit>> startWakeTest() => _post(ApiPaths.wakeTest);

  Future<Map<String, dynamic>> _get(String group) async =>
      await _device.client.get<Map<String, dynamic>>(ApiPaths.settings(group));

  Future<Map<String, dynamic>> _put(String group, Map<String, Object> change) async =>
      await _device.client.put<Map<String, dynamic>>(ApiPaths.settings(group), change);

  Future<Either<Failure, Unit>> _post(String path) => guard(() async {
        await _device.client.post<dynamic>(path);
        return unit;
      });
}
