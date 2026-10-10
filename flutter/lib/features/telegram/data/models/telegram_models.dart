/// LAN API JSON ↔ entities (firmware telegram handlers in `local_api.c`, `tg_store.c`, `api_events.c`)
library;

import '../../domain/entities/telegram.dart';

/// chat_id arrives as a cJSON number (double). Groups are negative (-100…)
int _id(Object? v) => (v as num? ?? 0).toInt();

class TelegramModels {
  TelegramModels._();

  /// `{chat_id, alias, title, type}`
  static TelegramChat chat(Map<String, dynamic> j) => TelegramChat(
        chatId: _id(j['chat_id']),
        alias: j['alias'] as String? ?? '',
        title: j['title'] as String? ?? '',
        type: j['type'] as String? ?? 'private',
      );

  /// `{chats: [...], state, bot, unread}`
  static TelegramOverview overview(Map<String, dynamic> j, {bool hasToken = true}) => TelegramOverview(
        state: j['state'] as String? ?? TelegramState.off,
        bot: j['bot'] as String? ?? '',
        unread: (j['unread'] as num? ?? 0).toInt(),
        chats: [
          for (final c in (j['chats'] as List<dynamic>? ?? const []))
            if (c is Map<String, dynamic>) chat(c),
        ],
        hasToken: hasToken,
      );

  /// `{auto_read, quiet_start, quiet_end}`
  static TelegramOptions options(Map<String, dynamic> j) => TelegramOptions(
        autoRead: j['auto_read'] == true,
        quietStart: (j['quiet_start'] as num? ?? 22).toInt(),
        quietEnd: (j['quiet_end'] as num? ?? 7).toInt(),
      );

  static Map<String, dynamic> optionsToJson(TelegramOptions o) =>
      {'auto_read': o.autoRead, 'quiet_start': o.quietStart, 'quiet_end': o.quietEnd};

  /// `{code, expires_s, bot}`
  static PairingCode pairing(Map<String, dynamic> j) => PairingCode(
        code: j['code'] as String? ?? '',
        expiresIn: Duration(seconds: (j['expires_s'] as num? ?? 300).toInt()),
        bot: j['bot'] as String? ?? '',
      );

  /// WS `tg_paired`: `{chat_id, title, type}`
  static PairedChat paired(Map<String, dynamic> j) => PairedChat(
        chatId: _id(j['chat_id']),
        title: j['title'] as String? ?? '',
        type: j['type'] as String? ?? 'private',
      );
}
