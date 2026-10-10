import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/device_endpoint.dart';
import '../entities/device.dart';
import '../entities/device_status.dart';

abstract interface class DevicesRepository {
  Future<Either<Failure, List<Device>>> devices();

  /// Selected device id (the first device if none)
  Future<Either<Failure, String?>> selectedId();
  Future<Either<Failure, Unit>> select(String id);

  /// Register or re-register: add or replace it in the list and save the token. Provisioning calls only this (design document 3.2)
  Future<Either<Failure, Unit>> addOrUpdate(Device device, String token);

  /// Removes it from the phone only (unregistering on the speaker side is the system feature)
  Future<Either<Failure, Unit>> remove(String id);

  /// LAN address. null if there is no token or address
  Future<Either<Failure, DeviceEndpoint?>> endpoint(String id);

  /// If the address is unknown or has changed, find it again via mDNS and save it
  Future<Either<Failure, Device>> rediscover(Device device);

  Future<Either<Failure, DeviceStatus>> status(DeviceEndpoint endpoint);
}
