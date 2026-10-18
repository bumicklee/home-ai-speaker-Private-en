import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/features/notes/data/models/note_model.dart';
import 'package:aispeaker/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape of the firmware notes JSON (design document, Section 4)
Map<String, dynamic> eventJson({int rev = 42}) => {
      'id': 'n_7f3a9c21',
      'kind': 'event',
      'title': 'Doctor (orthopedics)',
      'body': 'Bring insurance card',
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
    test('reads event JSON and reminder fields', () {
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

    test('all-day event (date only) keeps the local date with no time zone conversion', () {
      final n = NoteModel.fromJson({'id': 'n_1', 'kind': 'event', 'title': "Grandson's birthday", 'start': '2026-10-05', 'rev': 1});
      expect(n.isAllDay, isTrue);
      expect(n.start!.at, DateTime(2026, 10, 5));
      expect(n.start!.format(), '2026-10-05');
    });

    test('a deleted record (gone) reads with only id, rev and state', () {
      final n = NoteModel.fromJson({'id': 'n_1', 'rev': 50, 'state': 'gone'});
      expect(n.isGone, isTrue);
      expect(n.rev, 50);
      expect(n.title, '');
      expect(n.remind, isEmpty);
      expect(n.alert, isNull);
    });

    test('unknown or broken values fall back to defaults', () {
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

    test('writing to the copy file and reading back gives the same note', () {
      final n = NoteModel.fromJson(eventJson());
      expect(NoteModel.fromJson(NoteModel.toJson(n)), n);
    });

    test('create body: omits a null remind so the speaker uses its default reminders', () {
      final d = NoteDraft(kind: NoteKind.event, title: 'Doctor', start: NoteTime.at(DateTime(2026, 10, 5, 15)));
      expect(NoteModel.createJson(d), {'kind': 'event', 'title': 'Doctor', 'body': '', 'start': '2026-10-05T15:00', 'end': null});
      final withRemind = NoteDraft(kind: NoteKind.event, title: 'Doctor', start: NoteTime.date(DateTime(2026, 10, 5)), remind: const [0]);
      expect(NoteModel.createJson(withRemind)['remind'], [0]);
      expect(NoteModel.createJson(withRemind)['start'], '2026-10-05');
      expect(NoteModel.createJson(const NoteDraft(kind: NoteKind.memo, title: 'Milk')).containsKey('start'), isFalse);
    });

    test('update body carries base_rev; switching to a memo clears time and reminders', () {
      final d = NoteDraft(kind: NoteKind.event, title: 'Doctor', start: NoteTime.at(DateTime(2026, 10, 5, 16)), remind: const [60]);
      expect(NoteModel.updateJson(d, 42), {
        'base_rev': 42,
        'kind': 'event',
        'title': 'Doctor',
        'body': '',
        'start': '2026-10-05T16:00',
        'end': null,
        'remind': [60],
      });
      final memo = NoteModel.updateJson(const NoteDraft(kind: NoteKind.memo, title: 'Milk'), 7);
      expect(memo['start'], isNull);
      expect(memo['remind'], isEmpty);
    });
  });

  group('NotesSettingsModel', () {
    test('reads, with defaults for missing values (1 hour before; all-day at 9 on the day)', () {
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

    test('saving sends only the changed keys', () {
      const a = NotesSettings();
      expect(NotesSettingsModel.diff(a, a.copyWith(allDayTime: const ClockTime(7, 0))), {'all_day_time': '07:00'});
      expect(NotesSettingsModel.diff(a, a.copyWith(defaultRemind: [10, 0])), {'default_remind': [10, 0]});
      expect(NotesSettingsModel.diff(a, a), isEmpty);
    });
  });

  test('new error codes map to keys', () {
    expect(ErrorKeys.fromDeviceStatus(409, 'FULL'), ErrorKeys.deviceNotesFull);
    expect(ErrorKeys.fromDeviceStatus(409, 'CONFLICT'), ErrorKeys.deviceConflict);
    expect(ErrorKeys.fromDeviceStatus(404, 'NOT_FOUND'), ErrorKeys.deviceNotFound);
  });
}
