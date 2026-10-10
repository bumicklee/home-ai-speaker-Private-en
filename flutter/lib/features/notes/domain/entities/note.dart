import 'package:equatable/equatable.dart';

/// Note/event kind (firmware notes module `kind`)
enum NoteKind {
  memo('memo'),
  event('event');

  const NoteKind(this.id);
  final String id;

  static NoteKind fromId(String? id) => id == 'event' ? event : memo;
}

/// active = in the list, trash = deleted by voice (30 days), gone = deletion record (id and rev only)
enum NoteState {
  active('active'),
  trash('trash'),
  gone('gone');

  const NoteState(this.id);
  final String id;

  static NoteState fromId(String? id) => values.firstWhere((s) => s.id == id, orElse: () => active);
}

/// Result of the last reminder conversation (`alert.status`)
enum AlertStatus {
  sent('sent'),
  acked('acked'),
  noAnswer('no_answer'),
  missed('missed');

  const AlertStatus(this.id);
  final String id;

  static AlertStatus? fromId(String? id) => values.where((s) => s.id == id).firstOrNull;
}

/// Event time. The speaker's local time string as is (no time zone conversion)
/// `YYYY-MM-DD` = all day, `YYYY-MM-DDTHH:MM` = with a time
class NoteTime extends Equatable {
  NoteTime.date(DateTime d)
      : at = DateTime(d.year, d.month, d.day),
        allDay = true;

  NoteTime.at(DateTime t)
      : at = DateTime(t.year, t.month, t.day, t.hour, t.minute),
        allDay = false;

  final DateTime at;
  final bool allDay;

  DateTime get day => DateTime(at.year, at.month, at.day);

  static final _re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?');

  /// null if the format is wrong or the date doesn't exist
  static NoteTime? tryParse(Object? s) {
    if (s is! String) return null;
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, mo, d);
    if (date.month != mo) return null; // dates like February 30
    if (m[4] == null) return NoteTime.date(date);
    final h = int.parse(m[4]!), mi = int.parse(m[5]!);
    if (h > 23 || mi > 59) return null;
    return NoteTime.at(DateTime(y, mo, d, h, mi));
  }

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${at.year.toString().padLeft(4, '0')}-${two(at.month)}-${two(at.day)}';
    return allDay ? date : '${date}T${two(at.hour)}:${two(at.minute)}';
  }

  @override
  String toString() => format();

  @override
  List<Object?> get props => [at, allDay];
}

/// Hour:minute (reminder time for all-day events, `all_day_time`)
class ClockTime extends Equatable {
  const ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;

  static const morning = ClockTime(9, 0);

  static ClockTime parse(Object? s, {ClockTime fallback = morning}) {
    if (s is! String) return fallback;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return fallback;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    return h > 23 || mi > 59 ? fallback : ClockTime(h, mi);
  }

  String format() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [hour, minute];
}

/// Last reminder (`alert`). offset = how many minutes before it was (-1 = a "나중에 다시" (remind me later) reminder)
class NoteAlert extends Equatable {
  const NoteAlert({required this.offset, required this.status, this.at});

  final int offset;
  final AlertStatus status;
  final DateTime? at;

  @override
  List<Object?> get props => [offset, status, at];
}

/// One note or event (design document Section 4)
class Note extends Equatable {
  const Note({
    required this.id,
    this.kind = NoteKind.memo,
    this.title = '',
    this.body = '',
    this.start,
    this.end,
    this.remind = const [],
    this.reminded = const [],
    this.missed = const [],
    this.snoozeAt,
    this.alert,
    this.created,
    this.updated,
    this.rev = 0,
    this.by = '',
    this.state = NoteState.active,
  });

  final String id;
  final NoteKind kind;
  final String title;
  final String body;
  final NoteTime? start;
  final NoteTime? end;

  /// How many minutes before the start to remind (0 = on time, up to 3)
  final List<int> remind;
  final List<int> reminded;
  final List<int> missed;
  final DateTime? snoozeAt;
  final NoteAlert? alert;
  final DateTime? created;
  final DateTime? updated;
  final int rev;

  /// voice / app
  final String by;
  final NoteState state;

