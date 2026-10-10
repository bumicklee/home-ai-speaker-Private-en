/// BLE work with the speaker (design document Sections 2.13, 3.4). First-time setup, the Telegram token, and adding a phone all use this.
/// The real implementation is BleLink and BleSecretWriter; tests use a fake.
library;

import 'dart:async';

import '../constants/ble_protocol.dart';
import '../errors/exceptions.dart';
import '../services/ble_permission_service.dart';
import 'ble_link.dart';
import 'ble_secret_writer.dart';
import 'wifi_scan.dart';

/// One connected speaker
abstract interface class BleSpeakerSession {
  /// Device identifier (0xFF61 STA MAC)
  String get mac;
  Future<DeviceInfo> deviceInfo();
  Future<List<WifiNetwork>> scanWifi();
  Future<WifiProvStatus> provisionWifi(String ssid, String password);
  Future<void> setSecret(String key, String value);
  Future<void> eraseSecret(String key);
  Future<PairResult> pair({required String phoneId, required String phoneName, String? evict});

  /// `settings.set` (partial update). Choosing an AI with no key gives [BleCommandException] `NO_API_KEY`
  Future<void> setSettings(String group, Map<String, Object?> value);

  /// 0xFF88: if Wi-Fi was changed, save and reboot; otherwise just close the BLE window
  Future<void> finish();

  /// prov.close: apply written values, close the BLE window, no reboot (the end of any task other than first-time setup)
  Future<void> closeWindow();
  Future<void> disconnect();
}

abstract interface class BleSpeakerDataSource {
  /// Check permissions + that Bluetooth is on
  Future<void> ensureReady();
  Stream<List<DiscoveredSpeaker>> scan();
  Future<BleSpeakerSession> connect(DiscoveredSpeaker speaker);

  /// Finds and connects to an already registered speaker (device ID = STA MAC). Call it after the user holds Key2 for 3 seconds to open the BLE window.
  /// If no advertisement shows up within [timeout], throws [BleException] notFound
  Future<BleSpeakerSession> connectById(String deviceId, {Duration timeout});
  Future<String> defaultPhoneName();
}

class BleSpeakerDataSourceImpl implements BleSpeakerDataSource {
  BleSpeakerDataSourceImpl(this._permissions);

  final BlePermissionService _permissions;

  @override
  Future<void> ensureReady() async {
    await _permissions.ensureGranted();
    await BleScanner.ensureOn();
  }

  @override
  Stream<List<DiscoveredSpeaker>> scan() => BleScanner.scan();

  @override
  Future<BleSpeakerSession> connect(DiscoveredSpeaker speaker) async =>
      _BleSession(await BleLink.connect(speaker.device));

  @override
  Future<BleSpeakerSession> connectById(String deviceId, {Duration timeout = const Duration(seconds: 20)}) async {
    await ensureReady();
    final shortId = deviceId.substring(deviceId.length - 6).toUpperCase();
    DiscoveredSpeaker? target;
    await for (final list in BleScanner.scan(timeout: timeout)) {
      target = list.where((s) => s.shortId.toUpperCase() == shortId).firstOrNull;
      if (target != null) break;
    }
    if (target == null) throw const BleException(BleErrorCode.notFound);
    final session = await connect(target);
    if (session.mac.toUpperCase() != deviceId.toUpperCase()) {
      await session.disconnect();
      throw const BleException(BleErrorCode.notFound, 'another speaker with the same short id');
    }
    return session;
  }

  @override
  Future<String> defaultPhoneName() => _permissions.phoneName();
}

class _BleSession implements BleSpeakerSession {
  _BleSession(this._link) : _writer = BleSecretWriter(_link.commands);

  final BleLink _link;
  final BleSecretWriter _writer;

  @override
  String get mac => _link.mac;

  @override
  Future<DeviceInfo> deviceInfo() => _writer.deviceInfo();

  @override
  Future<List<WifiNetwork>> scanWifi() => _link.scanWifi();

  @override
  Future<WifiProvStatus> provisionWifi(String ssid, String password) => _link.provisionWifi(ssid, password);

  @override
  Future<void> setSecret(String key, String value) => _writer.setSecret(key, value);

  @override
  Future<void> eraseSecret(String key) => _writer.eraseSecret(key);

  @override
  Future<void> closeWindow() async {
    try {
      await _writer.close();
    } on BleException catch (e) {
      // The device may drop the connection as it closes, so the response may never arrive
      if (e.code != BleErrorCode.disconnected && e.code != BleErrorCode.timeout) rethrow;
    }
  }

  @override
  Future<PairResult> pair({required String phoneId, required String phoneName, String? evict}) =>
      _writer.pair(phoneId: phoneId, phoneName: phoneName, evict: evict);

  @override
  Future<void> setSettings(String group, Map<String, Object?> value) => _writer.setSettings(group, value);

  @override
  Future<void> finish() async {
    try {
      await _link.provisioningDone();
    } catch (_) {
      // The device reboots right away and drops the connection, so the write response may never arrive. The device has already saved
    }
  }

  @override
  Future<void> disconnect() => _link.disconnect();
}
