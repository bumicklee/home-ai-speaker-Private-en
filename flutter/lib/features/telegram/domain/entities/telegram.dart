import 'package:equatable/equatable.dart';

/// The speaker's Telegram connection state (firmware `telegram_state_name`)
class TelegramState {
  TelegramState._();
  static const off = 'off'; // no token
  static const connecting = 'connecting';
  static const ok = 'ok';
  static const conflict = 'conflict'; // the same bot is being polled elsewhere, or a webhook is set (TLG-13)
  static const tokenInvalid = 'token_invalid';
}

/// One registered chat (`chats[]`: chat_id, alias, title, type)
class TelegramChat extends Equatable {
  const TelegramChat({required this.chatId, required this.alias, this.title = '', this.type = 'private'});

  final int chatId;

  /// The name you say by voice ("send it to Mom"). Up to 32 bytes
  final String alias;

  /// Telegram chat name (a person's name for a private chat)
  final String title;

  /// private / group / supergroup / channel
  final String type;

  bool get isGroup => type == 'group' || type == 'supergroup';

  TelegramChat copyWith({String? alias}) =>
      TelegramChat(chatId: chatId, alias: alias ?? this.alias, title: title, type: type);

  @override
  List<Object?> get props => [chatId, alias, title, type];
}

/// All of `GET /telegram/chats` plus whether a token exists
class TelegramOverview extends Equatable {
  const TelegramOverview({
    required this.state,
    this.bot = '',
    this.unread = 0,
    this.chats = const [],
    this.hasToken = true,
  });

  final String state;

  /// Bot username (without @). Empty string if not connected yet
  final String bot;
  final int unread;
  final List<TelegramChat> chats;

  /// Whether the speaker has a bot token. Rechecked with /status only when state is off
  final bool hasToken;

  TelegramOverview copyWith({String? state, String? bot, int? unread, List<TelegramChat>? chats, bool? hasToken}) =>
      TelegramOverview(
        state: state ?? this.state,
        bot: bot ?? this.bot,
        unread: unread ?? this.unread,
        chats: chats ?? this.chats,
        hasToken: hasToken ?? this.hasToken,
      );

  @override
  List<Object?> get props => [state, bot, unread, chats, hasToken];
}

/// Message notification options (`auto_read`, `quiet_start`, `quiet_end`; hours are 0–23)
class TelegramOptions extends Equatable {
  const TelegramOptions({this.autoRead = false, this.quietStart = 22, this.quietEnd = 7});

  final bool autoRead;
  final int quietStart;
  final int quietEnd;

  TelegramOptions copyWith({bool? autoRead, int? quietStart, int? quietEnd}) => TelegramOptions(
        autoRead: autoRead ?? this.autoRead,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );

  @override
  List<Object?> get props => [autoRead, quietStart, quietEnd];
}

/// `POST /telegram/pair` response: 6-digit code (single use, void after 5 wrong attempts)
class PairingCode extends Equatable {
  const PairingCode({required this.code, required this.expiresIn, this.bot = ''});

  final String code;
  final Duration expiresIn;

  /// In a group, send it as `/pair@botname code`
  final String bot;

  @override
  List<Object?> get props => [code, expiresIn, bot];
}

/// `tg_paired` event: a newly registered chat
class PairedChat extends Equatable {
  const PairedChat({required this.chatId, this.title = '', this.type = 'private'});

  final int chatId;
  final String title;
  final String type;

  @override
  List<Object?> get props => [chatId, title, type];
}
