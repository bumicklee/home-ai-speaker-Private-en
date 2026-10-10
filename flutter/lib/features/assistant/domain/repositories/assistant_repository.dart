import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/assistant_settings.dart';

/// Assistant settings, voices and memories of the selected speaker (LAN)
abstract class AssistantRepository {
  Future<Either<Failure, AssistantSettings>> settings();

  /// Partial update: sends only the keys in [changes]. Returns the full settings the device saved
  Future<Either<Failure, AssistantSettings>> update(Map<String, dynamic> changes);

  Future<Either<Failure, List<String>>> voices();

  Future<Either<Failure, List<AssistantMemory>>> memories();

  Future<Either<Failure, Unit>> forget(String key);
}
