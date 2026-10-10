import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/core/theme/app_theme.dart';
import 'package:aispeaker/features/provisioning/domain/repositories/provisioning_repository.dart';
import 'package:aispeaker/features/provisioning/presentation/bloc/provisioning_cubit.dart';
import 'package:aispeaker/features/provisioning/presentation/pages/provisioning_page.dart';
import 'package:aispeaker/injection_container.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements ProvisioningRepository {}

class MockVault extends Mock implements KeyVault {}

void main() {
  setUp(() async {
    await sl.reset();
    final repo = MockRepo();
    final vault = MockVault();
    when(() => vault.openAiKey()).thenAnswer((_) async => null);
    when(() => vault.geminiKey()).thenAnswer((_) async => null);
    when(() => vault.telegramToken()).thenAnswer((_) async => null);
    when(() => repo.defaultPhoneName()).thenAnswer((_) async => 'Galaxy');
    when(() => repo.disconnect()).thenAnswer((_) async {});
    sl.registerFactory<ProvisioningCubit>(() => ProvisioningCubit(repo, vault));
  });

  testWidgets('첫 설정 1단계: 키도 "이미 있음"도 없으면 스피커 찾기 잠김', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const ProvisioningPage(),
    ));
    await t.pumpAndSettle();
    expect(find.text('어떤 AI를 쓸까요?'), findsOneWidget);
    expect(find.text('OpenAI API 키 (필수)'), findsOneWidget);
    expect(find.text('월 약 1.5만 원 · 대답 1~2초 늦음'), findsOneWidget);
    expect(find.text('OpenAI API 키를 넣어야 다음으로 갈 수 있어요'), findsOneWidget);
    FilledButton button() => t.widget<FilledButton>(find.widgetWithText(FilledButton, '스피커 찾기'));
    expect(button().onPressed, isNull);
    expect(find.text('(스피커에 따라 준비 중일 수 있어요)'), findsNothing); // OpenAI always works

    await t.tap(find.text('Gemini'));
    await t.pump();
    expect(find.text('Gemini API 키 (필수)'), findsOneWidget);
    expect(find.text('(스피커에 따라 준비 중일 수 있어요)'), findsOneWidget);
    expect(find.text('월 약 1만 원 · 대답 1~2초 늦음'), findsOneWidget);

    await t.tap(find.text('이미 이 AI 키가 저장된 스피커예요 (휴대폰 추가 등록)'));
    await t.pump();
    expect(button().onPressed, isNotNull);
    expect(find.text('Gemini API 키를 넣어야 다음으로 갈 수 있어요'), findsNothing);
  });
}
