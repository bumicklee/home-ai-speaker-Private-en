import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/features/notes/data/models/note_model.dart';
import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape of the firmware notes JSON (design document, Section 4)
Map<String, dynamic> eventJson({int rev = 42}) => {
      'id': 'n_7f3a9c21',
      'kind': 'event',
      'title': '병원 (정형외과)',
      'body': '보험증 챙기기',
      'start': '2026-10-05T15:00',
      'end': null,
      'remind': [1440, 60],
      'reminded': [1440],
      'missed': [],
      'snooze_at': null,
      'alert': {'offset': 1440, 'status': 'acked', 'at': 1791100000},
      'created': 1791000000,
      'updated': 1791100000,
      'rev': rev,
      'by': 'voice',
      'state': 'active',
    };

void main() {
  group('NoteModel', () {
    test('일정 JSON과 알림 필드를 읽는다', () {
      final n = NoteModel.fromJson(eventJson());
      expect(n.isEvent, isTrue);
      expect(n.start, NoteTime.at(DateTime(2026, 10, 5, 15)));
      expect(n.isAllDay, isFalse);
      expect(n.remind, [1440, 60]);
      expect(n.reminded, [1440]);
      expect(n.missed, isEmpty);
      expect(n.alert, NoteAlert(offset: 1440, status: AlertStatus.acked, at: DateTime.fromMillisecondsSinceEpoch(1791100000000)));
      expect(n.rev, 42);
      expect(n.by, 'voice');
      expect(n.state, NoteState.active);
    });

    test('하루 종일 일정 (날짜만) — 시간대 변환 없이 현지 날짜 그대로', () {
      final n = NoteModel.fromJson({'id': 'n_1', 'kind': 'event', 'title': '손주 생일', 'start': '2026-10-05', 'rev': 1});
      expect(n.isAllDay, isTrue);
      expect(n.start!.at, DateTime(2026, 10, 5));
      expect(n.start!.format(), '2026-10-05');
    });

    test('지운 기록(gone)은 id·rev·state만 와도 읽힌다', () {
      final n = NoteModel.fromJson({'id': 'n_1', 'rev': 50, 'state': 'gone'});
      expect(n.isGone, isTrue);
      expect(n.rev, 50);
      expect(n.title, '');
      expect(n.remind, isEmpty);
      expect(n.alert, isNull);
    });

    test('모르는 값·깨진 값은 기본값', () {
      final n = NoteModel.fromJson({
        'id': 'n_2',
        'kind': 'todo',
        'start': '2026-02-30T10:00',
        'remind': 'x',
        'alert': {'status': 'weird'},
        'state': '?',
      });
      expect(n.kind, NoteKind.memo);
      expect(n.start, isNull);
      expect(n.remind, isEmpty);
      expect(n.alert, isNull);
      expect(n.state, NoteState.active);
    });

    test('사본 파일로 쓰고 다시 읽으면 같다', () {
      final n = NoteModel.fromJson(eventJson());
      expect(NoteModel.fromJson(NoteModel.toJson(n)), n);
    });

    test('만들기 본문: remind가 null이면 빼서 스피커 기본 알림을 쓰게 한다', () {
      final d = NoteDraft(kind: NoteKind.event, title: '병원', start: NoteTime.at(DateTime(2026, 10, 5, 15)));
      expect(NoteModel.createJson(d), {'kind': 'event', 'title': '병원', 'body': '', 'start': '2026-10-05T15:00', 'end': null});
      final withRemind = NoteDraft(kind: NoteKind.event, title: '병원', start: NoteTime.date(DateTime(2026, 10, 5)), remind: const [0]);
      expect(NoteModel.createJson(withRemind)['remind'], [0]);
      expect(NoteModel.createJson(withRemind)['start'], '2026-10-05');
      expect(NoteModel.createJson(const NoteDraft(kind: NoteKind.memo, title: '우유')).containsKey('start'), isFalse);
    });

    test('고치기 본문에 base_rev, 메모로 바꾸면 시각·알림을 비운다', () {
      final d = NoteDraft(kind: NoteKind.event, title: '병원', start: NoteTime.at(DateTime(2026, 10, 5, 16)), remind: const [60]);
      expect(NoteModel.updateJson(d, 42), {
        'base_rev': 42,
        'kind': 'event',
        'title': '병원',
        'body': '',
        'start': '2026-10-05T16:00',
        'end': null,
        'remind': [60],
      });
      final memo = NoteModel.updateJson(const NoteDraft(kind: NoteKind.memo, title: '우유'), 7);
      expect(memo['start'], isNull);
      expect(memo['remind'], isEmpty);
    });
  });

  group('NotesSettingsModel', () {
    test('읽기 + 빠진 값은 기본값 (1시간 전, 하루 종일 당일 9시)', () {
      final s = NotesSettingsModel.fromJson({
        'enabled': false,
        'default_remind': [1440, 60],
        'default_remind_all_day': [1440],
        'all_day_time': '08:30',
      });
      expect(s, const NotesSettings(enabled: false, defaultRemind: [1440, 60], defaultRemindAllDay: [1440], allDayTime: ClockTime(8, 30)));
      expect(NotesSettingsModel.fromJson({}), const NotesSettings());
      expect(NotesSettingsModel.fromJson({'all_day_time': '25:00'}).allDayTime, ClockTime.morning);
    });

    test('저장은 바뀐 키만 보낸다', () {
      const a = NotesSettings();
      expect(NotesSettingsModel.diff(a, a.copyWith(allDayTime: const ClockTime(7, 0))), {'all_day_time': '07:00'});
      expect(NotesSettingsModel.diff(a, a.copyWith(defaultRemind: [10, 0])), {'default_remind': [10, 0]});
      expect(NotesSettingsModel.diff(a, a), isEmpty);
    });
  });

  test('새 오류 코드 → 키', () {
    expect(ErrorKeys.fromDeviceStatus(409, 'FULL'), ErrorKeys.deviceNotesFull);
    expect(ErrorKeys.fromDeviceStatus(409, 'CONFLICT'), ErrorKeys.deviceConflict);
    expect(ErrorKeys.fromDeviceStatus(404, 'NOT_FOUND'), ErrorKeys.deviceNotFound);
  });
}
