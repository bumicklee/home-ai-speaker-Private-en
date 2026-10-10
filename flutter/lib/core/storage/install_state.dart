import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Per-install state (design document 3.6 "Reinstall handling").
/// The iOS Keychain survives app deletion, so if the first-run marker is missing, clear secure storage.
class InstallState {
  InstallState(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _installedKey = 'installed';
  static const _phoneIdKey = 'phone_id';

  /// Once at app startup
  Future<void> init() async {
    if (_prefs.getBool(_installedKey) != true) {
      await _secure.deleteAll();
      await _prefs.setBool(_installedKey, true);
    }
    if (_prefs.getString(_phoneIdKey) == null) {
      await _prefs.setString(_phoneIdKey, const Uuid().v4());
    }
  }

  /// The phone_id for `api.pair`. A new one per install (a reinstall registers as a new phone)
  String get phoneId => _prefs.getString(_phoneIdKey)!;
}
