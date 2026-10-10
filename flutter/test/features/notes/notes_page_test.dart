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
    title: '병원',
    start: NoteTime.at(today.add(const Duration(days: 1, hours: 15))),
    remind: const [1440, 60],
    rev: 4,
  );
  const milk = Note(id: 'n_2', title: '우유 사기', body: '마트 갈 때', rev: 3);

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
        locale: Locale('ko'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NotesPage(),
      );

  testWidgets('일정 묶음·알림 표시, 메모 탭', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => Right(NotesCache(rev: 4, items: [hospital, milk])));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('내일 ·'), findsOneWidget);
    expect(find.text('병원'), findsOneWidget);
    expect(find.text('하루 전 · 1시간 전'), findsOneWidget);
    expect(find.text('알림 예정'), findsOneWidget);
    expect(find.text('새로 만들기'), findsOneWidget);
    await tester.tap(find.text('메모'));
    await tester.pumpAndSettle();
    expect(find.text('우유 사기'), findsOneWidget);
    expect(find.text('병원'), findsNothing);
  });

  testWidgets('스피커에 닿지 않으면 안내 + 새로 만들기 없음', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => const Left(NetworkFailure()));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('집 Wi-Fi에서 고칠 수 있어요'), findsOneWidget);
    expect(find.text('새로 만들기'), findsNothing);
    expect(find.text('병원'), findsOneWidget, reason: '사본은 보인다');
  });

  testWidgets('편집: 알림 칩은 3개까지, 삭제는 스피커에서도 지워진다고 묻고 DELETE', (tester) async {
    tall(tester);
    when(() => repo.sync()).thenAnswer((_) async => Right(NotesCache(rev: 4, items: [hospital, milk])));
    when(() => repo.delete(any())).thenAnswer((_) async => const Right(NotesCache(rev: 4, items: [milk])));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('병원'));
    await tester.pumpAndSettle();
    expect(find.text('일정 편집'), findsOneWidget);
    expect(find.text('스피커가 하루 전, 1시간 전에 말로 알려 줘요'), findsOneWidget);
    expect(find.text('여러 개 고를 수 있어요'), findsOneWidget);

    await tester.tap(find.text('10분 전'));
    await tester.pumpAndSettle();
    expect(find.text('최대 3개'), findsOneWidget);
    expect(find.text('스피커가 하루 전, 1시간 전, 10분 전에 말로 알려 줘요'), findsOneWidget);
    await tester.tap(find.text('30분 전')); // disabled
    await tester.pumpAndSettle();
    expect(find.text('스피커가 하루 전, 1시간 전, 10분 전에 말로 알려 줘요'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('“병원” 지울까요?'), findsOneWidget);
    expect(find.text('스피커에서도 지워지고 되살릴 수 없어요. 다른 가족 휴대폰에서도 사라져요.'), findsOneWidget);
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    verify(() => repo.delete(hospital)).called(1);
    expect(find.text('일정 편집'), findsNothing);
  });
}
