import 'dart:async';
import 'dart:io';

import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/notes/data/datasources/notes_local_store.dart';
import 'package:aispeaker/features/notes/data/datasources/notes_remote_datasource.dart';
import 'package:aispeaker/features/notes/data/repositories/notes_repository.dart';
import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDevice extends Mock implements CurrentDevice {}

class MockEvents extends Mock implements DeviceEventService {}

class MockRemote extends Mock implements NotesRemoteDataSource {}

Map<String, dynamic> memo(String id, int rev, {String title = '메모', String state = 'active'}) =>
    {'id': id, 'kind': 'memo', 'title': title, 'rev': rev, 'state': state};

void main() {
  late Directory dir;
  late MockDevice device;
  late MockEvents events;
  late MockRemote remote;
  late NotesLocalStore store;
  late NotesRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notes_test');
    device = MockDevice();
    events = MockEvents();
    remote = MockRemote();
    store = NotesLocalStore(directory: () async => dir);
    when(() => device.deviceId).thenReturn('A1B2C3');
    repo = NotesRepository(device, events, remote, store);
  });

  tearDown(() => dir.delete(recursive: true));

  group('합치기 (NotesCache.merge)', () {
    const n = Note(id: 'a', title: 'old', rev: 5);

    test('rev가 큰 쪽이 이긴다', () {
      final c = const NotesCache(rev: 5, items: [n]);
      expect(c.merge(6, [const Note(id: 'a', title: 'new', rev: 6)]).items.single.title, 'new');
      expect(c.merge(6, [const Note(id: 'a', title: 'stale', rev: 4)]).items.single.title, 'old');
      expect(c.merge(6, const []).rev, 6);
      expect(c.merge(3, const []).rev, 5, reason: '사본 rev는 줄지 않는다');
    });

    test('gone은 사본에서 지운다', () {
      final c = const NotesCache(rev: 5, items: [n, Note(id: 'b', rev: 2)]);
      final m = c.merge(7, [const Note(id: 'a', rev: 7, state: NoteState.gone)]);
      expect(m.items.map((x) => x.id), ['b']);
    });

    test('전체(replace)면 받은 것에 없는 항목은 지운다', () {
      final c = const NotesCache(rev: 50, items: [n]);
      final m = c.merge(3, [const Note(id: 'z', rev: 3)], replace: true);
      expect(m.items.map((x) => x.id), ['z']);
      expect(m.rev, 3);
    });
  });

  group('sync', () {
    test('처음엔 since=0으로 전체, 다음엔 since=rev로 바뀐 것만 받아 파일에 저장', () async {
      when(() => remote.changes(0)).thenAnswer((_) async => {
            'rev': 10,
            'items': [memo('a', 3), memo('b', 10), memo('c', 9, state: 'gone')],
          });
      final first = await repo.sync();
      expect(first.getOrElse(() => throw 'x').items.map((n) => n.id), ['a', 'b']);

      when(() => remote.changes(10)).thenAnswer((_) async => {
            'rev': 12,
            'items': [memo('a', 11, title: '바뀜'), memo('b', 12, state: 'gone'), memo('d', 12)],
          });
      final second = (await repo.sync()).getOrElse(() => throw 'x');
      expect(second.rev, 12);
      expect({for (final n in second.items) n.id: n.title}, {'a': '바뀜', 'd': '메모'});

      // the same copy from the file even after the app restarts
      final saved = await NotesLocalStore(directory: () async => dir).read('A1B2C3');
      expect(saved.rev, 12);
      expect(saved.items.map((n) => n.id).toSet(), {'a', 'd'});
    });

    test('스피커 rev가 사본보다 작으면(초기화) 전체를 다시 받아 바꾼다', () async {
      await store.write('A1B2C3', const NotesCache(rev: 40, items: [Note(id: 'old', rev: 40)]));
      when(() => remote.changes(40)).thenAnswer((_) async => {'rev': 2, 'items': []});
      when(() => remote.changes(0)).thenAnswer((_) async => {
            'rev': 2,
            'items': [memo('new', 2)],
          });
      final c = (await repo.sync()).getOrElse(() => throw 'x');
      expect(c.items.map((n) => n.id), ['new']);
      expect(c.rev, 2);
    });

    test('스피커에 닿지 않으면 NetworkFailure, 사본은 그대로', () async {
      await store.write('A1B2C3', const NotesCache(rev: 4, items: [Note(id: 'a', rev: 4)]));
      when(() => remote.changes(4)).thenThrow(const NetworkException('refused'));
      final r = await repo.sync();
      expect(r.fold((f) => f, (_) => null), isA<NetworkFailure>());
      expect((await repo.cached()).items.single.id, 'a');
    });
  });

  group('고치기·지우기', () {
    final event = Note(
        id: 'n_1', kind: NoteKind.event, title: '병원', start: NoteTime.at(DateTime(2026, 10, 5, 15)), remind: const [60], rev: 5);

    setUp(() async {
      await store.write('A1B2C3', NotesCache(rev: 5, items: [event]));
    });

    test('409 CONFLICT: 사본을 본문의 최신 항목으로 바꾸고 errorDeviceConflict', () async {
      when(() => remote.update(any(), any())).thenThrow(DeviceApiException(409, 'CONFLICT', 'conflict', {
            'error': 'CONFLICT',
            'note': {'id': 'n_1', 'kind': 'event', 'title': '병원 (말로 바꿈)', 'start': '2026-10-05T16:00', 'rev': 8},
          }));
      final draft = NoteDraft(kind: NoteKind.event, title: '병원 2', start: event.start, remind: const [30]);
      final r = await repo.update(event, draft);
      final f = r.fold((f) => f, (_) => null);
      expect(f?.errorKey, ErrorKeys.deviceConflict);
      expect(f?.code, 'CONFLICT');
      final latest = (await repo.cached()).items.single;
      expect(latest.title, '병원 (말로 바꿈)');
      expect(latest.rev, 8);
      final body = verify(() => remote.update('n_1', captureAny())).captured.single as Map<String, dynamic>;
      expect(body['base_rev'], 5);
      expect(body['remind'], [30]);
    });

    test('고친 항목을 반영해도 사본 rev는 그대로 (그 사이 다른 변경을 놓치지 않게)', () async {
      when(() => remote.update(any(), any())).thenAnswer((_) async => {
            'id': 'n_1',
            'kind': 'event',
            'title': '병원 2',
            'start': '2026-10-05T15:00',
            'remind': [30],
            'rev': 9,
          });
      final c = (await repo.update(event, NoteDraft(kind: NoteKind.event, title: '병원 2', start: event.start)))
          .getOrElse(() => throw 'x');
      expect(c.items.single.title, '병원 2');
      expect(c.rev, 5);
    });

    test('지우기: DELETE 뒤 사본에서 뺀다', () async {
      when(() => remote.delete('n_1')).thenAnswer((_) async => {'id': 'n_1', 'rev': 6, 'state': 'gone'});
      final c = (await repo.delete(event)).getOrElse(() => throw 'x');
      expect(c.items, isEmpty);
    });

    test('409 FULL → errorDeviceNotesFull', () async {
      when(() => remote.create(any())).thenThrow(const DeviceApiException(409, 'FULL'));
      final r = await repo.create(const NoteDraft(kind: NoteKind.memo, title: '우유'));
      expect(r.fold((f) => f.errorKey, (_) => null), ErrorKeys.deviceNotesFull);
    });
  });

  test('알림 설정: 받아서 사본에도 둔다, 저장은 바뀐 키만', () async {
    when(() => remote.settings()).thenAnswer((_) async => {
          'enabled': true,
          'default_remind': [60],
          'default_remind_all_day': [0],
          'all_day_time': '09:00',
        });
    final s = (await repo.settings()).getOrElse(() => throw 'x');
    expect(s, const NotesSettings());
    expect((await NotesLocalStore(directory: () async => dir).read('A1B2C3')).settings, s);

    when(() => remote.saveSettings(any())).thenAnswer((_) async => {
          'enabled': true,
          'default_remind': [60],
          'default_remind_all_day': [0],
          'all_day_time': '08:00',
        });
    final saved = (await repo.saveSettings(s, s.copyWith(allDayTime: const ClockTime(8, 0)))).getOrElse(() => throw 'x');
    expect(saved.allDayTime, const ClockTime(8, 0));
    verify(() => remote.saveSettings({'all_day_time': '08:00'})).called(1);
  });

  test('WS notes·reminder 이벤트와 다시 연결될 때 알린다 (다른 이벤트는 무시)', () async {
    final ws = StreamController<DeviceEvent>.broadcast();
    final conn = StreamController<EventConnection>.broadcast();
    when(() => events.events).thenAnswer((_) => ws.stream);
    when(() => events.connection).thenAnswer((_) => conn.stream);
    var count = 0;
    final sub = repo.changes().listen((_) => count++);
    ws
      ..add(const DeviceEvent('notes', {'rev': 43}))
      ..add(const DeviceEvent('reminder', {'id': 'n_1', 'status': 'acked'}))
      ..add(const DeviceEvent('volume', {'volume': 3}));
    conn.add(EventConnection.connected);
    await Future<void>.delayed(Duration.zero);
    expect(count, 3);
    await sub.cancel();
    await ws.close();
    await conn.close();
  });
}
