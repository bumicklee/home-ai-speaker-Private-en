import 'package:aispeaker/core/storage/key_vault.dart';
import 'package:aispeaker/core/theme/app_theme.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/domain/repositories/system_repository.dart';
import 'package:aispeaker/features/system/presentation/bloc/keys_cubit.dart';
import 'package:aispeaker/features/system/presentation/bloc/system_cubit.dart';
import 'package:aispeaker/features/system/system_feature.dart';
import 'package:aispeaker/injection_container.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements SystemRepository {}

class MockVault extends Mock implements KeyVault {}

void main() {
  late MockRepo repo;
  late MockVault vault;

  setUp(() async {
    await sl.reset();
    repo = MockRepo();
    vault = MockVault();
    when(() => repo.host).thenReturn('192.168.0.156');
    when(() => repo.deviceId).thenReturn('A1B2C3EB1650');
    when(() => repo.status()).thenAnswer((_) async => const Right(SystemStatus(
          firmware: '0.5.0',
          uptime: Duration(hours: 3, minutes: 12),
          wifiRssi: -51,
          secrets: {'openai_key': true},
        )));
    when(() => repo.phones()).thenAnswer((_) async => const Right([
          RegisteredPhone(phoneId: 'p1', name: "Mom's Galaxy S24", self: true),
          RegisteredPhone(phoneId: 'p2', name: "Dad's iPhone"),
        ]));
    when(() => vault.openAiKey()).thenAnswer((_) async => 'sk-abcdefWXYZ');
    when(() => vault.geminiKey()).thenAnswer((_) async => null);
    when(() => vault.telegramToken()).thenAnswer((_) async => null);
    sl
      ..registerFactory<SystemCubit>(() => SystemCubit(repo))
      ..registerFactory<KeysCubit>(() => KeysCubit(repo, vault));
  });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      );

  testWidgets('System page: info, phones (2 / 5), this-phone badge, revoke', (t) async {
    await t.pumpWidget(app(const SystemPage()));
    await t.pumpAndSettle();
    expect(find.text('0.5.0'), findsOneWidget);
    expect(find.text('3 h 12 min'), findsOneWidget);
    expect(find.text('Good (-51 dBm)'), findsOneWidget);
    expect(find.text('192.168.0.156'), findsOneWidget);
    expect(find.text('Registered phones (2 / 5)'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
    expect(find.text('Restart speaker'), findsOneWidget);
  });

  testWidgets('Keys page: phone keys are masked', (t) async {
    await t.pumpWidget(app(const KeysPage()));
    await t.pumpAndSettle();
    expect(find.text('••••WXYZ'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(2)); // the Gemini key and Telegram token are not on the speaker
    expect(find.text('Gemini API key'), findsNWidgets(2)); // two rows: speaker and phone
  });
}
