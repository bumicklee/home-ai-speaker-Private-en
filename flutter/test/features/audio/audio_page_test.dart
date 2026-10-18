import 'dart:async';

import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/audio/audio_feature.dart';
import 'package:aispeaker/features/audio/data/repositories/audio_repository.dart';
import 'package:aispeaker/features/audio/domain/entities/audio_settings.dart';
import 'package:aispeaker/features/audio/presentation/bloc/audio_cubit.dart';
import 'package:aispeaker/injection_container.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements AudioRepository {}

class MockEvents extends Mock implements DeviceEventService {}

const audio = AudioSettings(volume: 40, micGain: 36, autoGain: false, duckDb: 20);
const wake = WakeSettings(enabled: true, phrase: WakePhrase.computer, sensitivity: 80, gainDb: 12);

void main() {
  late MockRepo repo;
  late StreamController<DeviceEvent> stream;

  setUp(() {
    repo = MockRepo();
    final events = MockEvents();
    stream = StreamController<DeviceEvent>.broadcast();
    when(() => events.on(any())).thenAnswer((i) {
      final type = i.positionalArguments.first as String;
      return stream.stream.where((e) => e.type == type);
    });
    when(() => repo.audio()).thenAnswer((_) async => const Right(audio));
    when(() => repo.wake()).thenAnswer((_) async => const Right(wake));
    when(() => repo.ledBrightness()).thenAnswer((_) async => const Right(60));
    sl.registerFactory<AudioCubit>(() => AudioCubit(repo, events));
  });

  tearDown(() async {
    await sl.reset();
    await stream.close();
  });

  // so all three cards fit on one screen; 440 wide so the English slider end
  // labels fit in the test font (Ahem draws every glyph as a full square)
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app() => const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AudioPage(),
      );

  testWidgets('shows settings and updates on a volume event', (tester) async {
    tall(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Computer'), findsOneWidget);
    expect(find.text('Alexa'), findsOneWidget);
    expect(find.text('40 / 80'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.textContaining('spotify', findRichText: true), findsNothing);

    stream.add(const DeviceEvent('volume', {'value': 55}));
    await tester.pumpAndSettle();
    expect(find.text('55 / 80'), findsOneWidget);
  });

  testWidgets('mic sensitivity picks only values the device accepts', (tester) async {
    tall(tester);
    when(() => repo.updateAudio(any())).thenAnswer((_) async => Right(audio.copyWith(micGain: 30)));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '36 dB'));
    await tester.pumpAndSettle();
    for (final db in AudioSettings.micGainSteps) {
      expect(find.text('$db dB'), findsWidgets);
    }
    expect(find.text('33 dB'), findsNothing);

    await tester.tap(find.text('30 dB'));
    await tester.pumpAndSettle();
    verify(() => repo.updateAudio({'mic_gain': 30})).called(1);
  });
}
