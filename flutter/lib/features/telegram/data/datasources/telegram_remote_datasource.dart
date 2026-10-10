import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';

/// Telegram LAN API of the selected speaker (design document, Section 2.14). DeviceApiClient turns errors into AppException and throws them
class TelegramRemoteDataSource {
  TelegramRemoteDataSource(this._device);

  final CurrentDevice _device;

  /// `{chats, state, bot, unread}`
  Future<Map<String, dynamic>> chats() => _device.client.get<Map<String, dynamic>>(ApiPaths.telegramChats);

  /// `secrets` from `/status` (a bool per key). Used to recheck whether a token exists when state is off
  Future<Map<String, dynamic>> secrets() async {
    final j = await _device.client.get<Map<String, dynamic>>(ApiPaths.status);
    return j['secrets'] as Map<String, dynamic>? ?? const {};
  }

  /// 400 INVALID_ARG (empty or over 32 bytes), 404 NOT_FOUND
  Future<void> rename(int chatId, String alias) =>
      _device.client.put<dynamic>(ApiPaths.telegramChat(chatId), {'alias': alias});

  Future<void> remove(int chatId) => _device.client.delete<dynamic>(ApiPaths.telegramChat(chatId));

  /// `{auto_read, quiet_start, quiet_end}`
  Future<Map<String, dynamic>> options() => _device.client.get<Map<String, dynamic>>(ApiPaths.telegramOptions);

  /// Returns all values after saving. 400 INVALID_ARG (unknown key or outside 0–23)
  Future<Map<String, dynamic>> saveOptions(Map<String, dynamic> body) =>
      _device.client.put<Map<String, dynamic>>(ApiPaths.telegramOptions, body);

  /// `{code, expires_s, bot}`. 409 NO_TOKEN if there is no token
  Future<Map<String, dynamic>> pair() => _device.client.post<Map<String, dynamic>>(ApiPaths.telegramPair);
}
