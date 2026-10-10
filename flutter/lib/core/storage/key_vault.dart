import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets remembered on the phone (2026-10-03 user request: remember the OpenAI and Gemini keys and Telegram bot token, once entered).
/// Encrypted secure storage via iOS Keychain / Android Keystore. Emptied by InstallState on uninstall and reinstall.
/// Sent to the speaker only over BLE (never over LAN, D6).
class KeyVault {
  KeyVault(this._storage);

  final FlutterSecureStorage _storage;
  static const _openAi = 'vault_openai_key';
  static const _gemini = 'vault_gemini_key';
  static const _telegram = 'vault_tg_bot_token';

  Future<String?> openAiKey() => _storage.read(key: _openAi);
  Future<String?> geminiKey() => _storage.read(key: _gemini);
  Future<String?> telegramToken() => _storage.read(key: _telegram);

  Future<void> saveOpenAiKey(String? value) => _save(_openAi, value);
  Future<void> saveGeminiKey(String? value) => _save(_gemini, value);
  Future<void> saveTelegramToken(String? value) => _save(_telegram, value);

  Future<void> _save(String key, String? value) =>
      value == null || value.isEmpty ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}
