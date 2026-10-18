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

  testWidgets('first setup step 1: Find speaker is locked without a key or "already set"', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const ProvisioningPage(),
    ));
    await t.pumpAndSettle();
    expect(find.text('Which AI should it use?'), findsOneWidget);
    expect(find.text('OpenAI API key (required)'), findsOneWidget);
    expect(find.text('About ₩15k/month · Replies 1–2 s later'), findsOneWidget);
    expect(find.text('Enter the OpenAI API key to continue'), findsOneWidget);
    FilledButton button() => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Find speaker'));
    expect(button().onPressed, isNull);
    expect(find.text('(may not be ready yet on some speakers)'), findsNothing); // OpenAI always works

    await t.tap(find.text('Gemini'));
    await t.pump();
    expect(find.text('Gemini API key (required)'), findsOneWidget);
    expect(find.text('(may not be ready yet on some speakers)'), findsOneWidget);
    expect(find.text('About ₩10k/month · Replies 1–2 s later'), findsOneWidget);

    await t.tap(find.text("This speaker already has this AI's key (adding another phone)"));
    await t.pump();
    expect(button().onPressed, isNotNull);
    expect(find.text('Enter the Gemini API key to continue'), findsNothing);
  });
}
