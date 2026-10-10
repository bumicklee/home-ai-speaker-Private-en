/// BLE GATT specification — the only file that must match the firmware's `app_config.h` and design document Section 2.13 one to one.
/// If you change a value, change the firmware too.
library;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProtocol {
  BleProtocol._();

  /// Advertising name prefix. Last 6 characters = last 6 of the Wi-Fi STA MAC
  static const namePrefix = 'JARVIS_';

  /// `protocol_version` in `device.info`. If the firmware's is higher, prompt for an app update
  static const protocolVersion = 1;

  // Service and characteristics (16-bit)
  static final svcWifi = Guid('ff50');
  static final chrSsid = Guid('ff51');
  static final chrPassword = Guid('ff52');
  static final chrStatus = Guid('ff53');
  static final chrScan = Guid('ff54');

  static final svcDevice = Guid('ff60');
  static final chrMac = Guid('ff61');
  static final chrProduct = Guid('ff62');
  static final chrFirmware = Guid('ff63');

  static final svcConfig = Guid('ff80');
  static final chrCmdRx = Guid('ff81');
  static final chrCmdTx = Guid('ff82');
  static final chrProvDone = Guid('ff88');

  static const productCode = 'AISPK-S3-V1';

  // Length limits (UTF-8 bytes)
  static const ssidMaxBytes = 32;
  static const passwordMaxBytes = 64;

  // Settings command protocol (0xFF81/0xFF82)
  static const flagLast = 0x01;
  static const flagFirst = 0x02;
  static const frameHeaderBytes = 2;

  /// ATT header 3B + frame header 2B. Frame payload = MTU − 5
  static const mtuOverhead = 5;
  static const androidMtuRequest = 247;
  static const cmdMaxBytes = 4096;
  static const maxFrames = 256;
  static const cmdTimeout = Duration(seconds: 10);

  /// Values written to 0xFF88
  static const provDoneValue = 0x01;

  /// BLE window opened by holding Key2 for 3 seconds: 5 minutes with no connection, up to 15 minutes while connected
  static const windowIdle = Duration(minutes: 5);
  static const windowMax = Duration(minutes: 15);

  // 0xFF54 scan notifications
  static const scanEntryBytes = 34;
  static const scanFailed = 0xFF;
  static const scanMaxEntries = 20;
}

/// 0xFF53 Wi-Fi status. 2–5 are terminal statuses and arrive only once per password write.
enum WifiProvStatus {
  idle(0),
  connecting(1),
  success(2),
  ssidNotFound(3),
  authFailed(4),
  timeout(5);

  const WifiProvStatus(this.code);
  final int code;

  bool get isFinal => code >= 2;

  static WifiProvStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// 0xFF54 security values (the design document's table, not IDF numbers)
enum WifiSecurity {
  open(0),
  wep(1),
  wpa(2),
  wpa2(3),
  wpaWpa2(4),
  wpa3(5),
  wpa2Wpa3(6),
  enterprise(7),
  other(255);

  const WifiSecurity(this.code);
  final int code;

  bool get needsPassword => this != open;

  static WifiSecurity fromCode(int code) =>
      values.firstWhere((s) => s.code == code, orElse: () => other);
}

/// 0xFF81 command names
class BleOp {
  BleOp._();
  static const deviceInfo = 'device.info';
  static const secretSet = 'secret.set';
  static const secretErase = 'secret.erase';
  static const settingsGet = 'settings.get';
  static const settingsSet = 'settings.set';
  static const apiPair = 'api.pair';
  static const spotifyLink = 'spotify.link';
  static const spotifyLogout = 'spotify.logout';
  static const provClose = 'prov.close';
}

/// `secret.set` / `secret.erase` keys
class SecretKey {
  SecretKey._();
  static const openai = 'openai_key';
  static const gemini = 'gemini_key';
  static const telegramBot = 'tg_bot_token';
}

/// 0xFF82 response error codes
class BleCmdError {
  BleCmdError._();
  static const invalidArg = 'INVALID_ARG';
  static const unknownOp = 'UNKNOWN_OP';
  static const tooLarge = 'TOO_LARGE';
  static const frameTimeout = 'FRAME_TIMEOUT';
  static const busy = 'BUSY';
  static const storageFail = 'STORAGE_FAIL';
  static const notAllowed = 'NOT_ALLOWED';
  static const phonesFull = 'PHONES_FULL';
  static const unsupportedVersion = 'UNSUPPORTED_VERSION';

  /// Chose an AI with no key in `settings.set assistant` (LAN uses the same name with 409)
  static const noApiKey = 'NO_API_KEY';
}
