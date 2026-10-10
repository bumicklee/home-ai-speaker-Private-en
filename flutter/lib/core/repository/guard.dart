import 'dart:async';

import 'package:dartz/dartz.dart';

import '../errors/error_keys.dart';
import '../errors/exceptions.dart';
import '../errors/failures.dart';

/// Shared by repositories: exception → Failure (no try/catch repeated in every method; design document Section 3.3)
Future<Either<Failure, T>> guard<T>(Future<T> Function() run) async {
  try {
    return Right(await run());
  } on AppException catch (e) {
    return Left(failureFrom(e));
  } on TimeoutException {
    return const Left(DeviceFailure.timeout());
  } catch (e) {
    return Left(UnknownFailure(message: e.toString()));
  }
}

Failure failureFrom(AppException e) => switch (e) {
      DeviceApiException(:final status, :final code, :final message) =>
        DeviceFailure.fromStatus(status, code, message),
      DeviceTimeoutException() => const DeviceFailure.timeout(),
      NetworkException(:final message) => NetworkFailure(message: message),
      BleException(:final code, :final message) =>
        BleFailure(errorKey: ErrorKeys.fromBleCode(code), code: code, message: message),
      BleCommandException(:final code, :final data, :final message) =>
        BleFailure(errorKey: ErrorKeys.fromBleCommand(code), code: code, data: data, message: message),
      CacheException(:final message) => CacheFailure(message: message),
    };
