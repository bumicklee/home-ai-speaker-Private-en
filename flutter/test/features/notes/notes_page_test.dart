import 'dart:async';

import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/features/notes/data/repositories/notes_repository.dart';
import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:aispeaker/features/notes/notes_feature.dart';
import 'package:aispeaker/features/notes/presentation/bloc/notes_cubit.dart';
import 'package:aispeaker/injection_container.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements NotesRepository {}

void main() {
  late MockRepo repo;
  late StreamController<void> changes;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final hospital = Note(
    id: 'n_1',
    kind: NoteKind.event,
    title: 'Doctor',
    start: NoteTime.at(today.add(const Duration(days: 1, hours: 15))),
    remind: const [1440, 60],
    rev: 4,
  );
  const milk = Note(id: 'n_2', title: 'Buy milk', body: 'On the way to the store', rev: 3);

  setUpAll(() {
    registerFallbackValue(const Note(id: 'x'));
    registerFallbackValue(const NoteDraft(kind: NoteKind.memo, title: 'x'));
  });

  setUp(() {
    repo = MockRepo();
    changes = StreamController<void>.broadcast();
    when(() => repo.changes()).thenAnswer((_) => changes.stream);
    when(() => repo.cached()).thenAnswer((_) async => NotesCache(rev: 4, items: [hospital, milk]));
    when(() => repo.settings()).thenAnswer((_) async => const Right(NotesSettings()));
    sl.registerFactory<NotesCubit>(() => NotesCubit(repo));
  });

  tearDown(() async {
    await sl.reset();
    await changes.close();
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app() => const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NotesPage(),
      );

  testWidgets('event groups and reminder badges, memos tab', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => Right(NotesCache(rev: 4, items: [hospital, milk])));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Tomorrow ·'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('1 day before · 1 hr before'), findsOneWidget);
    expect(find.text('Reminder set'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    await tester.tap(find.text('Memos'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Doctor'), findsNothing);
  });

  testWidgets('when the speaker is unreachable: notice and no New button', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => const Left(NetworkFailure()));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('You can edit on your home Wi-Fi'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.text('Doctor'), findsOneWidget, reason: 'the local copy is still shown');
  });

  testWidgets('edit: up to 3 reminder chips; delete warns it is removed from the speaker too, then DELETEs', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => Right(NotesCache(rev: 4, items: [hospital, milk])));
    when(() => repo.delete(any())).thenAnswer((_) async => const Right(NotesCache(rev: 4, items: [milk])));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('The speaker will tell you 1 day before, 1 hr before'), findsOneWidget);
    expect(find.text('You can pick several'), findsOneWidget);

    await tester.tap(find.text('10 min before'));
    await tester.pumpAndSettle();
    expect(find.text('Up to 3'), findsOneWidget);
    expect(find.text('The speaker will tell you 1 day before, 1 hr before, 10 min before'), findsOneWidget);
    await tester.tap(find.text('30 min before')); // disabled
    await tester.pumpAndSettle();
    expect(find.text('The speaker will tell you 1 day before, 1 hr before, 10 min before'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Doctor”?'), findsOneWidget);
    expect(find.text("It will be deleted from the speaker too and can't be restored. It will also disappear from other family phones."), findsOneWidget);
    // the edit page's Delete button and the dialog's action share the same English label
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pumpAndSettle();
    verify(() => repo.delete(hospital)).called(1);
    expect(find.text('Edit event'), findsNothing);
  });
}
