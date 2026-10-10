import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/device_event_service.dart';
import '../../data/models/device_status_model.dart';
import '../../data/repositories/device_control_repository.dart';
import '../../domain/entities/device_status.dart';
import '../../domain/repositories/devices_repository.dart';

class HomeState extends Equatable {
  const HomeState({this.status, this.loading = false, this.failure, this.busy = false});

  final DeviceStatus? status;
  final bool loading;

  /// Last load or action failure. If DeviceFailure.isUnauthorized, prompt to register again
  final Failure? failure;
  final bool busy;

  bool get unauthorized => failure is DeviceFailure && (failure as DeviceFailure).isUnauthorized;

  HomeState copyWith({DeviceStatus? Function()? status, bool? loading, Failure? Function()? failure, bool? busy}) =>
      HomeState(
        status: status != null ? status() : this.status,
        loading: loading ?? this.loading,
        failure: failure != null ? failure() : this.failure,
        busy: busy ?? this.busy,
      );

  @override
  List<Object?> get props => [status, loading, failure, busy];
}

/// Home: the selected speaker's /status + real-time events (design document 3.2: voice_state, media_state, volume, tg_message)
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._devices, this._control, this._current, this._events) : super(const HomeState()) {
    _sub = _events.events.listen(_onEvent);
    _current.addListener(_onDeviceChanged);
  }

  final DevicesRepository _devices;
  final DeviceControlRepository _control;
  final CurrentDevice _current;
  final DeviceEventService _events;
  late final StreamSubscription<DeviceEvent> _sub;
  String? _deviceId;

  Future<void> refresh() async {
    final endpoint = _current.endpoint;
    _deviceId = endpoint?.deviceId;
    if (endpoint == null) {
      emit(const HomeState());
      return;
    }
    emit(state.copyWith(loading: true));
    final r = await _devices.status(endpoint);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(loading: false, failure: () => f)),
      (s) => emit(HomeState(status: s)),
    );
  }

  Future<void> toggleVoice() async {
    final talking = state.status?.isTalking ?? false;
    await _act(() => talking ? _control.stopVoice() : _control.startVoice());
  }

  Future<void> media(String action) => _act(() => _control.media(action));

  /// When the slider is released. Update the screen first; reload if it fails
  Future<void> setVolume(int volume) async {
    final s = state.status;
    if (s != null) emit(state.copyWith(status: () => s.copyWith(volume: volume)));
    final r = await _control.setVolume(volume);
    r.fold((f) {
      emit(state.copyWith(failure: () => f));
      refresh();
    }, (_) {});
  }

  Future<void> _act(Future<Either<Failure, Unit>> Function() run) async {
    emit(state.copyWith(busy: true));
    final r = await run();
    if (isClosed) return;
    emit(state.copyWith(busy: false, failure: () => r.fold((f) => f, (_) => null)));
  }

  void _onEvent(DeviceEvent e) {
    final s = state.status;
    if (s == null) return;
    switch (e.type) {
      case DeviceEventType.voiceState:
        emit(state.copyWith(status: () => s.copyWith(voiceState: e.data['state'] as String? ?? 'idle')));
      case DeviceEventType.volume:
        emit(state.copyWith(status: () => s.copyWith(volume: (e.data['value'] as num?)?.toInt() ?? s.volume)));
      case DeviceEventType.mediaState:
        emit(state.copyWith(status: () => s.copyWith(media: DeviceStatusModel.mediaFromJson(e.data))));
      case DeviceEventType.tgMessage:
        emit(state.copyWith(status: () => s.copyWith(telegramUnread: (e.data['unread'] as num?)?.toInt() ?? 0)));
      case DeviceEventType.tgStatus:
        emit(state.copyWith(status: () => s.copyWith(telegramState: e.data['state'] as String? ?? s.telegramState)));
    }
  }

  void _onDeviceChanged() {
    if (_current.deviceId != _deviceId) refresh();
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    _current.removeListener(_onDeviceChanged);
    return super.close();
  }
}
