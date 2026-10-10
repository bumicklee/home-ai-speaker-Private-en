import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-device LAN tokens (received from `api.pair`). Only DevicesRepository uses this.
class DeviceTokenStorage {
  DeviceTokenStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const _prefix = 'device_token_';

  Future<String?> read(String deviceId) => _storage.read(key: '$_prefix$deviceId');

  Future<void> write(String deviceId, String token) => _storage.write(key: '$_prefix$deviceId', value: token);

  Future<void> delete(String deviceId) => _storage.delete(key: '$_prefix$deviceId');
}
