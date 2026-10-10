import 'package:dio/dio.dart';

import '../../../../core/errors/exceptions.dart';

/// Telegram Bot API (external). Calls only `getMe`, to check the token (design document, Section 3.2).
/// The token goes into the URL, so never put the URL or the raw exception text in logs or a Failure.
class TelegramBotApiDataSource {
  TelegramBotApiDataSource(this._dio);

  final Dio _dio;

  /// BotFather token shape (`123456789:AA…`). If it doesn't match, nothing is sent (it goes straight into the URL path)
  static final tokenPattern = RegExp(r'^\d{5,}:[A-Za-z0-9_-]{30,}$');

  /// If valid, the bot's username (without @); null if Telegram rejects it (401 or 404)
  Future<String?> getMe(String token) async {
    if (!tokenPattern.hasMatch(token)) return null;
    try {
      final r = await _dio.get<Map<String, dynamic>>('https://api.telegram.org/bot$token/getMe');
      final result = r.data?['result'];
      final username = result is Map<String, dynamic> ? result['username'] as String? : null;
      if (r.data?['ok'] != true || username == null) return null;
      return username;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 404) return null; // Telegram returns 404 for a malformed token
      // Drop the raw text (e.message): it may contain the URL
      throw NetworkException(status == null ? 'telegram unreachable' : 'telegram HTTP $status');
    }
  }
}
