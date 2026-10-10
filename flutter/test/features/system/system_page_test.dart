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
          RegisteredPhone(phoneId: 'p1', name: '엄마 Galaxy S24', self: true),
          RegisteredPhone(phoneId: 'p2', name: '아빠 iPhone'),
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
        locale: const Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      );

  testWidgets('시스템 화면: 정보, 휴대폰 (2 / 5), 이 휴대폰 배지, 등록 해지', (t) async {
    await t.pumpWidget(app(const SystemPage()));
    await t.pumpAndSettle();
    expect(find.text('0.5.0'), findsOneWidget);
    expect(find.text('3시간 12분'), findsOneWidget);
    expect(find.text('좋음 (-51 dBm)'), findsOneWidget);
    expect(find.text('192.168.0.156'), findsOneWidget);
    expect(find.text('등록된 휴대폰 (2 / 5)'), findsOneWidget);
    expect(find.text('이 휴대폰'), findsOneWidget);
    expect(find.text('등록 해지'), findsOneWidget);
    expect(find.text('스피커 다시 시작'), findsOneWidget);
  });

  testWidgets('키 화면: 휴대폰 키는 가려서 보인다', (t) async {
    await t.pumpWidget(app(const KeysPage()));
    await t.pumpAndSettle();
    expect(find.text('••••WXYZ'), findsOneWidget);
    expect(find.text('저장됨'), findsOneWidget);
    expect(find.text('바꾸기'), findsOneWidget);
    expect(find.text('넣기'), findsNWidgets(2)); // the Gemini key and Telegram token are not on the speaker
    expect(find.text('Gemini API 키'), findsNWidgets(2)); // two rows: speaker and phone
  });
}
