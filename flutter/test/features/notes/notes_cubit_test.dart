import 'dart:async';

import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/features/notes/data/repositories/notes_repository.dart';
import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:aispeaker/features/notes/presentation/bloc/notes_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements NotesRepository {}

const memo = Note(id: 'a', title: '우유', rev: 3);
const cache = NotesCache(rev: 3, items: [memo]);
const conflict = DeviceFailure(errorKey: ErrorKeys.deviceConflict, status: 409, code: 'CONFLICT');

void main() {
  setUpAll(() {
    registerFallbackValue(const Note(id: 'x'));
    registerFallbackValue(const NoteDraft(kind: NoteKind.memo, title: 'x'));
    registerFallbackValue(const NotesSettings());
  });

  late MockRepo repo;
  late StreamController<void> changes;

  setUp(() {
    repo = MockRepo();
    changes = StreamController<void>.broadcast();
    when(() => repo.changes()).thenAnswer((_) => changes.stream);
    when(() => repo.cached()).thenAnswer((_) async => cache);
    when(() => repo.settings()).thenAnswer((_) async => const Right(NotesSettings(allDayTime: ClockTime(8, 0))));
  });

  tearDown(() => changes.close());

  test('사본을 먼저 보여 주고 맞춘 뒤 알림 설정을 받는다', () async {
    const synced = NotesCache(rev: 5, items: [memo, Note(id: 'b', rev: 5)]);
    when(() => repo.sync()).thenAnswer((_) async => const Right(synced));
    final c = NotesCubit(repo);
    final seen = <NotesState>[];
    final sub = c.stream.listen(seen.add);
    await c.load();
    expect(seen.first.items, [memo], reason: '사본 먼저');
    expect(seen.first.loaded, isTrue);
    expect(c.state.items.length, 2);
    expect(c.state.rev, 5);
    expect(c.state.offline, isFalse);
    expect(c.state.settings.allDayTime, const ClockTime(8, 0));
    await sub.cancel();
    await c.close();
  });

  test('스피커에 닿지 않으면 사본 + 읽기 전용 (오류 문구 대신 안내)', () async {
    when(() => repo.sync()).thenAnswer((_) async => const Left(NetworkFailure()));
    final c = NotesCubit(repo);
    await c.load();
    expect(c.state.items, [memo]);
    expect(c.state.offline, isTrue);
    expect(c.state.readOnly, isTrue);
    expect(c.state.failure, isNull);
    verifyNever(() => repo.settings());

    // touching it again releases it
    when(() => repo.sync()).thenAnswer((_) async => const Right(cache));
    await c.sync();
    expect(c.state.offline, isFalse);
    await c.close();
  });

  test('WS 이벤트가 오면 다시 맞춘다', () async {
    when(() => repo.sync()).thenAnswer((_) async => const Right(cache));
    final c = NotesCubit(repo);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    verify(() => repo.sync()).called(1);
    await c.close();
  });

  test('저장 성공: 새 사본', () async {
    const updated = NotesCache(rev: 3, items: [Note(id: 'a', title: '우유 2', rev: 4)]);
    when(() => repo.update(any(), any())).thenAnswer((_) async => const Right(updated));
    final c = NotesCubit(repo);
    final ok = await c.save(memo, const NoteDraft(kind: NoteKind.memo, title: '우유 2'));
    expect(ok, isTrue);
    expect(c.state.items.single.title, '우유 2');
    expect(c.state.busy, isFalse);
    await c.close();
  });

  test('409 충돌: 실패와 함께 레포가 바꿔 둔 최신 사본을 보여 준다', () async {
    const latest = NotesCache(rev: 3, items: [Note(id: 'a', title: '말로 바꿈', rev: 7)]);
    when(() => repo.update(any(), any())).thenAnswer((_) async {
      when(() => repo.cached()).thenAnswer((_) async => latest);
      return const Left(conflict);
    });
    final c = NotesCubit(repo);
    final ok = await c.save(memo, const NoteDraft(kind: NoteKind.memo, title: '우유 2'));
    expect(ok, isFalse);
    expect(c.state.failure, conflict);
    expect(c.state.byId('a')?.title, '말로 바꿈');
    expect(c.state.byId('a')?.rev, 7);
    await c.close();
  });

  test('새로 만들기는 create, 지우기는 delete (스피커 원본 삭제)', () async {
    when(() => repo.create(any())).thenAnswer((_) async => const Right(cache));
    when(() => repo.delete(any())).thenAnswer((_) async => const Right(NotesCache(rev: 3)));
    final c = NotesCubit(repo);
    expect(await c.save(null, const NoteDraft(kind: NoteKind.memo, title: '우유')), isTrue);
    verify(() => repo.create(const NoteDraft(kind: NoteKind.memo, title: '우유'))).called(1);
    expect(await c.delete(memo), isTrue);
    verify(() => repo.delete(memo)).called(1);
    expect(c.state.items, isEmpty);
    await c.close();
  });

  test('알림 설정 저장 실패면 되돌린다', () async {
    when(() => repo.saveSettings(any(), any())).thenAnswer((_) async => const Left(DeviceFailure.timeout()));
    final c = NotesCubit(repo);
    final ok = await c.saveSettings(const NotesSettings(enabled: false));
    expect(ok, isFalse);
    expect(c.state.settings.enabled, isTrue);
    expect(c.state.failure, const DeviceFailure.timeout());
    await c.close();
  });

  test('닫힌 뒤 끝난 요청은 무시', () async {
    final done = Completer<Either<Failure, NotesCache>>();
    when(() => repo.sync()).thenAnswer((_) => done.future);
    final c = NotesCubit(repo);
    final f = c.sync();
    await c.close();
    done.complete(const Right(cache));
    expect(await f, isFalse);
  });
}
