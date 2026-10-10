import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../errors/exceptions.dart';

/// BLE permissions (design document Section 3.6).
/// Android 12+: BLUETOOTH_SCAN (neverForLocation) and CONNECT. Android 11 and below: location permission.
/// iOS: the OS asks the first time BLE is used (we don't ask here, so permission_handler's iOS macro setup isn't needed).
class BlePermissionService {
  BlePermissionService({DeviceInfoPlugin? info}) : _info = info ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _info;

  /// Throws [BleException] permissionDenied if denied
  Future<void> ensureGranted() async {
    if (!Platform.isAndroid) return;
    final sdk = (await _info.androidInfo).version.sdkInt;
    final permissions =
        sdk >= 31 ? [Permission.bluetoothScan, Permission.bluetoothConnect] : [Permission.locationWhenInUse];
    final result = await permissions.request();
    if (!result.values.every((s) => s.isGranted || s.isLimited)) {
      throw const BleException(BleErrorCode.permissionDenied);
    }
  }

  /// Default phone name on the registration screen (the user can edit it)
  Future<String> phoneName() async {
    try {
      if (Platform.isAndroid) {
        final a = await _info.androidInfo;
        return '${a.manufacturer} ${a.model}'.trim();
      }
      if (Platform.isIOS) {
        final i = await _info.iosInfo;
        return i.name.isNotEmpty ? i.name : 'iPhone';
      }
    } catch (_) {}
    return 'Phone';
  }
}
