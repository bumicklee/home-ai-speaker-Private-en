import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_keys.dart';
import '../../../../core/errors/failures.dart';
import '../../data/repositories/notes_repository.dart';
import '../../domain/entities/note.dart';

class NotesState extends Equatable {
  const NotesState({
    this.items = const [],
    this.rev = 0,
    this.settings = const NotesSettings(),
    this.loaded = false,
    this.syncing = false,
    this.offline = false,
    this.busy = false,
    this.query = '',
    this.failure,
  });

  /// The whole copy (active and trash)
  final List<Note> items;
  final int rev;
  final NotesSettings settings;

  /// Has the copy been read at least once
  final bool loaded;
  final bool syncing;

  /// Can't reach the speaker → the copy is read-only
  final bool offline;

  /// Saving or deleting
  final bool busy;
  final String query;
  final Failure? failure;

  bool get readOnly => offline;

  Note? byId(String id) => items.where((n) => n.id == id).firstOrNull;

  NotesState copyWith({
    List<Note>? items,
    int? rev,
    NotesSettings? settings,
    bool? loaded,
    bool? syncing,
    bool? offline,
    bool? busy,
    String? query,
    Failure? Function()? failure,
  }) =>
      NotesState(
        items: items ?? this.items,
        rev: rev ?? this.rev,
        settings: settings ?? this.settings,
        loaded: loaded ?? this.loaded,
        syncing: syncing ?? this.syncing,
        offline: offline ?? this.offline,
        busy: busy ?? this.busy,
        query: query ?? this.query,
        failure: failure != null ? failure() : this.failure,
      );

  @override
  List<Object?> get props => [items, rev, settings, loaded, syncing, offline, busy, query, failure];
}

/// Notes and schedule list, editing and reminder settings (shared by three screens)
class NotesCubit extends Cubit<NotesState> {
  NotesCubit(this._repo) : super(const NotesState()) {
    _sub = _repo.changes().listen((_) => sync());
  }

  final NotesRepository _repo;
  late final StreamSubscription<void> _sub;

  /// Show the copy first, then sync with the speaker. Syncing also fetches the reminder settings
  Future<void> load() async {
    final c = await _repo.cached();
    if (isClosed) return;
    emit(_withCache(state.copyWith(loaded: true), c));
    if (await sync()) {
      final s = await _repo.settings();
      if (isClosed) return;
      s.fold((_) {}, (v) => emit(state.copyWith(settings: v)));
    }
  }

  /// true on success
  Future<bool> sync() async {
    if (isClosed) return false;
    emit(state.copyWith(syncing: true));
    final r = await _repo.sync();
    if (isClosed) return false;
    return r.fold(
      (f) {
        final offline = _isOffline(f);
        emit(state.copyWith(syncing: false, offline: offline, failure: () => offline ? null : f));
        return false;
      },
      (c) {
        emit(_withCache(state.copyWith(syncing: false, offline: false, failure: () => null), c));
        return true;
      },
    );
  }

  void setQuery(String q) => emit(state.copyWith(query: q));

  /// Create new ([original] == null) or edit. true on success.
  /// On 409 CONFLICT, the copy is replaced with the speaker's latest item and failure.code == 'CONFLICT'
  Future<bool> save(Note? original, NoteDraft draft) =>
      _mutate(() => original == null ? _repo.create(draft) : _repo.update(original, draft));

  /// Deletes the original on the speaker too
  Future<bool> delete(Note note) => _mutate(() => _repo.delete(note));

  Future<bool> restore(Note note) => _mutate(() => _repo.restore(note));

  /// Show the change right away and save. Revert on failure
  Future<bool> saveSettings(NotesSettings next) async {
    final before = state.settings;
    if (next == before) return true;
    emit(state.copyWith(settings: next, failure: () => null));
    final r = await _repo.saveSettings(before, next);
    if (isClosed) return false;
    return r.fold(
      (f) {
        emit(state.copyWith(settings: before, failure: () => f, offline: state.offline || _isOffline(f)));
        return false;
      },
      (s) {
        emit(state.copyWith(settings: s));
        return true;
      },
    );
  }

  Future<bool> _mutate(Future<Either<Failure, NotesCache>> Function() run) async {
    emit(state.copyWith(busy: true, failure: () => null));
    final r = await run();
    if (isClosed) return false;
    final failure = r.fold<Failure?>((f) => f, (_) => null);
    if (failure == null) {
      emit(_withCache(state.copyWith(busy: false), r.getOrElse(() => const NotesCache())));
      return true;
    }
    // On conflict, the repository already replaced the copy with the latest
    final c = await _repo.cached();
    if (isClosed) return false;
    emit(_withCache(
        state.copyWith(busy: false, failure: () => failure, offline: state.offline || _isOffline(failure)), c));
    if (failure.code == 'NOT_FOUND') unawaited(sync()); // deleted elsewhere
    return false;
  }

  NotesState _withCache(NotesState s, NotesCache c) =>
      s.copyWith(items: c.items, rev: c.rev, settings: c.settings ?? s.settings);

  static bool _isOffline(Failure f) => f is NetworkFailure || f.errorKey == ErrorKeys.deviceTimeout;

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
