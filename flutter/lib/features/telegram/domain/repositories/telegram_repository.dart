import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/telegram.dart';

/// Telegram (design document, Sections 2.11 and 3.5). The token goes to the speaker over BLE only (D6). The app never calls getUpdates
abstract interface class TelegramRepository {
  /// Chats, state, bot name, unread count
  Future<Either<Failure, TelegramOverview>> overview();

  /// Change the alias (cannot be empty, 32 bytes or less)
  Future<Either<Failure, Unit>> rename(int chatId, String alias);
  Future<Either<Failure, Unit>> remove(int chatId);

  Future<Either<Failure, TelegramOptions>> options();

  /// Sends only changed values. The speaker returns all saved values
  Future<Either<Failure, TelegramOptions>> saveOptions(TelegramOptions options);

  /// 6-digit pairing code. DeviceFailure 409 (`NO_TOKEN`) if there is no token
  Future<Either<Failure, PairingCode>> startPairing();

  /// Check the token with Telegram `getMe`. If valid, the bot's username; null if Telegram rejects it
  Future<Either<Failure, String?>> checkToken(String token);

  /// Save the token to the speaker over BLE (after the user holds Key2 for 3 seconds to open the BLE window)
  Future<Either<Failure, Unit>> saveTokenToSpeaker(String token);

  /// Newly registered chat (WS `tg_paired`)
  Stream<PairedChat> paired();

  /// Connection state (WS `tg_status`)
  Stream<String> statusChanges();

  /// Unread count (WS `tg_message`)
  Stream<int> unreadChanges();
}
