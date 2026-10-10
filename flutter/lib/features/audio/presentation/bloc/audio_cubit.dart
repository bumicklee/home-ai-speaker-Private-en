import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/services/device_event_service.dart';
import '../../data/repositories/audio_repository.dart';
import '../../domain/entities/audio_settings.dart';

/// Progress of the wake word detection test
class WakeTest extends Equatable {
  const WakeTest({required this.remaining, this.detections = 0});

  /// Seconds left. 0 means finished (show the result)
  final int remaining;
  final int detections;

  bool get running => remaining > 0;

  WakeTest copyWith({int? remaining, int? detections}) =>
      WakeTest(remaining: remaining ?? this.remaining, detections: detections ?? this.detections);

  @override
  List<Object?> get props => [remaining, detections];
}

class AudioState extends Equatable {
  const AudioState({
    this.audio,
    this.wake,
    this.ledBrightness,
    this.loading = false,
    this.failure,
    this.error,
    this.wakeTest,
  });

  final AudioSettings? audio;
  final WakeSettings? wake;
  final int? ledBrightness;
  final bool loading;

  /// Loading failed (the whole screen becomes the failure screen)
  final Failure? failure;

  /// Save or test failed (shown once in a snackbar)
  final ActionError? error;
  final WakeTest? wakeTest;

  bool get loaded => audio != null && wake != null && ledBrightness != null;

  AudioState copyWith({
    AudioSettings? audio,
    WakeSettings? wake,
    int? ledBrightness,
    bool? loading,
    Failure? Function()? failure,
    ActionError? Function()? error,
    WakeTest? Function()? wakeTest,
  }) =>
      AudioState(
        audio: audio ?? this.audio,
        wake: wake ?? this.wake,
        ledBrightness: ledBrightness ?? this.ledBrightness,
        loading: loading ?? this.loading,
        failure: failure != null ? failure() : this.failure,
        error: error != null ? error() : this.error,
        wakeTest: wakeTest != null ? wakeTest() : this.wakeTest,
      );

  @override
  List<Object?> get props => [audio, wake, ledBrightness, loading, failure, error, wakeTest];
}

/// Audio & Wake Word screen: settings groups audio, wake, led + WS `volume` and `wake_test` (design document, Section 3.2)
/// While a slider is dragged, [preview] changes only the screen; on release, only the one changed key is PUT.
/// If saving fails, revert to the values the device last returned.
class AudioCubit extends Cubit<AudioState> {
  AudioCubit(this._repo, this._events, {Duration tick = const Duration(seconds: 1)})
      : _tick = tick,
        super(const AudioState()) {
    _volumeSub = _events.on(DeviceEventType.volume).listen(_onVolume);
    _wakeSub = _events.on(DeviceEventType.wakeTest).listen(_onWakeTest);
  }

  final AudioRepository _repo;
  final DeviceEventService _events;
  final Duration _tick;
  late final StreamSubscription<DeviceEvent> _volumeSub;
  late final StreamSubscription<DeviceEvent> _wakeSub;
  Timer? _timer;

  /// Values the device last confirmed (what to revert to on failure)
  AudioSettings? _audio;
  WakeSettings? _wake;
  int? _led;

