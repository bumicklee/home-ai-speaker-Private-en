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

  test('load: 설정·키·가능한 조합', () async {
    final c = await loaded();
    expect(c.state.provider, AiProvider.openai);
    expect(c.state.mode, AiMode.saver);
    expect(c.state.hasKey(AiProvider.gemini), isFalse);
    expect(c.state.ai, stage1);
    await c.close();
  });

  test('잠금: 키 없음이 먼저, 키는 있는데 available에 없으면 준비 중', () async {
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

  test('옛 펌웨어(ai 없음): OpenAI 실시간만 고를 수 있다', () async {
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

  test('상태를 못 읽으면 키로는 잠그지 않는다 (스피커가 409로 막는다)', () async {
    when(() => system.status()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = await loaded();
    expect(c.state.settings, isNotNull);
    expect(c.state.hasKey(AiProvider.gemini), isNull);
    expect(c.state.providerLock(AiProvider.gemini), AiLock.notReady); // treat it like old firmware
    expect(c.state.providerLock(AiProvider.openai), AiLock.none);
    await c.close();
  });

  test('설정을 못 읽으면 화면 실패', () async {
    when(() => assistant.settings()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = await loaded();
    expect(c.state.settings, isNull);
    expect(c.state.failure, const NetworkFailure());
    await c.close();
  });

  test('잠긴 AI·방식은 보내지 않는다', () async {
    final c = await loaded();
    expect(await c.chooseProvider(AiProvider.gemini), isNull);
    expect(await c.chooseProvider(AiProvider.openai), isNull); // already chosen
    expect(await c.chooseMode(AiMode.saver), isNull); // already chosen
    verifyNever(() => assistant.update(any()));
    await c.close();
  });

  test('방식 바꾸기: 지금 AI의 mode_ 키만 PUT', () async {
    when(() => assistant.update(any())).thenAnswer((_) async => Right(settings({'mode_openai': 'live'})));
    final c = await loaded();
    expect(await c.chooseMode(AiMode.live), isNull);
    verify(() => assistant.update({'mode_openai': 'live'})).called(1);
    expect(c.state.mode, AiMode.live);
    expect(c.state.saving, isFalse);
    await c.close();
  });

  test('AI 바꾸기: 그 AI의 마지막 방식이 안 되면 되는 방식으로 함께 바꾼다', () async {
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

  test('AI 바꾸기: 마지막 방식이 되면 ai_provider만', () async {
    when(() => system.status()).thenAnswer((_) async => Right(status(gemini: true, ai: stage2)));
    when(() => assistant.settings()).thenAnswer((_) async => Right(settings({'mode_gemini': 'saver'})));
    when(() => assistant.update(any())).thenAnswer((_) async => Right(settings({'ai_provider': 'gemini'})));
    final c = await loaded();
    await c.chooseProvider(AiProvider.gemini);
    verify(() => assistant.update({'ai_provider': 'gemini'})).called(1);
    await c.close();
  });

  test('409 NO_API_KEY: 실패를 돌려주고 그 AI를 키 없음으로 잠근다', () async {
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

  test('키 넣기: gemini_key를 BLE로 보내고 휴대폰에 기억, 키 없음 잠금이 풀린다', () async {
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

  test('키 넣기 실패: 휴대폰에 저장하지 않는다', () async {
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
