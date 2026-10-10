import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/services/device_event_service.dart';
import '../../data/repositories/radio_repository.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';

class RadioState extends Equatable {
  const RadioState({
    this.presets = const [],
    this.now = const RadioNow(),
    this.loaded = false,
    this.loading = false,
    this.busy = false,
    this.failure,
    this.invalid,
  });

  final List<RadioPreset> presets;
  final RadioNow now;

  /// Whether presets have been received at least once
  final bool loaded;
  final bool loading;

  /// Play or save request in progress
  final bool busy;

  /// Last load or action failure (the screen shows a snackbar when it changes)
  final Failure? failure;

  /// Validation failure before sending (firmware rules)
  final PresetError? invalid;

  int? get playingIndex => playingPresetIndex(presets, now);

  RadioState copyWith({
    List<RadioPreset>? presets,
    RadioNow? now,
    bool? loaded,
    bool? loading,
    bool? busy,
    Failure? Function()? failure,
    PresetError? Function()? invalid,
  }) =>
      RadioState(
        presets: presets ?? this.presets,
        now: now ?? this.now,
        loaded: loaded ?? this.loaded,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        failure: failure != null ? failure() : this.failure,
        invalid: invalid != null ? invalid() : this.invalid,
      );

  @override
  List<Object?> get props => [presets, now, loaded, loading, busy, failure, invalid];
}

/// Radio screen: presets + now playing (live updates via WS `media_state`)
class RadioCubit extends Cubit<RadioState> {
  RadioCubit(this._repo, this._events) : super(const RadioState()) {
    _sub = _events.on(DeviceEventType.mediaState).listen(_onMedia);
  }

  final RadioRepository _repo;
  final DeviceEventService _events;
  late final StreamSubscription<DeviceEvent> _sub;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: () => null));
    final results = await Future.wait([_repo.presets(), _repo.now()]);
    if (isClosed) return;
    final presets = results[0] as Either<Failure, List<RadioPreset>>;
    final now = results[1] as Either<Failure, RadioNow>;
    Failure? failure;
    var next = state.copyWith(loading: false);
    presets.fold((f) => failure = f, (p) => next = next.copyWith(presets: p, loaded: true));
    now.fold((f) => failure ??= f, (n) => next = next.copyWith(now: n));
    emit(next.copyWith(failure: () => failure));
  }

  Future<void> playPreset(int index) => _act(() => _repo.playPreset(index));

  /// Play a search result right away without saving it
  Future<void> playStation(RadioStation s) =>
      _act(() => _repo.playUrl(s.url, truncateUtf8(s.name, RadioLimits.nameMax)));

  /// Pause if playing or connecting, otherwise play again
  Future<void> togglePause() => media(state.now.canPause ? 'pause' : 'resume');

  /// pause / resume / stop / next / previous. On 409 (not playing), fetch the current state again
  Future<void> media(String action) async {
    final ok = await _act(() => _repo.media(action));
    if (!ok && !isClosed && _isNotPlaying(state.failure)) await refreshNow();
  }

  Future<void> refreshNow() async {
    final r = await _repo.now();
    if (isClosed) return;
    r.fold((_) {}, (n) => emit(state.copyWith(now: n)));
  }

  /// Replace the whole list (save on the edit screen). Validates with the same rules as the firmware before sending
  Future<bool> savePresets(List<RadioPreset> presets) async {
    final invalid = validatePresets(presets);
    if (invalid != null) {
      emit(state.copyWith(invalid: () => invalid, failure: () => null));
      return false;
    }
    emit(state.copyWith(busy: true, failure: () => null, invalid: () => null));
    final r = await _repo.savePresets(presets);
    if (isClosed) return r.isRight();
    return r.fold((f) {
      emit(state.copyWith(busy: false, failure: () => f));
      return false;
    }, (saved) {
      emit(state.copyWith(busy: false, presets: saved, loaded: true));
      return true;
    });
  }

  /// Add at the end (rejected if the same URL already exists)
  Future<bool> addPreset(RadioPreset preset) async {
    if (state.presets.any((p) => p.url == preset.url)) {
      emit(state.copyWith(invalid: () => PresetError.duplicate, failure: () => null));
      return false;
    }
    return savePresets([...state.presets, preset]);
  }

  bool hasUrl(String url) => state.presets.any((p) => p.url == url);

  Future<bool> _act(Future<Either<Failure, Unit>> Function() run) async {
    emit(state.copyWith(busy: true, failure: () => null, invalid: () => null));
    final r = await run();
    if (isClosed) return r.isRight();
    emit(state.copyWith(busy: false, failure: () => r.fold((f) => f, (_) => null)));
    return r.isRight();
  }

  void _onMedia(DeviceEvent e) {
    if (isClosed) return;
    emit(state.copyWith(now: RadioRepository.parseNow(e.data)));
  }

  static bool _isNotPlaying(Failure? f) => f is DeviceFailure && f.code == 'NOT_PLAYING';

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
