import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/note.dart';
import '../../domain/notes_view.dart';

/// Values always shown on the reminder chips (table in design document Section 4). Custom entry is separate
const remindPresets = [0, 10, 30, 60, 120, 1440];

String _locale(BuildContext context) => Localizations.localeOf(context).toLanguageTag();

/// "9:00 AM"
String clockText(BuildContext context, ClockTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: t.hour, minute: t.minute));

/// Short time for the home subtitle ("3 o'clock", "3:30")
String shortClock(AppLocalizations l, DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return t.minute == 0 ? l.notesClockHour(h) : l.notesClockHourMinute(h, t.minute.toString().padLeft(2, '0'));
}

/// "Sun, Oct 4"
String dayText(BuildContext context, DateTime d) => DateFormat.MMMEd(_locale(context)).format(d);

/// One reminder ("1 hr before"; for all-day, 0 = "Same day 9:00 AM")
String remindLabel(BuildContext context, int minutes, {required bool allDay, required ClockTime allDayTime}) {
  final l = AppLocalizations.of(context);
  if (minutes == 0) return allDay ? l.notesRemindSameDay(clockText(context, allDayTime)) : l.notesRemindOnTime;
  if (minutes == 1440) return l.notesRemindDayBefore;
  if (minutes % 1440 == 0) return l.notesRemindDays(minutes ~/ 1440);
  if (minutes % 60 == 0) return l.notesRemindHours(minutes ~/ 60);
  if (minutes > 60) return l.notesRemindHoursMinutes(minutes ~/ 60, minutes % 60);
  return l.notesRemindMinutes(minutes);
}

/// Joins reminders earliest first ("1 day before · 1 hr before"). "No reminder" if none
String remindList(BuildContext context, List<int> remind,
    {required bool allDay, required ClockTime allDayTime, String separator = ' · '}) {
  if (remind.isEmpty) return AppLocalizations.of(context).notesRemindNone;
  final sorted = [...remind]..sort((a, b) => b.compareTo(a));
  return sorted.map((m) => remindLabel(context, m, allDay: allDay, allDayTime: allDayTime)).join(separator);
}

/// "The speaker will tell you 1 day before, 1 hr before"
String remindSummary(BuildContext context, List<int> remind, {required bool allDay, required ClockTime allDayTime}) {
  final l = AppLocalizations.of(context);
  if (remind.isEmpty) return l.notesRemindNone;
  return l.notesRemindSummary(remindList(context, remind, allDay: allDay, allDayTime: allDayTime, separator: ', '));
}

String? badgeText(AppLocalizations l, NoteBadge b) => switch (b) {
      NoteBadge.none => null,
      NoteBadge.scheduled => l.notesBadgeScheduled,
      NoteBadge.sent => l.notesBadgeSent,
      NoteBadge.acked => l.notesBadgeAcked,
      NoteBadge.noAnswer => l.notesBadgeNoAnswer,
      NoteBadge.missed => l.notesBadgeMissed,
    };

/// (text color, background color)
(Color, Color) badgeColors(BuildContext context, NoteBadge b) {
  final scheme = Theme.of(context).colorScheme;
  return switch (b) {
    NoteBadge.sent => (scheme.primary, scheme.primaryContainer),
    NoteBadge.acked => (AppColors.ok, const Color(0xFFDDF3E4)),
    NoteBadge.noAnswer => (AppColors.warn, AppColors.warnSoft),
    NoteBadge.missed => (scheme.error, scheme.errorContainer),
    _ => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
  };
}

String groupTitle(BuildContext context, EventGroup g) {
  final l = AppLocalizations.of(context);
  return switch (g.kind) {
    EventGroupKind.today => l.notesGroupToday(dayText(context, g.day)),
    EventGroupKind.tomorrow => l.notesGroupTomorrow(dayText(context, g.day)),
    EventGroupKind.thisWeek => l.notesGroupThisWeek,
    EventGroupKind.later => l.notesGroupLater,
    EventGroupKind.past => l.notesGroupPast,
  };
}

/// Right side of a note row ("Today", "Yesterday", "Oct 1")
String memoWhen(BuildContext context, Note n, DateTime now) {
  final l = AppLocalizations.of(context);
  final t = n.updated ?? n.created;
  if (t == null) return '';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return l.notesMemoToday;
  if (day == today.subtract(const Duration(days: 1))) return l.notesMemoYesterday;
  return DateFormat.MMMd(_locale(context)).format(t);
}
