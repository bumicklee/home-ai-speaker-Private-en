import 'dart:async';

import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/radio/presentation/bloc/radio_cubit.dart';
import 'package:aispeaker/features/radio/presentation/pages/preset_edit_page.dart';
import 'package:aispeaker/features/radio/presentation/pages/radio_page.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'radio_cubit_test.dart' show MockEvents, MockRepo, playing, presets;

void main() {
  late MockRepo repo;
  late MockEvents events;

  setUp(() {
    repo = MockRepo();
    events = MockEvents();
    when(() => events.on(DeviceEventType.mediaState)).thenAnswer((_) => const Stream.empty());
    when(() => repo.presets()).thenAnswer((_) async => const Right(presets));
    when(() => repo.now()).thenAnswer((_) async => const Right(playing));
  });

  Widget app(RadioCubit cubit, Widget child) => MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(value: cubit, child: child),
      );

  testWidgets('묶음 제목과 재생 중 방송을 보인다', (tester) async {
    final cubit = RadioCubit(repo, events);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(app(cubit, const RadioView()));
    await tester.pump();
    expect(find.text('뉴스·경제'), findsOneWidget);
    expect(find.text('한국 음악'), findsOneWidget);
    expect(find.text('CNN'), findsNWidgets(2)); // header card + list
    expect(find.byTooltip('일시정지'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.runAsync(cubit.close);
  });

  testWidgets('편집 화면이 그려진다', (tester) async {
    final cubit = RadioCubit(repo, events);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(app(cubit, const PresetEditPage()));
    await tester.pump();
    expect(find.text('Big B'), findsOneWidget);
    expect(find.text('2 / 20개'), findsOneWidget);
    await tester.runAsync(cubit.close);
  });
}
