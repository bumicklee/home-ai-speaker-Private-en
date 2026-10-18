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
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(value: cubit, child: child),
      );

  testWidgets('shows group titles and the playing station', (tester) async {
    final cubit = RadioCubit(repo, events);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(app(cubit, const RadioView()));
    await tester.pump();
    expect(find.text('News & business'), findsOneWidget);
    expect(find.text('Korean music'), findsOneWidget);
    expect(find.text('CNN'), findsNWidgets(2)); // header card + list
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.runAsync(cubit.close);
  });

  testWidgets('renders the edit page', (tester) async {
    final cubit = RadioCubit(repo, events);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(app(cubit, const PresetEditPage()));
    await tester.pump();
    expect(find.text('Big B'), findsOneWidget);
    expect(find.text('2 / 20'), findsOneWidget);
    await tester.runAsync(cubit.close);
  });
}
