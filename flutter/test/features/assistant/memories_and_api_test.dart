import 'package:aispeaker/core/ai/ai_choice.dart';
import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/network/device_api_client.dart';
import 'package:aispeaker/features/assistant/data/datasources/assistant_local_api_datasource.dart';
import 'package:aispeaker/features/assistant/data/models/assistant_settings_model.dart';
import 'package:aispeaker/features/assistant/data/repositories/assistant_repository_impl.dart';
import 'package:aispeaker/features/assistant/domain/entities/assistant_settings.dart';
import 'package:aispeaker/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:aispeaker/features/assistant/presentation/bloc/memories_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements AssistantRepository {}

class MockCurrent extends Mock implements CurrentDevice {}

class MockClient extends Mock implements DeviceApiClient {}

/// Exactly the firmware assistant.c DEFAULTS
const firmwareDefaults = {
  'name': 'Jarvis',
  'purpose': 'A helpful family home assistant for conversation, cooking, everyday questions and current information.',
  'language': 'ko',
  'location': '',
  'units': 'metric',
  'web_search': true,
  'device_controls': true,
  'auto_memory': false,
  'voice': 'marin',
  'timezone': 'Asia/Seoul',
  'ai_provider': 'openai',
  'mode_openai': 'saver',
  'mode_gemini': 'saver',
};

void main() {
  group('MemoriesCubit', () {
    late MockRepo repo;

    setUp(() {
      repo = MockRepo();
      when(() => repo.memories()).thenAnswer((_) async => const Right([
            AssistantMemory(key: 'favorite_food', value: '김치찌개'),
            AssistantMemory(key: 'pet_name', value: '초코'),
          ]));
    });

    test('지우면 목록에서 뺀다', () async {
      when(() => repo.forget('pet_name')).thenAnswer((_) async => const Right(unit));
      final c = MemoriesCubit(repo);
      await c.load();
      expect(c.state.memories, hasLength(2));
      expect(await c.forget('pet_name'), isNull);
      expect(c.state.memories, [const AssistantMemory(key: 'favorite_food', value: '김치찌개')]);
      expect(c.state.deleting, isEmpty);
      await c.close();
    });

    test('지우기 실패면 목록을 그대로 두고 Failure', () async {
      when(() => repo.forget(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(400, 'INVALID_ARG')));
      final c = MemoriesCubit(repo);
      await c.load();
      final f = await c.forget('pet_name');
      expect(f?.errorKey, ErrorKeys.deviceInvalidArg);
      expect(c.state.memories, hasLength(2));
      expect(c.state.deleting, isEmpty);
      await c.close();
    });
  });

  group('LAN 데이터소스·레포지토리', () {
    late MockCurrent current;
    late MockClient client;
    late AssistantRepositoryImpl repo;

    setUp(() {
      current = MockCurrent();
      client = MockClient();
      when(() => current.client).thenReturn(client);
      repo = AssistantRepositoryImpl(AssistantLocalApiDataSource(current));
    });

    test('설정 JSON (펌웨어 기본값) → 엔티티 → JSON 왕복', () async {
      when(() => client.get<Map<String, dynamic>>('/api/v1/settings/assistant'))
          .thenAnswer((_) async => Map<String, dynamic>.from(firmwareDefaults));
      final s = (await repo.settings()).getOrElse(() => throw StateError('x'));
      expect(s.voice, 'marin');
      expect(s.autoMemory, isFalse);
      expect(AssistantSettingsModel.toJson(s), firmwareDefaults);
    });

    test('AI 키 3개: 읽기, 옛 펌웨어(키 없음)는 OpenAI 실시간, 모르는 값은 기본값', () async {
      final s = AssistantSettingsModel.fromJson(Map<String, dynamic>.from(firmwareDefaults));
      expect(s.aiProvider, AiProvider.openai);
      expect(s.aiMode, AiMode.saver);
      expect(s.modeGemini, AiMode.saver);

      final old = Map<String, dynamic>.from(firmwareDefaults)
        ..remove('ai_provider')
        ..remove('mode_openai')
        ..remove('mode_gemini');
      final legacy = AssistantSettingsModel.fromJson(old);
      expect(legacy.aiProvider, AiProvider.openai);
      expect(legacy.modeOpenai, AiMode.live);
      expect(legacy.modeGemini, AiMode.saver);

      final odd = AssistantSettingsModel.fromJson({...old, 'ai_provider': 'claude', 'mode_openai': 7});
      expect(odd.aiProvider, AiProvider.openai);
      expect(odd.modeOpenai, AiMode.live);

      final gemini = AssistantSettingsModel.fromJson({...old, 'ai_provider': 'gemini', 'mode_gemini': 'live'});
      expect(gemini.aiMode, AiMode.live);
      expect(AssistantSettingsModel.diff(s, s.copyWith(aiProvider: AiProvider.gemini)), {'ai_provider': 'gemini'});
    });

    test('PUT 본문은 바뀐 키만', () async {
      when(() => client.put<Map<String, dynamic>>(any(), any()))
          .thenAnswer((_) async => {...firmwareDefaults, 'units': 'imperial'});
      final r = await repo.update({'units': 'imperial'});
      expect(r.isRight(), isTrue);
      verify(() => client.put<Map<String, dynamic>>('/api/v1/settings/assistant', {'units': 'imperial'})).called(1);
    });

    test('보이스 목록 {"voices": [...]}', () async {
      when(() => client.get<Map<String, dynamic>>('/api/v1/voices')).thenAnswer((_) async => {
            'voices': ['alloy', 'marin'],
          });
      expect((await repo.voices()).getOrElse(() => const []), ['alloy', 'marin']);
    });

    test('기억 목록은 {키: 값} 객체, 지우기는 DELETE /memories/{key}', () async {
      when(() => client.get<Map<String, dynamic>>('/api/v1/memories'))
          .thenAnswer((_) async => {'favorite_food': '김치찌개'});
      when(() => client.delete<dynamic>(any())).thenAnswer((_) async => {'ok': true});
      final m = (await repo.memories()).getOrElse(() => const []);
      expect(m, [const AssistantMemory(key: 'favorite_food', value: '김치찌개')]);
      expect(await repo.forget('favorite_food'), const Right<Failure, Unit>(unit));
      verify(() => client.delete<dynamic>('/api/v1/memories/favorite_food')).called(1);
    });

    test('400 INVALID_ARG → DeviceFailure', () async {
      when(() => client.put<Map<String, dynamic>>(any(), any()))
          .thenThrow(const DeviceApiException(400, 'INVALID_ARG'));
      final r = await repo.update({'timezone': 'Asia/Kolkata'});
      expect(r.fold((f) => f.errorKey, (_) => null), ErrorKeys.deviceInvalidArg);
    });
  });
}
