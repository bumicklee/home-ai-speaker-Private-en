import 'package:aispeaker/core/ai/ai_choice.dart';
import 'package:aispeaker/core/constants/ble_protocol.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/features/assistant/data/models/assistant_settings_model.dart';
import 'package:aispeaker/features/assistant/domain/entities/assistant_settings.dart';
import 'package:aispeaker/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:aispeaker/features/assistant/presentation/bloc/ai_mode_cubit.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/domain/repositories/system_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAssistant extends Mock implements AssistantRepository {}

class MockSystem extends Mock implements SystemRepository {}

class MockVault extends Mock implements KeyVault {}

const settingsJson = <String, dynamic>{
  'name': 'Jarvis',
  'ai_provider': 'openai',
  'mode_openai': 'saver',
  'mode_gemini': 'live',
};

/// Stage 1 firmware: OpenAI only
const stage1 = AiStatus(provider: AiProvider.openai, mode: AiMode.saver, available: {'openai.live', 'openai.saver'});

/// Stage 2 firmware: + gemini.saver
const stage2 = AiStatus(
  provider: AiProvider.openai,
  mode: AiMode.saver,
  available: {'openai.live', 'openai.saver', 'gemini.saver'},
);

SystemStatus status({bool openai = true, bool gemini = false, AiStatus ai = stage1}) => SystemStatus(
      firmware: '0.6.0',
      uptime: Duration.zero,
      secrets: {'openai_key': openai, 'gemini_key': gemini},
      ai: ai,
    );

AssistantSettings settings([Map<String, dynamic> extra = const {}]) =>
    AssistantSettingsModel.fromJson({...settingsJson, ...extra});

