/// Exceptions thrown by data sources. External library exceptions (`DioException`, `FlutterBluePlusException`)
/// are converted into these in the data source. `guard` handles only these.
library;

sealed class AppException implements Exception {
  const AppException([this.message]);
  final String? message;

  @override
  String toString() => '$runtimeType(${message ?? ''})';
}

/// The LAN API returned an HTTP error. [code] is the body's `{"error": "..."}` (null if absent)
class DeviceApiException extends AppException {
  const DeviceApiException(this.status, this.code, [super.message, this.data]);
  final int status;
  final String? code;

  /// The whole error response body (e.g. `note` in a notes 409 `CONFLICT`). null if the body isn't a JSON object
  final Map<String, dynamic>? data;
}

/// Device response timeout. Kept separate so the name doesn't clash with dart:async `TimeoutException`
class DeviceTimeoutException extends AppException {
  const DeviceTimeoutException([super.message]);
}

/// Can't reach the device (not on the same Wi-Fi, IP changed, powered off)
class NetworkException extends AppException {
  const NetworkException([super.message]);
}

/// BLE error. [code] is a `BleErrorCode` value
class BleException extends AppException {
  const BleException(this.code, [super.message]);
  final String code;
}

/// The device answered a 0xFF81 command with `ok: false`. [code] is a `BleCmdError` value
class BleCommandException extends AppException {
  const BleCommandException(this.code, {this.data, String? message}) : super(message);
  final String code;

  /// The whole error response (e.g. the `phones` list for `PHONES_FULL`)
  final Map<String, dynamic>? data;
}

class CacheException extends AppException {
  const CacheException([super.message]);
}

/// App-internal BLE error codes
class BleErrorCode {
  BleErrorCode._();
  static const adapterOff = 'adapter_off';
  static const permissionDenied = 'permission_denied';
  static const notFound = 'not_found';
  static const connectFailed = 'connect_failed';
  static const disconnected = 'disconnected';
  static const serviceMissing = 'service_missing';
  static const bondFailed = 'bond_failed';
  static const protocol = 'protocol';
  static const tooLarge = 'too_large';
  static const timeout = 'timeout';
}