  /// Firmware wake.c TEST_MS
  static const wakeTestSeconds = 60;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: () => null));
    final (audio, wake, led) = await (_repo.audio(), _repo.wake(), _repo.ledBrightness()).wait;
    if (isClosed) return;
    Failure? failure;
    audio.fold((f) => failure ??= f, (v) => _audio = v);
    wake.fold((f) => failure ??= f, (v) => _wake = v);
    led.fold((f) => failure ??= f, (v) => _led = v);
    if (failure != null) {
      emit(state.copyWith(loading: false, failure: () => failure));
      return;
    }
    emit(state.copyWith(audio: _audio, wake: _wake, ledBrightness: _led, loading: false));
  }

  /// While a slider is being dragged: change only the screen
  void preview({AudioSettings? audio, WakeSettings? wake, int? ledBrightness}) =>
      emit(state.copyWith(audio: audio, wake: wake, ledBrightness: ledBrightness));

  // ── audio ──

  Future<void> setVolume(int v) => _saveAudio(state.audio!.copyWith(volume: v), {'volume': v});
  Future<void> setDuck(int db) => _saveAudio(state.audio!.copyWith(duckDb: db), {'duck_db': db});
  Future<void> setAutoGain(bool on) => _saveAudio(state.audio!.copyWith(autoGain: on), {'auto_gain': on});

  Future<void> setMicGain(int db) {
    assert(AudioSettings.micGainSteps.contains(db));
    return _saveAudio(state.audio!.copyWith(micGain: db), {'mic_gain': db});
  }

  // ── wake ──

  Future<void> setWakeEnabled(bool on) => _saveWake(state.wake!.copyWith(enabled: on), {'enabled': on});
  Future<void> setPhrase(WakePhrase p) => _saveWake(state.wake!.copyWith(phrase: p), {'phrase': p.value});
  Future<void> setSensitivity(int v) => _saveWake(state.wake!.copyWith(sensitivity: v), {'sensitivity': v});
  Future<void> setWakeGain(int db) => _saveWake(state.wake!.copyWith(gainDb: db), {'gain_db': db});

  // ── led ──

  Future<void> setLedBrightness(int v) async {
    emit(state.copyWith(ledBrightness: v, error: () => null));
    final r = await _repo.setLedBrightness(v);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(ledBrightness: _led, error: () => ActionError(f))),
      (saved) => emit(state.copyWith(ledBrightness: _led = saved)),
    );
  }

  Future<void> testTone() async {
    final r = await _repo.testTone();
    if (isClosed) return;
    r.fold((f) => emit(state.copyWith(error: () => ActionError(f))), (_) {});
  }

  /// 60-second detection test. The count is the number of `wake_test` events
  /// (the event's `detections` is cumulative since boot, not counted from the test start, wake.c)
  Future<void> startWakeTest() async {
    if (state.wakeTest?.running ?? false) return;
    emit(state.copyWith(error: () => null));
    final r = await _repo.startWakeTest();
    if (isClosed) return;
    r.fold((f) => emit(state.copyWith(error: () => ActionError(f))), (_) {
      emit(state.copyWith(wakeTest: () => const WakeTest(remaining: wakeTestSeconds)));
      _timer?.cancel();
      _timer = Timer.periodic(_tick, (_) => _countDown());
    });
  }

  void _countDown() {
    final t = state.wakeTest;
    if (t == null || !t.running) {
      _timer?.cancel();
      return;
    }
    final next = t.remaining - 1;
    if (next <= 0) _timer?.cancel();
    emit(state.copyWith(wakeTest: () => t.copyWith(remaining: next < 0 ? 0 : next)));
  }

  Future<void> _saveAudio(AudioSettings next, Map<String, Object> change) async {
    emit(state.copyWith(audio: next, error: () => null));
    final r = await _repo.updateAudio(change);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(audio: _audio, error: () => ActionError(f))),
      (saved) => emit(state.copyWith(audio: _audio = saved)),
    );
  }

  Future<void> _saveWake(WakeSettings next, Map<String, Object> change) async {
    emit(state.copyWith(wake: next, error: () => null));
    final r = await _repo.updateWake(change);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(wake: _wake, error: () => ActionError(f))),
      (saved) => emit(state.copyWith(wake: _wake = saved)),
    );
  }

  /// When the volume was changed by a button or by voice
  void _onVolume(DeviceEvent e) {
    final v = (e.data['value'] as num?)?.toInt();
    final a = _audio;
    if (v == null || a == null) return;
    _audio = a.copyWith(volume: v);
    emit(state.copyWith(audio: state.audio!.copyWith(volume: v)));
  }

  void _onWakeTest(DeviceEvent e) {
    final t = state.wakeTest;
    if (t == null || !t.running) return;
    // The design document says remaining_s is sent too, but the current firmware sends only detections. Use it if it arrives
    final remaining = (e.data['remaining_s'] as num?)?.toInt();
    emit(state.copyWith(wakeTest: () => t.copyWith(detections: t.detections + 1, remaining: remaining)));
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _volumeSub.cancel();
    await _wakeSub.cancel();
    return super.close();
  }
}

/// A failure shown once. Even if the same Failure repeats, each is a new value, so the listener fires again
class ActionError {
  ActionError(this.failure);
  final Failure failure;
}