void main() {
  late MockAssistant assistant;
  late MockSystem system;
  late MockVault vault;

  setUp(() {
    assistant = MockAssistant();
    system = MockSystem();
    vault = MockVault();
    when(() => assistant.settings()).thenAnswer((_) async => Right(settings()));
    when(() => system.status()).thenAnswer((_) async => Right(status()));
    when(() => vault.openAiKey()).thenAnswer((_) async => null);
    when(() => vault.geminiKey()).thenAnswer((_) async => 'AIza-remembered');
    when(() => vault.saveOpenAiKey(any())).thenAnswer((_) async {});
    when(() => vault.saveGeminiKey(any())).thenAnswer((_) async {});
  });

  Future<AiModeCubit> loaded() async {
    final c = AiModeCubit(assistant, system, vault);
    await c.load();
    return c;
  }

  test('load: settings, keys, available combinations', () async {
    final c = await loaded();
    expect(c.state.provider, AiProvider.openai);
    expect(c.state.mode, AiMode.saver);
    expect(c.state.hasKey(AiProvider.gemini), isFalse);
    expect(c.state.ai, stage1);
    await c.close();
  });

  test('locks: missing key comes first; key present but not in available means coming soon', () async {
    final c = await loaded();
    expect(c.state.providerLock(AiProvider.openai), AiLock.none);
    expect(c.state.providerLock(AiProvider.gemini), AiLock.noKey);

    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true)));
    await c.load();
    expect(c.state.providerLock(AiProvider.gemini), AiLock.notReady); // stage 1 firmware

    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true, ai: stage2)));
    await c.load();
    expect(c.state.providerLock(AiProvider.gemini), AiLock.none);
    expect(c.state.modeLock(AiProvider.gemini, AiMode.saver), AiLock.none);
    expect(c.state.modeLock(AiProvider.gemini, AiMode.live), AiLock.notReady);

    // Even if the key for the AI in use was deleted, it still shows as locked
    when(() => system.status()).thenAnswer((_) async => Right(status(openai: false, gemini: true, ai: stage2)));
    await c.load();
    expect(c.state.providerLock(AiProvider.openai), AiLock.noKey);
    await c.close();
  });

  test('old firmware (no ai): only OpenAI real-time can be chosen', () async {
    when(() => system.status()).thenAnswer((_) async => Right(status(ai: AiStatus.legacy)));
    when(() => assistant.settings()).thenAnswer(
        (_) async => Right(AssistantSettingsModel.fromJson(const {'name': 'Jarvis'}))); // no AI keys
    final c = await loaded();
    expect(c.state.provider, AiProvider.openai);
    expect(c.state.mode, AiMode.live);
    expect(c.state.modeLock(AiProvider.openai, AiMode.live), AiLock.none);
    expect(c.state.modeLock(AiProvider.openai, AiMode.saver), AiLock.notReady);
    expect(await c.chooseMode(AiMode.saver), isNull);
    verifyNever(() => assistant.update(any()));
    await c.close();
  });

  test('if status cannot be read, nothing is locked by key (the speaker blocks with 409)', () async {
    when(() => system.status()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = await loaded();
    expect(c.state.settings, isNotNull);
    expect(c.state.hasKey(AiProvider.gemini), isNull);
    expect(c.state.providerLock(AiProvider.gemini), AiLock.notReady); // treat it like old firmware
    expect(c.state.providerLock(AiProvider.openai), AiLock.none);
    await c.close();
  });

  test('if settings cannot be read, the screen fails', () async {
    when(() => assistant.settings()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = await loaded();
    expect(c.state.settings, isNull);
    expect(c.state.failure, const NetworkFailure());
    await c.close();
  });

  test('does not send a locked AI or mode', () async {
    final c = await loaded();
    expect(await c.chooseProvider(AiProvider.gemini), isNull);
    expect(await c.chooseProvider(AiProvider.openai), isNull); // already chosen
    expect(await c.chooseMode(AiMode.saver), isNull); // already chosen
    verifyNever(() => assistant.update(any()));
    await c.close();
  });

  test('changing mode: PUTs only the current AI mode_ key', () async {
    when(() => assistant.update(any())).thenAnswer((_) async => Right(settings({'mode_openai': 'live'})));
    final c = await loaded();
    expect(await c.chooseMode(AiMode.live), isNull);
    verify(() => assistant.update({'mode_openai': 'live'})).called(1);
    expect(c.state.mode, AiMode.live);
    expect(c.state.saving, isFalse);
    await c.close();
  });

  test('changing AI: if that AI last mode is unavailable, also switches to an available mode', () async {
    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true, ai: stage2)));
    when(() => assistant.update(any()))
        .thenAnswer((_) async => Right(settings({'ai_provider': 'gemini', 'mode_gemini': 'saver'})));
    final c = await loaded();
    expect(await c.chooseProvider(AiProvider.gemini), isNull);
    // mode_gemini was live, but stage 2 firmware has only gemini.saver
    verify(() => assistant.update({'ai_provider': 'gemini', 'mode_gemini': 'saver'})).called(1);
    expect(c.state.provider, AiProvider.gemini);
    expect(c.state.mode, AiMode.saver);
    await c.close();
  });

  test('changing AI: only ai_provider when the last mode is available', () async {
    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true, ai: stage2)));
    when(() => assistant.settings()).thenAnswer((_) async => Right(settings({'mode_gemini': 'saver'})));
    when(() => assistant.update(any())).thenAnswer((_) async => Right(settings({'ai_provider': 'gemini'})));
    final c = await loaded();
    await c.chooseProvider(AiProvider.gemini);
    verify(() => assistant.update({'ai_provider': 'gemini'})).called(1);
    await c.close();
  });

  test('409 NO_API_KEY: returns the failure and locks that AI as missing a key', () async {
    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true, ai: stage2)));
    when(() => assistant.update(any())).thenAnswer((_) async => const Left(
        DeviceFailure(errorKey: ErrorKeys.deviceNoApiKey, status: 409, code: 'NO_API_KEY')));
    final c = await loaded();
    final f = await c.chooseProvider(AiProvider.gemini);
    expect(f, isNotNull);
    expect(AiModeCubit.isNoKey(f!), isTrue);
    expect(c.state.providerLock(AiProvider.gemini), AiLock.noKey);
    expect(c.state.provider, AiProvider.openai);
    expect(c.state.saving, isFalse);
    await c.close();
  });

  test('adding a key: sends gemini_key over BLE, remembers it on the phone, unlocks the missing-key lock', () async {
    const key = 'AIzaSyA1234567890abcdefghijklmnopqrstu';
    when(() => system.sendKeyOverBle(SecretKey.gemini, key)).thenAnswer((_) async => const Right(unit));
    final c = await loaded();
    expect(await c.rememberedKey(AiProvider.gemini), 'AIza-remembered');
    expect(await c.rememberedKey(AiProvider.openai), '');
    expect(await c.sendKey(AiProvider.gemini, key), isNull);
    verify(() => vault.saveGeminiKey(key)).called(1);
    expect(c.state.hasKey(AiProvider.gemini), isTrue);
    expect(c.state.providerLock(AiProvider.gemini), AiLock.notReady); // stage 1 firmware: still coming soon
    await c.close();
  });

  test('adding a key fails: does not save it on the phone', () async {
    when(() => system.sendKeyOverBle(any(), any()))
        .thenAnswer((_) async => const Left(BleFailure(errorKey: ErrorKeys.bleNotFound)));
    final c = await loaded();
    final f = await c.sendKey(AiProvider.gemini, 'AIzaSyA1234567890abcdefghijklmnopqrstu');
    expect(f?.errorKey, ErrorKeys.bleNotFound);
    verifyNever(() => vault.saveGeminiKey(any()));
    expect(c.state.hasKey(AiProvider.gemini), isFalse);
    await c.close();
  });
}
