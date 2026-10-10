import '../../domain/entities/device.dart';

/// SharedPreferences storage format (the token is not stored here; see DeviceTokenStorage)
class DeviceModel {
  static Map<String, dynamic> toJson(Device d) => {'id': d.id, 'name': d.name, 'host': d.host, 'port': d.port};

  static Device fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        host: j['host'] as String?,
        port: j['port'] as int? ?? 80,
      );
}
