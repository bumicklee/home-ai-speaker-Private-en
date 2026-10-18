import 'dart:async';

import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/features/telegram/domain/entities/telegram.dart';
import 'package:aispeaker/features/telegram/domain/repositories/telegram_repository.dart';
import 'package:aispeaker/features/telegram/presentation/bloc/telegram_connect_cubit.dart';
import 'package:aispeaker/features/telegram/presentation/bloc/telegram_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements TelegramRepository {}

class MockVault extends Mock implements KeyVault {}

const token = '7712345678:AAHabcdefghijklmnopqrstuvwxyz012345';
const mom = TelegramChat(chatId: 1, alias: 'Mom', title: 'Kim Mira');
const family = TelegramChat(chatId: -100, alias: 'Family', title: 'Our Family', type: 'group');
const overview = TelegramOverview(state: 'ok', bot: 'jarvis_home_bot', unread: 2, chats: [mom, family]);
const options = TelegramOptions(autoRead: false, quietStart: 22, quietEnd: 7);
const code = PairingCode(code: '482913', expiresIn: Duration(minutes: 5), bot: 'jarvis_home_bot');
const storage = DeviceFailure(errorKey: ErrorKeys.deviceStorage, status: 500, code: 'STORAGE_FAIL');

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late MockRepo repo;
  late MockVault vault;
  late StreamController<PairedChat> paired;
  late StreamController<String> status;
  late StreamController<int> unread;

  setUpAll(() => registerFallbackValue(const TelegramOptions()));

  setUp(() {
    repo = MockRepo();
    vault = MockVault();
    paired = StreamController<PairedChat>.broadcast();
    status = StreamController<String>.broadcast();
    unread = StreamController<int>.broadcast();
    when(() => repo.paired()).thenAnswer((_) => paired.stream);
    when(() => repo.statusChanges()).thenAnswer((_) => status.stream);
    when(() => repo.unreadChanges()).thenAnswer((_) => unread.stream);
    when(() => repo.overview()).thenAnswer((_) async => const Right(overview));
    when(() => repo.options()).thenAnswer((_) async => const Right(options));
    when(() => vault.telegramToken()).thenAnswer((_) async => null);
    when(() => vault.saveTelegramToken(any())).thenAnswer((_) async {});
  });

  group('TelegramCubit', () {
    test('load: chats, state, options', () async {
      final c = TelegramCubit(repo);
      await c.load();
      expect(c.state.loading, isFalse);
      expect(c.state.overview, overview);
      expect(c.state.options, options);
      expect(c.state.needsSetup, isFalse);
      await c.close();
    });

    test('no token → connect screen', () async {
      when(() => repo.overview())
          .thenAnswer((_) async => const Right(TelegramOverview(state: 'off', hasToken: false)));
      final c = TelegramCubit(repo);
      await c.load();
      expect(c.state.needsSetup, isTrue);
      await c.close();
    });

    test('load failure', () async {
      when(() => repo.overview()).thenAnswer((_) async => const Left(NetworkFailure()));
      final c = TelegramCubit(repo);
      await c.load();
      expect(c.state.failure, const NetworkFailure());
      expect(c.state.overview, isNull);
      await c.close();
    });

    test('rename alias: applied immediately', () async {
      when(() => repo.rename(1, 'Mother')).thenAnswer((_) async => const Right(unit));
      final c = TelegramCubit(repo);
      await c.load();
      expect(await c.rename(1, 'Mother'), isTrue);
      expect(c.state.overview!.chats.first.alias, 'Mother');
      expect(c.state.actionFailure, isNull);
      await c.close();
    });

    test('rename alias failure: reverts and notifies', () async {
      const invalid = DeviceFailure(errorKey: ErrorKeys.deviceInvalidArg, status: 400, code: 'INVALID_ARG');
      when(() => repo.rename(any(), any())).thenAnswer((_) async => const Left(invalid));
      final c = TelegramCubit(repo);
      await c.load();
      expect(await c.rename(1, 'x'), isFalse);
      expect(c.state.overview!.chats.first.alias, 'Mom');
      expect(c.state.actionFailure, invalid);
      await c.close();
    });

    test('delete', () async {
      when(() => repo.remove(-100)).thenAnswer((_) async => const Right(unit));
      final c = TelegramCubit(repo);
      await c.load();
      await c.remove(-100);
      expect(c.state.overview!.chats, [mom]);
      await c.close();
    });

    test('saving options: uses the values the speaker returns, reverts on failure', () async {
      when(() => repo.saveOptions(any()))
          .thenAnswer((_) async => const Right(TelegramOptions(autoRead: true, quietStart: 22, quietEnd: 7)));
      final c = TelegramCubit(repo);
      await c.load();
      await c.setAutoRead(true);
      expect(c.state.options.autoRead, isTrue);
      verify(() => repo.saveOptions(const TelegramOptions(autoRead: true, quietStart: 22, quietEnd: 7))).called(1);

      when(() => repo.saveOptions(any())).thenAnswer((_) async => const Left(storage));
      await c.setQuietHours(23, 6);
      expect(c.state.options, const TelegramOptions(autoRead: true, quietStart: 22, quietEnd: 7));
      expect(c.state.actionFailure, storage);
      await c.close();
    });

    test('events: applies tg_status and tg_message, reloads on tg_paired', () async {
      final c = TelegramCubit(repo);
      await c.load();
      status.add('conflict');
      unread.add(5);
      await pump();
      expect(c.state.overview!.state, 'conflict');
      expect(c.state.overview!.unread, 5);

      paired.add(const PairedChat(chatId: 7));
      await pump();
      verify(() => repo.overview()).called(2);
      await c.close();
    });
  });

  group('TelegramConnectCubit', () {
    test('init: fills in the remembered token', () async {
      when(() => vault.telegramToken()).thenAnswer((_) async => token);
      final c = TelegramConnectCubit(repo, vault);
      await c.init();
      expect(c.state.token, token);
      await c.close();
    });

    test('token check succeeds: bot name, remembered on the phone', () async {
      when(() => repo.checkToken(token)).thenAnswer((_) async => const Right('jarvis_home_bot'));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged(' $token ');
      await c.checkToken();
      expect(c.state.check, TokenCheck.valid);
      expect(c.state.botName, 'jarvis_home_bot');
      verify(() => vault.saveTelegramToken(token)).called(1);
      await c.close();
    });

    test('wrong token: not remembered and saving is blocked', () async {
      when(() => repo.checkToken(any())).thenAnswer((_) async => const Right(null));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged('123:bad');
      await c.checkToken();
      expect(c.state.check, TokenCheck.invalid);
      verifyNever(() => vault.saveTelegramToken(any()));
      await c.saveToSpeaker();
      verifyNever(() => repo.saveTokenToSpeaker(any()));
      await c.close();
    });

    test('cannot reach Telegram', () async {
      when(() => repo.checkToken(any())).thenAnswer((_) async => const Left(NetworkFailure()));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged(token);
      await c.checkToken();
      expect(c.state.check, TokenCheck.failed);
      await c.close();
    });

    test('save → code → tg_paired completes registration', () async {
      when(() => repo.checkToken(token)).thenAnswer((_) async => const Right('jarvis_home_bot'));
      when(() => repo.saveTokenToSpeaker(token)).thenAnswer((_) async => const Right(unit));
      when(() => repo.startPairing()).thenAnswer((_) async => const Right(code));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged(token);
      await c.checkToken();
      await c.saveToSpeaker();
      expect(c.state.save, TokenSave.saved);
      expect(c.state.pairing, Pairing.waiting);
      expect(c.state.code, code);
      expect(c.state.remaining, const Duration(minutes: 5));
      expect(c.state.bot, 'jarvis_home_bot');

      paired.add(const PairedChat(chatId: -100, title: 'Our Family', type: 'group'));
      await pump();
      expect(c.state.pairing, Pairing.paired);
      expect(c.state.pairedChat?.title, 'Our Family');
      await c.close();
    });

    test('BLE save failure: no code is requested', () async {
      const ble = BleFailure(errorKey: ErrorKeys.bleNotFound);
      when(() => repo.checkToken(token)).thenAnswer((_) async => const Right('b'));
      when(() => repo.saveTokenToSpeaker(token)).thenAnswer((_) async => const Left(ble));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged(token);
      await c.checkToken();
      await c.saveToSpeaker();
      expect(c.state.save, TokenSave.failed);
      expect(c.state.failure, ble);
      verifyNever(() => repo.startPairing());
      await c.close();
    });

    test('replace-token mode: only saves, no code is requested', () async {
      when(() => repo.checkToken(token)).thenAnswer((_) async => const Right('b'));
      when(() => repo.saveTokenToSpeaker(token)).thenAnswer((_) async => const Right(unit));
      final c = TelegramConnectCubit(repo, vault)..tokenChanged(token);
      await c.checkToken();
      await c.saveToSpeaker(pairAfter: false);
      expect(c.state.save, TokenSave.saved);
      expect(c.state.pairing, Pairing.idle);
      await c.close();
    });

    test('409: no token on the speaker', () async {
      when(() => repo.startPairing()).thenAnswer((_) async => const Left(
          DeviceFailure(errorKey: ErrorKeys.deviceBusy, status: 409, code: 'NO_TOKEN')));
      final c = TelegramConnectCubit(repo, vault);
      await c.startPairing();
      expect(c.state.pairing, Pairing.noToken);
      await c.close();
    });

    test('code time counts down and expires; tg_paired after expiry is ignored', () async {
      var now = DateTime(2026, 10, 3, 12);
      when(() => repo.startPairing()).thenAnswer((_) async => const Right(code));
      final c = TelegramConnectCubit(repo, vault, clock: () => now);
      await c.startPairing();
      now = now.add(const Duration(minutes: 1, seconds: 28));
      c.tick();
      expect(c.state.remaining, const Duration(minutes: 3, seconds: 32));
      now = now.add(const Duration(minutes: 4));
      c.tick();
      expect(c.state.pairing, Pairing.expired);

      paired.add(const PairedChat(chatId: 1));
      await pump();
      expect(c.state.pairing, Pairing.expired);
      await c.close();
    });
  });
}
