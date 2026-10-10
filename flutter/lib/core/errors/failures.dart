import 'package:equatable/equatable.dart';

import 'error_keys.dart';

/// Failures returned by repositories. Screens pick the localized message by [errorKey].
sealed class Failure extends Equatable {
  const Failure({required this.errorKey, this.message, this.code});

  final String errorKey;

  /// Raw text for logs (never shown on screen as is)
  final String? message;
  final String? code;

  @override
  List<Object?> get props => [runtimeType, errorKey, message, code];
}

class DeviceFailure extends Failure {
  const DeviceFailure({required super.errorKey, this.status, super.message, super.code});

  factory DeviceFailure.fromStatus(int status, String? code, [String? message]) =>
      DeviceFailure(errorKey: ErrorKeys.fromDeviceStatus(status, code), status: status, code: code, message: message);

  const DeviceFailure.timeout() : this(errorKey: ErrorKeys.deviceTimeout);

  final int? status;

  /// 401 = this phone's registration was revoked → BLE re-registration screen
  bool get isUnauthorized => status == 401;

  @override
  List<Object?> get props => [...super.props, status];
}

class BleFailure extends Failure {
  const BleFailure({required super.errorKey, super.message, super.code, this.data});

  /// The whole device error response (e.g. `phones` for `PHONES_FULL`)
  final Map<String, dynamic>? data;

  @override
  List<Object?> get props => [...super.props, data];
}

class NetworkFailure extends Failure {
  const NetworkFailure({super.message}) : super(errorKey: ErrorKeys.deviceUnreachable);
}

class CacheFailure extends Failure {
  const CacheFailure({super.message}) : super(errorKey: ErrorKeys.cache);
}

class UnknownFailure extends Failure {
  const UnknownFailure({super.message}) : super(errorKey: ErrorKeys.unknown);
}
