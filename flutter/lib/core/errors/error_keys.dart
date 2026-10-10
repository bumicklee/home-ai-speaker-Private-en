/// Error → ARB key. Every Failure must fill errorKey (led-app left it empty, so localization didn't work).
/// Key names must match `app_ko.arb` and `app_en.arb`.
library;

import '../constants/ble_protocol.dart';
import 'exceptions.dart';

class ErrorKeys {
  ErrorKeys._();
  static const unknown = 'errorUnknown';
  static const network = 'errorNetwork';
  static const cache = 'errorCache';
  static const deviceUnreachable = 'errorDeviceUnreachable';
  static const deviceUnauthorized = 'errorDeviceUnauthorized';
  static const deviceRateLimited = 'errorDeviceRateLimited';
  static const deviceTimeout = 'errorDeviceTimeout';
  static const deviceInvalidArg = 'errorDeviceInvalidArg';
  static const deviceBusy = 'errorDeviceBusy';
  static const deviceStorage = 'errorDeviceStorage';
  static const deviceNoApiKey = 'errorDeviceNoApiKey';
  static const deviceNoWifi = 'errorDeviceNoWifi';
  static const deviceVoiceActive = 'errorDeviceVoiceActive';
  static const deviceNotPlaying = 'errorDeviceNotPlaying';
  static const deviceNoTelegramToken = 'errorDeviceNoTelegramToken';
  static const deviceNotFound = 'errorDeviceNotFound';
  static const deviceNotesFull = 'errorDeviceNotesFull';
  static const deviceConflict = 'errorDeviceConflict';
  static const deviceOtaTooLarge = 'errorDeviceOtaTooLarge';
  static const deviceOtaSignature = 'errorDeviceOtaSignature';
  static const bleAdapterOff = 'errorBleAdapterOff';
  static const blePermission = 'errorBlePermission';
  static const bleNotFound = 'errorBleNotFound';
  static const bleConnect = 'errorBleConnect';
  static const bleDisconnected = 'errorBleDisconnected';
  static const bleBondFailed = 'errorBleBondFailed';
  static const bleProtocol = 'errorBleProtocol';
  static const bleTimeout = 'errorBleTimeout';
  static const bleWindowClosed = 'errorBleWindowClosed';
  static const blePhonesFull = 'errorBlePhonesFull';
  static const bleUnsupportedVersion = 'errorBleUnsupportedVersion';
  static const wifiAuth = 'errorWifiAuth';
  static const wifiNotFound = 'errorWifiNotFound';
  static const wifiTimeout = 'errorWifiTimeout';

  /// LAN response (HTTP status + body code) → key
  static String fromDeviceStatus(int status, String? code) {
    switch (code) {
      case 'INVALID_ARG':
        return deviceInvalidArg;
      case 'BUSY':
        return deviceBusy;
      case 'STORAGE_FAIL':
        return deviceStorage;
      case 'NO_API_KEY':
        return deviceNoApiKey;
      case 'NO_WIFI':
        return deviceNoWifi;
      case 'VOICE_ACTIVE':
        return deviceVoiceActive;
      case 'NOT_PLAYING':
        return deviceNotPlaying;
      case 'NO_TOKEN':
        return deviceNoTelegramToken;
      case 'NOT_FOUND':
        return deviceNotFound;
      case 'FULL':
        return deviceNotesFull;
      case 'CONFLICT':
        return deviceConflict;
    }
    switch (status) {
      case 401:
        return deviceUnauthorized;
      case 403:
        return deviceOtaSignature;
      case 404:
        return deviceNotFound;
      case 409:
        return deviceBusy;
      case 413:
        return deviceOtaTooLarge;
      case 429:
        return deviceRateLimited;
    }
    return unknown;
  }

  static String fromBleCode(String code) {
    switch (code) {
      case BleErrorCode.adapterOff:
        return bleAdapterOff;
      case BleErrorCode.permissionDenied:
        return blePermission;
      case BleErrorCode.notFound:
        return bleNotFound;
      case BleErrorCode.connectFailed:
      case BleErrorCode.serviceMissing:
        return bleConnect;
      case BleErrorCode.disconnected:
        return bleDisconnected;
      case BleErrorCode.bondFailed:
        return bleBondFailed;
      case BleErrorCode.timeout:
        return bleTimeout;
    }
    return bleProtocol;
  }

  static String fromBleCommand(String code) {
    switch (code) {
      case BleCmdError.invalidArg:
        return deviceInvalidArg;
      case BleCmdError.busy:
        return deviceBusy;
      case BleCmdError.storageFail:
        return deviceStorage;
      case BleCmdError.notAllowed:
        return bleWindowClosed;
      case BleCmdError.phonesFull:
        return blePhonesFull;
      case BleCmdError.unsupportedVersion:
        return bleUnsupportedVersion;
      case BleCmdError.frameTimeout:
        return bleTimeout;
      case BleCmdError.noApiKey:
        return deviceNoApiKey;
    }
    return bleProtocol;
  }

  static String? fromWifiStatus(WifiProvStatus status) {
    switch (status) {
      case WifiProvStatus.ssidNotFound:
        return wifiNotFound;
      case WifiProvStatus.authFailed:
        return wifiAuth;
      case WifiProvStatus.timeout:
        return wifiTimeout;
      default:
        return null;
    }
  }
}
