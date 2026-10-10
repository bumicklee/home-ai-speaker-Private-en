import 'package:dartz/dartz.dart';

import '../../../../core/ble/ble_speaker.dart';
import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../../../core/services/device_event_service.dart';
import '../../domain/entities/telegram.dart';
import '../../domain/repositories/telegram_repository.dart';
import '../datasources/telegram_bot_api_datasource.dart';
import '../datasources/telegram_remote_datasource.dart';
import '../models/telegram_models.dart';

class TelegramRepositoryImpl implements TelegramRepository {
  TelegramRepositoryImpl(this._remote, this._botApi, this._ble, this._device, this._events);

  final TelegramRemoteDataSource _remote;
  final TelegramBotApiDataSource _botApi;
  final BleSpeakerDataSource _ble;
  final CurrentDevice _device;
  final DeviceEventService _events;

  @override
  Future<Either<Failure, TelegramOverview>> overview() => guard(() async {
        final j = await _remote.chats();
        var hasToken = true;
        // off means "no token", but it can also be off right after enabling (before polling starts), so check with /status
        if ((j['state'] as String? ?? TelegramState.off) == TelegramState.off) {
          hasToken = (await _remote.secrets())[SecretKey.telegramBot] == true;
        }
        return TelegramModels.overview(j, hasToken: hasToken);
      });

  @override
  Future<Either<Failure, Unit>> rename(int chatId, String alias) => guard(() async {
        await _remote.rename(chatId, alias);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> remove(int chatId) => guard(() async {
        await _remote.remove(chatId);
        return unit;
      });

  @override
  Future<Either<Failure, TelegramOptions>> options() =>
      guard(() async => TelegramModels.options(await _remote.options()));

  @override
  Future<Either<Failure, TelegramOptions>> saveOptions(TelegramOptions options) =>
      guard(() async => TelegramModels.options(await _remote.saveOptions(TelegramModels.optionsToJson(options))));

  @override
  Future<Either<Failure, PairingCode>> startPairing() => guard(() async => TelegramModels.pairing(await _remote.pair()));

  @override
  Future<Either<Failure, String?>> checkToken(String token) => guard(() => _botApi.getMe(token));

  @override
  Future<Either<Failure, Unit>> saveTokenToSpeaker(String token) => guard(() async {
        final id = _device.deviceId;
        if (id == null) throw const BleException(BleErrorCode.notFound, 'no device selected');
        final session = await _ble.connectById(id);
        try {
          await session.setSecret(SecretKey.telegramBot, token);
          await session.closeWindow(); // Applied without a reboot. The speaker reconnects with the new token
        } finally {
          try {
            await session.disconnect();
          } catch (_) {}
        }
        return unit;
      });

  @override
  Stream<PairedChat> paired() => _events.on(DeviceEventType.tgPaired).map((e) => TelegramModels.paired(e.data));

  @override
  Stream<String> statusChanges() =>
      _events.on(DeviceEventType.tgStatus).map((e) => e.data['state'] as String? ?? TelegramState.off);

  @override
  Stream<int> unreadChanges() =>
      _events.on(DeviceEventType.tgMessage).map((e) => (e.data['unread'] as num? ?? 0).toInt());
}
