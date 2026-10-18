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

const memo = Note(id: 'a', title: 'Buy milk', rev: 3);
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

  test('shows the local copy first, syncs, then loads reminder settings', () async {
    const synced = NotesCache(rev: 5, items: [memo, Note(id: 'b', rev: 5)]);
    when(() => repo.sync()).thenAnswer((_) async => const Right(synced));
    final c = NotesCubit(repo);
    final seen = <NotesState>[];
    final sub = c.stream.listen(seen.add);
    await c.load();
    expect(seen.first.items, [memo], reason: 'local copy first');
    expect(seen.first.loaded, isTrue);
    expect(c.state.items.length, 2);
    expect(c.state.rev, 5);
    expect(c.state.offline, isFalse);
    expect(c.state.settings.allDayTime, const ClockTime(8, 0));
    await sub.cancel();
    await c.close();
  });

  test('when the speaker is unreachable: local copy + read-only (a notice instead of an error message)', () async {
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

  test('syncs again on a WS event', () async {
    when(() => repo.sync()).thenAnswer((_) async => const Right(cache));
    final c = NotesCubit(repo);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    verify(() => repo.sync()).called(1);
    await c.close();
  });

  test('save succeeds: new local copy', () async {
    const updated = NotesCache(rev: 3, items: [Note(id: 'a', title: 'Buy milk 2', rev: 4)]);
    when(() => repo.update(any(), any())).thenAnswer((_) async => const Right(updated));
    final c = NotesCubit(repo);
    final ok = await c.save(memo, const NoteDraft(kind: NoteKind.memo, title: 'Buy milk 2'));
    expect(ok, isTrue);
    expect(c.state.items.single.title, 'Buy milk 2');
    expect(c.state.busy, isFalse);
    await c.close();
  });

  test('409 conflict: fails and shows the latest copy the repo stored', () async {
    const latest = NotesCache(rev: 3, items: [Note(id: 'a', title: 'Changed by voice', rev: 7)]);
    when(() => repo.update(any(), any())).thenAnswer((_) async {
      when(() => repo.cached()).thenAnswer((_) async => latest);
      return const Left(conflict);
    });
    final c = NotesCubit(repo);
    final ok = await c.save(memo, const NoteDraft(kind: NoteKind.memo, title: 'Buy milk 2'));
    expect(ok, isFalse);
    expect(c.state.failure, conflict);
    expect(c.state.byId('a')?.title, 'Changed by voice');
    expect(c.state.byId('a')?.rev, 7);
    await c.close();
  });

  test('new uses create, removing uses delete (deletes the speaker original)', () async {
    when(() => repo.create(any())).thenAnswer((_) async => const Right(cache));
    when(() => repo.delete(any())).thenAnswer((_) async => const Right(NotesCache(rev: 3)));
    final c = NotesCubit(repo);
    expect(await c.save(null, const NoteDraft(kind: NoteKind.memo, title: 'Buy milk')), isTrue);
    verify(() => repo.create(const NoteDraft(kind: NoteKind.memo, title: 'Buy milk'))).called(1);
    expect(await c.delete(memo), isTrue);
    verify(() => repo.delete(memo)).called(1);
    expect(c.state.items, isEmpty);
    await c.close();
  });

  test('reverts when saving reminder settings fails', () async {
    when(() => repo.saveSettings(any(), any())).thenAnswer((_) async => const Left(DeviceFailure.timeout()));
    final c = NotesCubit(repo);
    final ok = await c.saveSettings(const NotesSettings(enabled: false));
    expect(ok, isFalse);
    expect(c.state.settings.enabled, isTrue);
    expect(c.state.failure, const DeviceFailure.timeout());
    await c.close();
  });

  test('ignores requests that finish after close', () async {
    final done = Completer<Either<Failure, NotesCache>>();
    when(() => repo.sync()).thenAnswer((_) => done.future);
    final c = NotesCubit(repo);
    final f = c.sync();
    await c.close();
    done.complete(const Right(cache));
    expect(await f, isFalse);
  });
}
