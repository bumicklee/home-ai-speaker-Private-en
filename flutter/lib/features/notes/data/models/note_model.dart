import '../../domain/entities/note.dart';

/// Firmware notes JSON ↔ Note. Unknown values and missing fields get defaults (gone comes with only id, rev, state)
class NoteModel {
  static Note fromJson(Map<String, dynamic> j) {
    final alert = j['alert'];
    final status = alert is Map ? AlertStatus.fromId(alert['status'] as String?) : null;
    return Note(
      id: j['id'] as String? ?? '',
      kind: NoteKind.fromId(j['kind'] as String?),
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      start: NoteTime.tryParse(j['start']),
      end: NoteTime.tryParse(j['end']),
      remind: _ints(j['remind']),
      reminded: _ints(j['reminded']),
      missed: _ints(j['missed']),
      snoozeAt: _time(j['snooze_at']),
      alert: alert is Map && status != null
          ? NoteAlert(offset: (alert['offset'] as num?)?.toInt() ?? 0, status: status, at: _time(alert['at']))
          : null,
      created: _time(j['created']),
      updated: _time(j['updated']),
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      by: j['by'] as String? ?? '',
      state: NoteState.fromId(j['state'] as String?),
    );
  }

  /// Shape written to the copy file (same keys as the firmware)
  static Map<String, dynamic> toJson(Note n) => {
        'id': n.id,
        'kind': n.kind.id,
        'title': n.title,
        'body': n.body,
        'start': n.start?.format(),
        'end': n.end?.format(),
        'remind': n.remind,
        'reminded': n.reminded,
        'missed': n.missed,
        'snooze_at': _unix(n.snoozeAt),
        'alert': n.alert == null
            ? null
            : {'offset': n.alert!.offset, 'status': n.alert!.status.id, 'at': _unix(n.alert!.at)},
        'created': _unix(n.created),
        'updated': _unix(n.updated),
        'rev': n.rev,
        'by': n.by,
        'state': n.state.id,
      };

  /// POST body. If remind is null, leave it out so the speaker's default reminders are used
  static Map<String, dynamic> createJson(NoteDraft d) => {
        'kind': d.kind.id,
        'title': d.title,
        'body': d.body,
        if (d.kind == NoteKind.event) 'start': d.start?.format(),
        if (d.kind == NoteKind.event) 'end': d.end?.format(),
        if (d.remind != null) 'remind': d.kind == NoteKind.event ? d.remind : <int>[],
      };

  /// PUT body. base_rev = the rev of the item the app saw (409 CONFLICT if it changed in between)
  static Map<String, dynamic> updateJson(NoteDraft d, int baseRev) {
    final event = d.kind == NoteKind.event;
    return {
      'base_rev': baseRev,
      'kind': d.kind.id,
      'title': d.title,
      'body': d.body,
      'start': event ? d.start?.format() : null,
      'end': event ? d.end?.format() : null,
      if (d.remind != null || !event) 'remind': event ? d.remind : <int>[],
    };
  }

  static List<int> _ints(Object? v) => [
        if (v is List)
          for (final x in v)
            if (x is num) x.toInt(),
      ];

  static DateTime? _time(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

  static int? _unix(DateTime? t) => t == null ? null : t.millisecondsSinceEpoch ~/ 1000;
}

class NotesSettingsModel {
  static NotesSettings fromJson(Map<String, dynamic> j) {
    const d = NotesSettings();
    List<int> list(Object? v, List<int> fallback) =>
        v is List ? [for (final x in v) if (x is num) x.toInt()] : fallback;
    return NotesSettings(
      enabled: j['enabled'] as bool? ?? d.enabled,
      defaultRemind: list(j['default_remind'], d.defaultRemind),
      defaultRemindAllDay: list(j['default_remind_all_day'], d.defaultRemindAllDay),
      allDayTime: ClockTime.parse(j['all_day_time']),
    );
  }

  static Map<String, dynamic> toJson(NotesSettings s) => {
        'enabled': s.enabled,
        'default_remind': s.defaultRemind,
        'default_remind_all_day': s.defaultRemindAllDay,
        'all_day_time': s.allDayTime.format(),
      };

  /// PUT may send only some fields: just the changed keys
  static Map<String, dynamic> diff(NotesSettings from, NotesSettings to) {
    final a = toJson(from), b = toJson(to);
    return {
      for (final k in b.keys)
        if (a[k].toString() != b[k].toString()) k: b[k],
    };
  }
}

class NotesCacheModel {
  static NotesCache fromJson(Map<String, dynamic> j) {
    final settings = j['settings'];
    return NotesCache(
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      items: [
        for (final i in (j['items'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) NoteModel.fromJson(i),
      ].where((n) => n.id.isNotEmpty && !n.isGone).toList(),
      settings: settings is Map<String, dynamic> ? NotesSettingsModel.fromJson(settings) : null,
    );
  }

  static Map<String, dynamic> toJson(NotesCache c) => {
        'rev': c.rev,
        'items': [for (final n in c.items) NoteModel.toJson(n)],
        if (c.settings != null) 'settings': NotesSettingsModel.toJson(c.settings!),
      };
}
