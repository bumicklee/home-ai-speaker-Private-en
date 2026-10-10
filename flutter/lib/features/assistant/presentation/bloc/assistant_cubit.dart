import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../data/models/assistant_settings_model.dart';
import '../../data/services/location_service.dart';
import '../../domain/entities/assistant_settings.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../domain/services/place_formatter.dart';

class AssistantState extends Equatable {
  const AssistantState({
    this.original,
    this.draft,
    this.voices = const [],
    this.memoryCount,
    this.loading = false,
    this.saving = false,
    this.locating = false,
    this.failure,
    this.timezone,
  });

  /// Values saved on the device
  final AssistantSettings? original;

  /// Values edited on screen (not saved yet)
  final AssistantSettings? draft;
  final List<String> voices;
  final int? memoryCount;
  final bool loading;
  final bool saving;
  final bool locating;

  /// Load failed (the whole screen shows failure)
  final Failure? failure;

  /// Phone time zone check after "Set to current location". If the speaker doesn't know the time zone, the screen shows candidates
  final TimezoneSuggestion? timezone;

  bool get dirty => original != null && draft != null && original != draft;
  List<AssistantFieldError> get errors => draft?.validate() ?? const [];

  AssistantState copyWith({
    AssistantSettings? original,
    AssistantSettings? draft,
    List<String>? voices,
    int? Function()? memoryCount,
    bool? loading,
    bool? saving,
    bool? locating,
    Failure? Function()? failure,
    TimezoneSuggestion? Function()? timezone,
  }) =>
      AssistantState(
        original: original ?? this.original,
        draft: draft ?? this.draft,
        voices: voices ?? this.voices,
        memoryCount: memoryCount != null ? memoryCount() : this.memoryCount,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        locating: locating ?? this.locating,
        failure: failure != null ? failure() : this.failure,
        timezone: timezone != null ? timezone() : this.timezone,
      );

  @override
  List<Object?> get props => [original, draft, voices, memoryCount, loading, saving, locating, failure, timezone];
}

/// Result of "Set to current location" (the screen picks the message)
enum LocateResult {
  /// Filled in the neighborhood and the phone time zone (known to the speaker)
  filled,

  /// Filled in the neighborhood only. The time zone must be picked from the candidates
  filledTimezoneUnsupported,
  serviceOff,
  denied,
  deniedForever,
  unavailable,
}

/// Assistant settings: load → edit (draft) → save only the changed keys
class AssistantCubit extends Cubit<AssistantState> {
  AssistantCubit(this._repo, this._location) : super(const AssistantState());

  final AssistantRepository _repo;
  final LocationService _location;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: () => null));
    final settings = _repo.settings();
    final voices = _repo.voices();
    final memories = _repo.memories();
    final s = await settings;
    if (isClosed) return;
    await s.fold(
      (f) async => emit(state.copyWith(loading: false, failure: () => f)),
      (v) async {
        // The screen works even without voices or the memory count (voices show only the saved one)
        final names = (await voices).getOrElse(() => const []);
        final count = (await memories).fold((_) => null, (m) => m.length);
        if (isClosed) return;
        emit(AssistantState(original: v, draft: v, voices: names, memoryCount: count));
      },
    );
  }

  /// When returning from the memories screen
  Future<void> refreshMemoryCount() async {
    final r = await _repo.memories();
    if (isClosed) return;
    r.fold((_) {}, (m) => emit(state.copyWith(memoryCount: () => m.length)));
  }

  /// When returning from the AI · Conversation mode screen: re-read only the AI values that screen saved directly (other edits in progress stay)
  Future<void> refreshAi() async {
    final r = await _repo.settings();
    if (isClosed) return;
    r.fold((_) {}, (v) {
      AssistantSettings withAi(AssistantSettings s) =>
          s.copyWith(aiProvider: v.aiProvider, modeOpenai: v.modeOpenai, modeGemini: v.modeGemini);
      final o = state.original;
      final d = state.draft;
      if (o == null || d == null) return;
      emit(state.copyWith(original: withAi(o), draft: withAi(d)));
    });
  }

  void edit(AssistantSettings Function(AssistantSettings) change) {
    final d = state.draft;
    if (d == null) return;
    emit(state.copyWith(draft: change(d)));
  }

  void setTimezone(String iana) {
    edit((d) => d.copyWith(timezone: iana));
    emit(state.copyWith(timezone: () => null));
  }

  /// Discard edits
  void discard() {
    final o = state.original;
    if (o != null) emit(state.copyWith(draft: o, timezone: () => null));
  }

  /// PUT only the changed keys. Nothing is sent if there is nothing to save or a value is invalid. On failure, Failure (edits are kept)
  Future<Failure?> save() async {
    final o = state.original;
    final d = state.draft;
    if (o == null || d == null || state.saving || state.errors.isNotEmpty) return null;
    final changes = AssistantSettingsModel.diff(o, d.copyWith(name: d.name.trim(), location: d.location.trim()));
    if (changes.isEmpty) {
      emit(state.copyWith(draft: o));
      return null;
    }
    emit(state.copyWith(saving: true));
    final r = await _repo.update(changes);
    if (isClosed) return r.fold((f) => f, (_) => null);
    return r.fold((f) {
      emit(state.copyWith(saving: false));
      return f;
    }, (saved) {
      emit(state.copyWith(saving: false, original: saved, draft: saved, timezone: () => null));
      return null;
    });
  }

  /// Phone location → put the neighborhood name (+ time zone) into the draft. The user saves
  Future<LocateResult> locate() async {
    if (state.draft == null || state.locating) return LocateResult.unavailable;
    emit(state.copyWith(locating: true));
    try {
      final place = PlaceFormatter.format(await _location.currentPlace());
      if (place.isEmpty) throw const LocationLookupException(LocationError.unavailable);
      final tz = TimezoneSuggestion.of(await _location.phoneTimezone());
      if (isClosed) return LocateResult.filled;
      final d = state.draft!;
      emit(state.copyWith(
        locating: false,
        draft: d.copyWith(location: place, timezone: tz.supported ? tz.phone : null),
        timezone: () => tz.supported ? null : tz,
      ));
      return tz.supported ? LocateResult.filled : LocateResult.filledTimezoneUnsupported;
    } on LocationLookupException catch (e) {
      if (!isClosed) emit(state.copyWith(locating: false));
      return switch (e.error) {
        LocationError.serviceOff => LocateResult.serviceOff,
        LocationError.denied => LocateResult.denied,
        LocationError.deniedForever => LocateResult.deniedForever,
        LocationError.unavailable => LocateResult.unavailable,
      };
    }
  }

  Future<void> openLocationSettings() => _location.openSettings();
}