  static const maxReminders = 3;
  static const maxRemindMinutes = 10080;
  static const titleMaxBytes = 80;
  static const bodyMaxBytes = 600;

  bool get isEvent => kind == NoteKind.event;
  bool get isMemo => kind == NoteKind.memo;
  bool get isActive => state == NoteState.active;
  bool get isTrash => state == NoteState.trash;
  bool get isGone => state == NoteState.gone;
  bool get isAllDay => start?.allDay ?? false;

  /// Reminder reference time. For all-day events, [allDayTime] on that day
  DateTime? baseTime(ClockTime allDayTime) {
    final s = start;
    if (s == null) return null;
    return s.allDay ? DateTime(s.at.year, s.at.month, s.at.day, allDayTime.hour, allDayTime.minute) : s.at;
  }

  /// When the reminder [minutes] before rings
  DateTime? fireTime(int minutes, ClockTime allDayTime) => baseTime(allDayTime)?.subtract(Duration(minutes: minutes));

  /// Reminders that haven't rung yet and are still to come (minutes)
  List<int> pendingReminders(DateTime now, ClockTime allDayTime) => [
        for (final m in remind)
          if (!reminded.contains(m) && !missed.contains(m) && (fireTime(m, allDayTime)?.isAfter(now) ?? false)) m,
      ];

  @override
  List<Object?> get props =>
      [id, kind, title, body, start, end, remind, reminded, missed, snoozeAt, alert, created, updated, rev, by, state];
}

/// Create/edit body (the speaker decides id and rev)
class NoteDraft extends Equatable {
  const NoteDraft({required this.kind, required this.title, this.body = '', this.start, this.end, this.remind});

  final NoteKind kind;
  final String title;
  final String body;
  final NoteTime? start;
  final NoteTime? end;

  /// null = not sent (on create, the speaker's default reminders are used)
  final List<int>? remind;

  @override
  List<Object?> get props => [kind, title, body, start, end, remind];
}

/// Schedule reminder settings (one for the whole speaker, `/notes/settings`)
class NotesSettings extends Equatable {
  const NotesSettings({
    this.enabled = true,
    this.defaultRemind = const [60],
    this.defaultRemindAllDay = const [0],
    this.allDayTime = ClockTime.morning,
  });

  final bool enabled;
  final List<int> defaultRemind;
  final List<int> defaultRemindAllDay;
  final ClockTime allDayTime;

  NotesSettings copyWith({bool? enabled, List<int>? defaultRemind, List<int>? defaultRemindAllDay, ClockTime? allDayTime}) =>
      NotesSettings(
        enabled: enabled ?? this.enabled,
        defaultRemind: defaultRemind ?? this.defaultRemind,
        defaultRemindAllDay: defaultRemindAllDay ?? this.defaultRemindAllDay,
        allDayTime: allDayTime ?? this.allDayTime,
      );

  @override
  List<Object?> get props => [enabled, defaultRemind, defaultRemindAllDay, allDayTime];
}

/// Copy kept on the phone (one per speaker)
class NotesCache extends Equatable {
  const NotesCache({this.rev = 0, this.items = const [], this.settings});

  final int rev;

  /// active and trash (gone is removed from the copy)
  final List<Note> items;

  /// Last reminder settings received (so the all-day time etc. show even away from home)
  final NotesSettings? settings;

  NotesCache copyWith({int? rev, List<Note>? items, NotesSettings? settings}) =>
      NotesCache(rev: rev ?? this.rev, items: items ?? this.items, settings: settings ?? this.settings);

  /// Merge changed items: per id the higher rev wins; gone removes it from the copy.
  /// [replace] = full list (since=0), so items not in what was received are removed
  NotesCache merge(int serverRev, Iterable<Note> changes, {bool replace = false}) {
    final byId = <String, Note>{if (!replace) for (final n in items) n.id: n};
    for (final c in changes) {
      final old = byId[c.id];
      if (old != null && old.rev > c.rev) continue;
      if (c.isGone) {
        byId.remove(c.id);
      } else {
        byId[c.id] = c;
      }
    }
    final next = replace ? serverRev : (serverRev > rev ? serverRev : rev);
    return NotesCache(rev: next, items: byId.values.toList(), settings: settings);
  }

  @override
  List<Object?> get props => [rev, items, settings];
}
