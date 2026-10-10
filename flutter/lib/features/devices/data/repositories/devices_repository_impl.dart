import 'package:dartz/dartz.dart';

import '../../../../core/constants/api_paths.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/device_api_client.dart';
import '../../../../core/network/device_endpoint.dart';
import '../../../../core/repository/guard.dart';
import '../../../../core/services/device_discovery_service.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/device_status.dart';
import '../../domain/repositories/devices_repository.dart';
import '../datasources/devices_local_datasource.dart';
import '../models/device_status_model.dart';

class DevicesRepositoryImpl implements DevicesRepository {
  DevicesRepositoryImpl(this._local, this._clients, this._discovery);

  final DevicesLocalDataSource _local;
  final DeviceApiClientFactory _clients;
  final DeviceDiscoveryService _discovery;

  @override
  Future<Either<Failure, List<Device>>> devices() => guard(() async => _local.readAll());

  @override
  Future<Either<Failure, String?>> selectedId() => guard(() async {
        final all = _local.readAll();
        final id = _local.selectedId;
        if (id != null && all.any((d) => d.id == id)) return id;
        return all.isEmpty ? null : all.first.id;
      });

  @override
  Future<Either<Failure, Unit>> select(String id) => guard(() async {
        await _local.setSelectedId(id);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> addOrUpdate(Device device, String token) => guard(() async {
        // Save the token first: even if saving the list fails, losing the token would mean registering again over BLE
        await _local.saveToken(device.id, token);
        final all = [..._local.readAll().where((d) => d.id != device.id), device];
        await _local.writeAll(all);
        await _local.setSelectedId(device.id);
        _clients.remove(device.id); // drop the client that used the old token
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> remove(String id) => guard(() async {
        await _local.writeAll(_local.readAll().where((d) => d.id != id).toList());
        await _local.deleteToken(id);
        if (_local.selectedId == id) await _local.setSelectedId(null);
        _clients.remove(id);
        return unit;
      });

  @override
  Future<Either<Failure, DeviceEndpoint?>> endpoint(String id) => guard(() async {
        final device = _local.readAll().where((d) => d.id == id).firstOrNull;
        final token = await _local.token(id);
        if (device == null || token == null || device.host == null) return null;
        return DeviceEndpoint(deviceId: id, host: device.host!, port: device.port, token: token);
      });

  @override
  Future<Either<Failure, Device>> rediscover(Device device) => guard(() async {
        final found = await _discovery.find(device.id);
        if (found == null) throw const NetworkException('speaker not found on LAN');
        final updated = device.copyWith(host: () => found.host, port: found.port);
        await _saveDevice(updated);
        return updated;
      });

  @override
  Future<Either<Failure, DeviceStatus>> status(DeviceEndpoint endpoint) => guard(() async {
        final client = _clients.forDevice(endpoint, onEndpointChanged: _onEndpointChanged);
        final json = await client.get<Map<String, dynamic>>(ApiPaths.status);
        return DeviceStatusModel.fromJson(json);
      });

  /// When the client found a new IP via mDNS
  void _onEndpointChanged(DeviceEndpoint e) {
    final device = _local.readAll().where((d) => d.id == e.deviceId).firstOrNull;
    if (device != null) {
      _saveDevice(device.copyWith(host: () => e.host, port: e.port)).ignore();
    }
  }

  Future<void> _saveDevice(Device device) =>
      _local.writeAll([for (final d in _local.readAll()) d.id == device.id ? device : d]);
}
