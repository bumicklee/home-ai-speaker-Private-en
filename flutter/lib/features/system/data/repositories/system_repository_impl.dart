import 'package:dartz/dartz.dart';

import '../../../../core/ble/ble_speaker.dart';
import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../domain/entities/system_status.dart';
import '../../domain/repositories/system_repository.dart';
import '../models/system_status_model.dart';

class SystemRepositoryImpl implements SystemRepository {
  SystemRepositoryImpl(this._device, this._ble);

  final CurrentDevice _device;
  final BleSpeakerDataSource _ble;

  @override
  String? get deviceId => _device.deviceId;

  @override
  String? get host => _device.endpoint?.host;

  @override
  Future<Either<Failure, SystemStatus>> status() => guard(() async {
        final j = await _device.client.get<Map<String, dynamic>>(ApiPaths.status);
        return SystemStatusModel.fromJson(j);
      });

  @override
  Future<Either<Failure, List<RegisteredPhone>>> phones() => guard(() async {
        final body = await _device.client.get<dynamic>(ApiPaths.phones);
        return RegisteredPhoneModel.listFromJson(body);
      });

  @override
  Future<Either<Failure, Unit>> revokePhone(String phoneId) => guard(() async {
        await _device.client.delete<dynamic>(ApiPaths.phone(phoneId));
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> reboot() => guard(() async {
        await _device.client.post<dynamic>(ApiPaths.reboot);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> deleteSpeakerKey(String key) => guard(() async {
        await _device.client.delete<dynamic>(ApiPaths.key(key));
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> sendKeyOverBle(String key, String value) => guard(() async {
        final id = _device.deviceId;
        if (id == null) throw StateError('no device selected');
        final session = await _ble.connectById(id);
        try {
          await session.setSecret(key, value);
          await session.closeWindow(); // apply and close the BLE window (no reboot)
        } finally {
          try {
            await session.disconnect();
          } catch (_) {}
        }
        return unit;
      });
}
