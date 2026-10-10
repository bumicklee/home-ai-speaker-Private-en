import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../../../core/device/current_device.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../../../core/services/device_event_service.dart';
import '../../domain/entities/note.dart';
import '../datasources/notes_local_store.dart';
import '../datasources/notes_remote_datasource.dart';
import '../models/note_model.dart';

/// Notes and schedule (original = speaker, copy = this phone). Design document docs/design-notes-schedule.md Section 6.2
///
/// Sync: `GET ?since=<copy rev>` → apply the higher rev per id, remove gone from the copy → save to file.
/// If the speaker rev is lower than the copy's (speaker was reset), fetch everything again (since=0) and replace.
class NotesRepository {
  NotesRepository(this._device, this._events, this._remote, this._store);

  final CurrentDevice _device;
  final DeviceEventService _events;
  final NotesRemoteDataSource _remote;
  final NotesLocalStore _store;

  NotesCache _cache = const NotesCache();
  String? _cacheFor;

  static const eventNotes = 'notes';
  static const eventReminder = 'reminder';

  /// The copy on this phone (works without reaching the speaker)
  Future<NotesCache> cached() async {
    final id = _device.deviceId;
    if (id == null) return const NotesCache();
    if (_cacheFor != id) {
      _cache = await _store.read(id);
      _cacheFor = id;
    }
    return _cache;
  }

  Future<Either<Failure, NotesCache>> sync() => guard(() async {
        final base = await cached();
        var j = await _remote.changes(base.rev);
        var full = base.rev == 0;
        if (_rev(j) < base.rev) {
          j = await _remote.changes(0);
          full = true;
        }
        return _save(base.merge(_rev(j), _items(j), replace: full));
      });

  /// If remind is null, the speaker's default reminders
  Future<Either<Failure, NotesCache>> create(NoteDraft draft) => guard(() async {
        final j = await _remote.create(NoteModel.createJson(draft));
        return _apply(NoteModel.fromJson(j));
      });

  /// On 409 CONFLICT, replaces the copy with the latest item from the body and returns a failure (errorDeviceConflict)
  Future<Either<Failure, NotesCache>> update(Note note, NoteDraft draft) => guard(() async {
        try {
          final j = await _remote.update(note.id, NoteModel.updateJson(draft, note.rev));
          return await _apply(NoteModel.fromJson(j));
        } on DeviceApiException catch (e) {
          final latest = e.data?['note'];
          if (e.code == 'CONFLICT' && latest is Map<String, dynamic>) await _apply(NoteModel.fromJson(latest));
          rethrow;
        }
      });

  /// Delete the original on the speaker (cannot be restored)
  Future<Either<Failure, NotesCache>> delete(Note note) => guard(() async {
        final j = await _remote.delete(note.id);
        final rev = _rev(j);
        return _apply(Note(id: note.id, rev: rev > note.rev ? rev : note.rev, state: NoteState.gone));
      });

  Future<Either<Failure, NotesCache>> restore(Note note) => guard(() async {
        final j = await _remote.restore(note.id);
        return _apply(NoteModel.fromJson(j));
      });

  Future<Either<Failure, NotesSettings>> settings() => guard(() async {
        final s = NotesSettingsModel.fromJson(await _remote.settings());
        await _save((await cached()).copyWith(settings: s));
        return s;
      });

  /// Sends only the changed keys
  Future<Either<Failure, NotesSettings>> saveSettings(NotesSettings from, NotesSettings to) => guard(() async {
        final body = NotesSettingsModel.diff(from, to);
        if (body.isEmpty) return to;
        final j = await _remote.saveSettings(body);
        final s = j.isEmpty ? to : NotesSettingsModel.fromJson(j);
        await _save((await cached()).copyWith(settings: s));
        return s;
      });

  /// When to refetch: WS `notes` (rev only, no content), `reminder` (reminder result), event connection (re)opened
  Stream<void> changes() {
    final out = StreamController<void>();
    final subs = <StreamSubscription<Object?>>[];
    out
      ..onListen = () {
        subs
          ..add(_events.events
              .where((e) => e.type == eventNotes || e.type == eventReminder)
              .listen((_) => out.add(null)))
          ..add(_events.connection.where((c) => c == EventConnection.connected).listen((_) => out.add(null)));
      }
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    return out.stream;
  }

  /// Apply one item. Don't raise the copy rev (so other changes in between aren't missed at the next sync)
  Future<NotesCache> _apply(Note n) async {
    final base = await cached();
    return _save(base.merge(base.rev, [n]));
  }

  Future<NotesCache> _save(NotesCache c) async {
    final id = _device.deviceId;
    if (id == null) return c;
    _cache = c;
    _cacheFor = id;
    try {
      await _store.write(id, c);
    } on Exception {
      // Even if the file can't be written, the screen keeps going with the in-memory copy (written again at the next save)
    }
    return c;
  }

  static int _rev(Map<String, dynamic> j) => (j['rev'] as num?)?.toInt() ?? 0;

  static List<Note> _items(Map<String, dynamic> j) => [
        for (final i in (j['items'] as List<dynamic>? ?? const []))
          if (i is Map<String, dynamic>) NoteModel.fromJson(i),
      ].where((n) => n.id.isNotEmpty).toList();
}
