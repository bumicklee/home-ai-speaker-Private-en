import 'package:dartz/dartz.dart';

import '../../../../core/ble/ble_link.dart';
import '../../../../core/ble/ble_secret_writer.dart';
import '../../../../core/ble/wifi_scan.dart';
import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/errors/failures.dart';
import '../../../devices/domain/entities/device.dart';

abstract interface class ProvisioningRepository {
  Future<Either<Failure, Unit>> ensureReady();
  Stream<List<DiscoveredSpeaker>> scan();
  Future<String> defaultPhoneName();

  /// This installation's phone ID (api.pair)
  String get phoneId;

  Future<Either<Failure, DeviceInfo>> connect(DiscoveredSpeaker speaker);
  Future<Either<Failure, List<WifiNetwork>>> scanWifi();
  Future<Either<Failure, WifiProvStatus>> provisionWifi(String ssid, String password);
  Future<Either<Failure, Unit>> setSecret(String key, String value);
  Future<Either<Failure, PairResult>> pair(String phoneName, {String? evict});

  /// BLE `settings.set` (the AI and mode chosen after registration). BleFailure code `NO_API_KEY` if there is no key
  Future<Either<Failure, Unit>> setSettings(String group, Map<String, Object?> value);
  Future<Either<Failure, Unit>> finish();
  Future<void> disconnect();

  /// Finds it again over mDNS after the reboot. If not found, returns without a host
  Future<Device> discover(String mac, String name, {Duration timeout});

  /// Save on the phone (the token goes to secure storage)
  Future<Either<Failure, Unit>> save(Device device, String token);
}
