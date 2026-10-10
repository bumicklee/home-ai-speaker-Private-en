import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/device_token_storage.dart';
import '../../domain/entities/device.dart';
import '../models/device_model.dart';

/// Device list (SharedPreferences) + per-device tokens (secure storage)
class DevicesLocalDataSource {
  DevicesLocalDataSource(this._prefs, this._tokens);

  final SharedPreferences _prefs;
  final DeviceTokenStorage _tokens;
  static const _listKey = 'devices';
  static const _selectedKey = 'selected_device';

  List<Device> readAll() {
    final raw = _prefs.getString(_listKey);
    if (raw == null) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List<dynamic>) DeviceModel.fromJson(j as Map<String, dynamic>)];
    } on FormatException catch (e) {
      throw CacheException(e.message);
    }
  }

  Future<void> writeAll(List<Device> devices) async {
    if (!await _prefs.setString(_listKey, jsonEncode([for (final d in devices) DeviceModel.toJson(d)]))) {
      throw const CacheException('devices not saved');
    }
  }

  String? get selectedId => _prefs.getString(_selectedKey);

  Future<void> setSelectedId(String? id) async {
    if (id == null) {
      await _prefs.remove(_selectedKey);
    } else {
      await _prefs.setString(_selectedKey, id);
    }
  }

  Future<String?> token(String id) => _tokens.read(id);
  Future<void> saveToken(String id, String token) => _tokens.write(id, token);
  Future<void> deleteToken(String id) => _tokens.delete(id);
}
