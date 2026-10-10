/// Shared handling of secrets and registration commands. provisioning, keys, telegram, and spotify all use only this
/// (no duplicated BLE code per feature; design document Section 3.2). Secrets are never sent over LAN (D6).
library;

import '../ai/ai_choice.dart';
import '../constants/ble_protocol.dart';
import 'ble_command_channel.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.protocolVersion,
    required this.firmware,
    required this.mac,
    required this.provisioned,
    required this.wifiConnected,
    required this.secrets,
    this.ai = AiStatus.legacy,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        protocolVersion: j['protocol_version'] as int? ?? 0,
        firmware: j['fw'] as String? ?? '',
        mac: j['mac'] as String? ?? '',
        provisioned: j['provisioned'] as bool? ?? false,
        wifiConnected: j['wifi_connected'] as bool? ?? false,
        secrets: {
          for (final e in (j['secrets'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value == true,
        },
        // Old firmware (no ai) supports only openai.live
        ai: AiStatus.fromJson(j['ai']),
      );

  final int protocolVersion;
  final String firmware;
  final String mac;
  final bool provisioned;
  final bool wifiConnected;
  final Map<String, bool> secrets;

  /// The AI in use now and the combinations this firmware supports (same shape as `/status.ai`)
  final AiStatus ai;

  /// If the firmware's spec is newer than the app's, the app needs an update
  bool get needsAppUpdate => protocolVersion > BleProtocol.protocolVersion;
}

class PairResult {
  const PairResult({required this.token, required this.phoneId});
  final String token;
  final String phoneId;
}

class BleSecretWriter {
  BleSecretWriter(this._channel);

  final BleCommandChannel _channel;

  Future<DeviceInfo> deviceInfo() async => DeviceInfo.fromJson(await _channel.request(BleOp.deviceInfo));

  Future<void> setSecret(String key, String value) =>
      _channel.request(BleOp.secretSet, {'key': key, 'value': value});

  Future<void> eraseSecret(String key) => _channel.request(BleOp.secretErase, {'key': key});

  /// Registers the phone. When full, throws [BleCommandException] `PHONES_FULL` (list in data['phones']) →
  /// after the user confirms, call again with [evict]
  Future<PairResult> pair({required String phoneId, required String phoneName, String? evict}) async {
    final r = await _channel.request(BleOp.apiPair, {
      'phone_id': phoneId,
      'phone_name': phoneName,
      'evict': ?evict,
    });
    return PairResult(token: r['token'] as String, phoneId: r['phone_id'] as String? ?? phoneId);
  }

  /// After saving, the device immediately tries to refresh the token and returns the result
  Future<void> linkSpotify({required String clientId, required String refreshToken}) =>
      _channel.request(BleOp.spotifyLink, {'client_id': clientId, 'refresh_token': refreshToken});

  Future<void> logoutSpotify() => _channel.request(BleOp.spotifyLogout);

  Future<Map<String, dynamic>> getSettings(String group) async =>
      (await _channel.request(BleOp.settingsGet, {'group': group}))['value'] as Map<String, dynamic>? ?? const {};

  Future<void> setSettings(String group, Map<String, Object?> value) =>
      _channel.request(BleOp.settingsSet, {'group': group, 'value': value});

  /// Apply written values, close the BLE window, no reboot
  Future<void> close() => _channel.request(BleOp.provClose);
}
