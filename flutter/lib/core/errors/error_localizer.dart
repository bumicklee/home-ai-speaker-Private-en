import '../../l10n/app_localizations.dart';
import 'error_keys.dart';
import 'failures.dart';

/// Failure.errorKey → localized message
extension ErrorLocalizer on AppLocalizations {
  String errorText(Failure failure) => errorKeyText(failure.errorKey);

  String errorKeyText(String key) {
    final l = this;
    return switch (key) {
    ErrorKeys.unknown => l.errorUnknown,
    ErrorKeys.network => l.errorNetwork,
    ErrorKeys.cache => l.errorCache,
    ErrorKeys.deviceUnreachable => l.errorDeviceUnreachable,
    ErrorKeys.deviceUnauthorized => l.errorDeviceUnauthorized,
    ErrorKeys.deviceRateLimited => l.errorDeviceRateLimited,
    ErrorKeys.deviceTimeout => l.errorDeviceTimeout,
    ErrorKeys.deviceInvalidArg => l.errorDeviceInvalidArg,
    ErrorKeys.deviceBusy => l.errorDeviceBusy,
    ErrorKeys.deviceStorage => l.errorDeviceStorage,
    ErrorKeys.deviceNoApiKey => l.errorDeviceNoApiKey,
    ErrorKeys.deviceNoWifi => l.errorDeviceNoWifi,
    ErrorKeys.deviceVoiceActive => l.errorDeviceVoiceActive,
    ErrorKeys.deviceNotFound => l.errorDeviceNotFound,
    ErrorKeys.deviceNotesFull => l.errorDeviceNotesFull,
    ErrorKeys.deviceConflict => l.errorDeviceConflict,
    ErrorKeys.deviceOtaTooLarge => l.errorDeviceOtaTooLarge,
    ErrorKeys.deviceOtaSignature => l.errorDeviceOtaSignature,
    ErrorKeys.bleAdapterOff => l.errorBleAdapterOff,
    ErrorKeys.blePermission => l.errorBlePermission,
    ErrorKeys.bleNotFound => l.errorBleNotFound,
    ErrorKeys.bleConnect => l.errorBleConnect,
    ErrorKeys.bleDisconnected => l.errorBleDisconnected,
    ErrorKeys.bleBondFailed => l.errorBleBondFailed,
    ErrorKeys.bleProtocol => l.errorBleProtocol,
    ErrorKeys.bleTimeout => l.errorBleTimeout,
    ErrorKeys.bleWindowClosed => l.errorBleWindowClosed,
    ErrorKeys.blePhonesFull => l.errorBlePhonesFull,
    ErrorKeys.bleUnsupportedVersion => l.errorBleUnsupportedVersion,
    ErrorKeys.wifiAuth => l.errorWifiAuth,
    ErrorKeys.wifiNotFound => l.errorWifiNotFound,
    ErrorKeys.wifiTimeout => l.errorWifiTimeout,
      _ => l.errorUnknown,
    };
  }
}
