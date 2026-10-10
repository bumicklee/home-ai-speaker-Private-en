import 'package:aispeaker/core/ai/ai_choice.dart';
import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/core/theme/app_theme.dart';
import 'package:aispeaker/features/assistant/assistant_feature.dart';
import 'package:aispeaker/features/assistant/data/models/assistant_settings_model.dart';
import 'package:aispeaker/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:aispeaker/features/assistant/presentation/bloc/ai_mode_cubit.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/domain/repositories/system_repository.dart';
import 'package:aispeaker/injection_container.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAssistant extends Mock implements AssistantRepository {}

class MockSystem extends Mock implements SystemRepository {}

class MockVault extends Mock implements KeyVault {}

void main() {
  late MockAssistant assistant;
  late MockSystem system;

  setUp(() async {
    await sl.reset();
    assistant = MockAssistant();
    system = MockSystem();
    when(() => assistant.settings()).thenAnswer((_) async => Right(AssistantSettingsModel.fromJson(const {
          'ai_provider': 'openai',
          'mode_openai': 'saver',
          'mode_gemini': 'saver',
        })));
    when(() => system.status()).thenAnswer((_) async => const Right(SystemStatus(
          firmware: '0.6.0',
          uptime: Duration.zero,
          secrets: {'openai_key': true, 'gemini_key': false},
          ai: AiStatus(provider: AiProvider.openai, mode: AiMode.saver, available: {'openai.saver'}),
        )));
    sl.registerFactory<AiModeCubit>(() => AiModeCubit(assistant, system, MockVault()));
  });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      );

  testWidgets('AI · 대화 방식: 키 없는 AI 잠금, 키 넣기, 준비 중 방식, 영어 수업 안내', (t) async {
    await t.pumpWidget(app(const AiModePage()));
    await t.pumpAndSettle();
    expect(find.text('AI · 대화 방식'), findsOneWidget);
    expect(find.text('키 있음'), findsOneWidget);
    expect(find.text('키 없음 · 쓸 수 없어요'), findsOneWidget);
    expect(find.text('Gemini 키 넣기 (가운데 버튼 3초 → 블루투스로 보내요)'), findsOneWidget);
    expect(find.text('② OpenAI 대화 방식'), findsOneWidget);
    expect(find.text('월 약 15,000원'), findsOneWidget);
    expect(find.text('준비 중'), findsOneWidget); // openai.live is not in available
    expect(find.textContaining('실시간 API(OpenAI)'), findsOneWidget);

    await t.tap(find.text('Gemini'));
    await t.pump();
    expect(find.text('이 스피커에는 Gemini 키가 없어요. 먼저 키를 넣어 주세요.'), findsOneWidget);
    verifyNever(() => assistant.update(any()));
  });
}
