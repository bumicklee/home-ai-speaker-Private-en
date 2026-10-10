import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/system_status.dart';

/// System screen: status, registered phones, restart, the speaker's keys (design document, Sections 2.13–2.14)
abstract interface class SystemRepository {
  /// Device ID of the selected speaker (null if none)
  String? get deviceId;

  /// IP address (for display)
  String? get host;

  Future<Either<Failure, SystemStatus>> status();
  Future<Either<Failure, List<RegisteredPhone>>> phones();

  /// 404 = already gone
  Future<Either<Failure, Unit>> revokePhone(String phoneId);

  /// 409 VOICE_ACTIVE = in a conversation
  Future<Either<Failure, Unit>> reboot();

  /// Delete a key on the speaker (LAN; allowed because no secret is sent)
  Future<Either<Failure, Unit>> deleteSpeakerKey(String key);

  /// Change a speaker key. Secrets go over BLE only (D6). Call after the user holds Key2 for 3 seconds to open the BLE window
  Future<Either<Failure, Unit>> sendKeyOverBle(String key, String value);
}
