import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/domain/repositories/system_repository.dart';
import 'package:aispeaker/features/system/presentation/bloc/keys_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements SystemRepository {}

class MockVault extends Mock implements KeyVault {}

const key = 'sk-proj-abcdefghijklmnopqrstuvwxWXYZ';

void main() {
  late MockRepo repo;
  late MockVault vault;

  setUp(() {
    repo = MockRepo();
    vault = MockVault();
    when(() => vault.openAiKey()).thenAnswer((_) async => 'sk-old-1234');
    when(() => vault.geminiKey()).thenAnswer((_) async => null);
    when(() => vault.telegramToken()).thenAnswer((_) async => null);
    when(() => vault.saveOpenAiKey(any())).thenAnswer((_) async {});
    when(() => vault.saveGeminiKey(any())).thenAnswer((_) async {});
    when(() => vault.saveTelegramToken(any())).thenAnswer((_) async {});
    when(() => repo.status()).thenAnswer((_) async => const Right(SystemStatus(
          firmware: '0.5.0',
          uptime: Duration.zero,
          secrets: {'openai_key': true, 'tg_bot_token': false},
        )));
  });

  test('mask: last 4 characters only', () {
    expect(KeysCubit.mask('sk-abcdefWXYZ'), '••••WXYZ');
    expect(KeysCubit.mask('ab'), '••••ab');
  });

  test('load: phone keys and whether the speaker has them', () async {
    final c = KeysCubit(repo, vault);
    await c.load();
    expect(c.state.onPhone, {SecretKey.openai: 'sk-old-1234'});
    expect(c.state.onSpeaker, {SecretKey.openai: true, SecretKey.gemini: false, SecretKey.telegramBot: false});
  });

  test('Gemini key: remember on the phone, send over BLE, delete over LAN', () async {
    const gemini = 'AIzaSyA1234567890abcdefghijklmnopqrstu';
    when(() => vault.geminiKey()).thenAnswer((_) async => 'AIza-old-9876');
    when(() => repo.sendKeyOverBle(SecretKey.gemini, gemini)).thenAnswer((_) async => const Right(unit));
    when(() => repo.deleteSpeakerKey(SecretKey.gemini)).thenAnswer((_) async => const Right(unit));
    final c = KeysCubit(repo, vault);
    await c.load();
    expect(c.state.onPhone[SecretKey.gemini], 'AIza-old-9876');
    expect(c.state.onSpeaker?[SecretKey.gemini], isFalse);
    expect(await c.sendToSpeaker(SecretKey.gemini, gemini), isNull);
    verify(() => vault.saveGeminiKey(gemini)).called(1);
    verifyNever(() => vault.saveOpenAiKey(any()));
    expect(c.state.onSpeaker?[SecretKey.gemini], isTrue);
    expect(await c.deleteOnSpeaker(SecretKey.gemini), isNull);
    expect(c.state.onSpeaker?[SecretKey.gemini], isFalse);
    await c.forgetOnPhone(SecretKey.gemini);
    verify(() => vault.saveGeminiKey(null)).called(1);
  });

  test('load: phone keys show even when the speaker is unreachable', () async {
    when(() => repo.status()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = KeysCubit(repo, vault);
    await c.load();
    expect(c.state.onPhone.keys, [SecretKey.openai]);
    expect(c.state.onSpeaker, isNull);
    expect(c.state.speakerFailure, const NetworkFailure());
  });

  test('forgetOnPhone: deletes from KeyVault (saving null = delete)', () async {
    final c = KeysCubit(repo, vault);
    await c.load();
    await c.forgetOnPhone(SecretKey.openai);
    verify(() => vault.saveOpenAiKey(null)).called(1);
    expect(c.state.onPhone, isEmpty);
    expect(c.state.onSpeaker?[SecretKey.openai], isTrue); // the speaker keeps it
  });

  test('sendToSpeaker: sends over BLE and remembers on the phone', () async {
    when(() => repo.sendKeyOverBle(SecretKey.openai, key)).thenAnswer((_) async => const Right(unit));
    final c = KeysCubit(repo, vault);
    await c.load();
    expect(await c.sendToSpeaker(SecretKey.openai, key), isNull);
    verify(() => vault.saveOpenAiKey(key)).called(1);
    expect(c.state.onPhone[SecretKey.openai], key);
    expect(c.state.sending, isNull);
  });

  test('sendToSpeaker: the Telegram token goes in the Telegram slot', () async {
    when(() => repo.sendKeyOverBle(SecretKey.telegramBot, '123456:tok')).thenAnswer((_) async => const Right(unit));
    final c = KeysCubit(repo, vault);
    await c.load();
    await c.sendToSpeaker(SecretKey.telegramBot, '123456:tok');
    verify(() => vault.saveTelegramToken('123456:tok')).called(1);
    expect(c.state.onSpeaker?[SecretKey.telegramBot], isTrue);
  });

  test('sendToSpeaker: fails if the speaker is not found, not saved on the phone', () async {
    when(() => repo.sendKeyOverBle(any(), any()))
        .thenAnswer((_) async => const Left(BleFailure(errorKey: ErrorKeys.bleNotFound)));
    final c = KeysCubit(repo, vault);
    await c.load();
    final f = await c.sendToSpeaker(SecretKey.openai, key);
    expect(f?.errorKey, ErrorKeys.bleNotFound);
    verifyNever(() => vault.saveOpenAiKey(key));
    expect(c.state.sending, isNull);
  });

  test('deleteOnSpeaker: deletes over LAN and refreshes saved state', () async {
    when(() => repo.deleteSpeakerKey(SecretKey.openai)).thenAnswer((_) async => const Right(unit));
    final c = KeysCubit(repo, vault);
    await c.load();
    expect(await c.deleteOnSpeaker(SecretKey.openai), isNull);
    expect(c.state.onSpeaker?[SecretKey.openai], isFalse);
    expect(c.state.onPhone[SecretKey.openai], 'sk-old-1234'); // the phone value stays
  });
}
