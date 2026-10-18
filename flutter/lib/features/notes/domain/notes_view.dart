/// Calculations for the list screen (grouping, sorting, search, reminder status). Tested without widgets
library;

import 'entities/note.dart';

/// Schedule groups (design "Notes & schedule": today · tomorrow · this week · later · past events)
enum EventGroupKind { today, tomorrow, thisWeek, later, past }

class EventGroup {
  const EventGroup(this.kind, this.day, this.items);

  final EventGroupKind kind;

  /// Date of the today/tomorrow groups (title "Today · Sun, Oct 4")
  final DateTime day;
  final List<Note> items;
}

/// Status shown at the right of a list row
enum NoteBadge { none, scheduled, sent, acked, noAnswer, missed }

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Does the title or body contain the text (ignoring case and spaces, same way as the speaker's notes_search)
bool matchesQuery(Note n, String query) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final q = norm(query);
  if (q.isEmpty) return true;
  return norm(n.title).contains(q) || norm(n.body).contains(q);
}

int _byStart(Note a, Note b) {
  final sa = a.start, sb = b.start;
  if (sa == null || sb == null) return sa == null ? (sb == null ? 0 : 1) : -1;
  final c = sa.day.compareTo(sb.day);
  if (c != 0) return c;
  if (sa.allDay != sb.allDay) return sa.allDay ? -1 : 1; // on the same day, all-day comes first
  return sa.at.compareTo(sb.at);
}

/// Groups events by date. This week = within 7 days starting the day after tomorrow; past events most recent first
List<EventGroup> groupEvents(Iterable<Note> notes, DateTime now) {
  final today = _day(now);
  final tomorrow = today.add(const Duration(days: 1));
  final weekEnd = today.add(const Duration(days: 7));
  final buckets = {for (final k in EventGroupKind.values) k: <Note>[]};
  for (final n in notes) {
    if (!n.isActive || !n.isEvent || n.start == null) continue;
    final d = n.start!.day;
    final kind = d.isBefore(today)
        ? EventGroupKind.past
        : d == today
            ? EventGroupKind.today
            : d == tomorrow
                ? EventGroupKind.tomorrow
                : d.isBefore(weekEnd)
                    ? EventGroupKind.thisWeek
                    : EventGroupKind.later;
    buckets[kind]!.add(n);
  }
  for (final e in buckets.entries) {
    e.value.sort(_byStart);
    if (e.key == EventGroupKind.past) e.value.setAll(0, e.value.reversed.toList());
  }
  return [
    for (final k in EventGroupKind.values)
      if (buckets[k]!.isNotEmpty) EventGroup(k, k == EventGroupKind.tomorrow ? tomorrow : today, buckets[k]!),
  ];
}

/// Notes: most recently edited first
List<Note> sortedMemos(Iterable<Note> notes) =>
    notes.where((n) => n.isActive && n.isMemo).toList()..sort((a, b) => _updated(b).compareTo(_updated(a)));

/// Trash: most recently deleted first
List<Note> sortedTrash(Iterable<Note> notes) =>
    notes.where((n) => n.isTrash).toList()..sort((a, b) => _updated(b).compareTo(_updated(a)));

DateTime _updated(Note n) => n.updated ?? n.created ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Days left until permanently removed from the trash (the speaker changes it to gone after 30 days)
int trashDaysLeft(Note n, DateTime now, {int keepDays = 30}) {
  final since = n.updated;
  if (since == null) return keepDays;
  final left = keepDays - now.difference(since).inDays;
  return left.clamp(0, keepDays);
}

/// How long a reminder counts as just finished (within this, show the result even if another reminder is still pending)
const alertFreshFor = Duration(hours: 6);

/// Status: the recent reminder result if any; "Reminder set" if a reminder is still to ring; "Missed" if only missed ones remain
NoteBadge badgeOf(Note n, DateTime now, ClockTime allDayTime) {
  if (!n.isEvent || !n.isActive) return NoteBadge.none;
  final pending = n.pendingReminders(now, allDayTime).isNotEmpty || (n.snoozeAt?.isAfter(now) ?? false);
  final alert = n.alert;
  if (alert != null) {
    final at = alert.at;
    final fresh = at == null || now.difference(at) < alertFreshFor;
    if (!pending || fresh) {
      return switch (alert.status) {
        AlertStatus.sent => NoteBadge.sent,
        AlertStatus.acked => NoteBadge.acked,
        AlertStatus.noAnswer => NoteBadge.noAnswer,
        AlertStatus.missed => NoteBadge.missed,
      };
    }
  }
  if (pending) return NoteBadge.scheduled;
  if (n.missed.isNotEmpty) return NoteBadge.missed;
  return NoteBadge.none;
}

/// Home tile subtitle ("2 today · 3 o'clock Doctor")
class TodaySummary {
  const TodaySummary(this.count, this.next);

  final int count;

  /// The next event today that hasn't passed (if none, today's first event; null if no events today)
  final Note? next;
}

TodaySummary todaySummary(Iterable<Note> notes, DateTime now) {
  final today = groupEvents(notes, now).where((g) => g.kind == EventGroupKind.today).firstOrNull?.items ?? const [];
  final upcoming = today.where((n) => !n.isAllDay && !n.start!.at.isBefore(now)).firstOrNull;
  return TodaySummary(today.length, upcoming ?? today.firstOrNull);
}

/// Toggle a reminder chip: remove it if present, otherwise add it (up to 3). Sorted largest (earliest reminder) first
List<int> toggleRemind(List<int> current, int minutes) {
  if (current.contains(minutes)) return [...current]..remove(minutes);
  if (current.length >= Note.maxReminders || minutes < 0 || minutes > Note.maxRemindMinutes) return current;
  return [...current, minutes]..sort((a, b) => b.compareTo(a));
}
