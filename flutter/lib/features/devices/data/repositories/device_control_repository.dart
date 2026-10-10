import 'package:dartz/dartz.dart';

import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';

/// Immediate actions on the home screen (start/end conversation, volume, playback control). Sent to the selected device
class DeviceControlRepository {
  DeviceControlRepository(this._device);

  final CurrentDevice _device;

  Future<Either<Failure, Unit>> startVoice() => _post(ApiPaths.voice('start'));
  Future<Either<Failure, Unit>> stopVoice() => _post(ApiPaths.voice('stop'));

  /// pause / resume / stop / next / previous
  Future<Either<Failure, Unit>> media(String action) => _post(ApiPaths.mediaControl(action));

  /// 0–80. The device saves it and announces it via WS `volume`
  Future<Either<Failure, Unit>> setVolume(int volume) => guard(() async {
        await _device.client.put<dynamic>(ApiPaths.settings(SettingsGroup.audio), {'volume': volume});
        return unit;
      });

  Future<Either<Failure, Unit>> _post(String path) => guard(() async {
        await _device.client.post<dynamic>(path);
        return unit;
      });
}
