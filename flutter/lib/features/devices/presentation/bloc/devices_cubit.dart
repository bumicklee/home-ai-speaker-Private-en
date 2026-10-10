import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/device.dart';
import '../../domain/repositories/devices_repository.dart';

class DevicesState extends Equatable {
  const DevicesState({this.loaded = false, this.devices = const [], this.selectedId, this.failure, this.locating = false});

  final bool loaded;
  final List<Device> devices;
  final String? selectedId;
  final Failure? failure;

  /// Searching via mDNS for devices whose address is unknown
  final bool locating;

  Device? get selected => devices.where((d) => d.id == selectedId).firstOrNull;

  DevicesState copyWith({
    bool? loaded,
    List<Device>? devices,
    String? Function()? selectedId,
    Failure? Function()? failure,
    bool? locating,
  }) =>
      DevicesState(
        loaded: loaded ?? this.loaded,
        devices: devices ?? this.devices,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        failure: failure != null ? failure() : this.failure,
        locating: locating ?? this.locating,
      );

  @override
  List<Object?> get props => [loaded, devices, selectedId, failure, locating];
}

/// App-wide: list of registered speakers and the selection (design document 3.2 DeviceSelectionCubit). Updates CurrentDevice when the selection changes
class DevicesCubit extends Cubit<DevicesState> {
  DevicesCubit(this._repo, this._current) : super(const DevicesState());

  final DevicesRepository _repo;
  final CurrentDevice _current;

  Future<void> load() async {
    final list = await _repo.devices();
    final selected = await _repo.selectedId();
    list.fold(
      (f) => emit(state.copyWith(loaded: true, failure: () => f)),
      (devices) => emit(state.copyWith(
        loaded: true,
        devices: devices,
        selectedId: () => selected.getOrElse(() => null),
        failure: () => null,
      )),
    );
    await _applySelection();
  }

  Future<void> select(String id) async {
    await _repo.select(id);
    emit(state.copyWith(selectedId: () => id));
    await _applySelection();
  }

  /// Removes it from the phone (unregistering on the speaker side is on the System screen)
  Future<void> remove(String id) async {
    await _repo.remove(id);
    await load();
  }

  /// Finds the address again (connection failed or no address)
  Future<bool> locate() async {
    final device = state.selected;
    if (device == null) return false;
    emit(state.copyWith(locating: true));
    final r = await _repo.rediscover(device);
    emit(state.copyWith(locating: false));
    return r.fold((_) => false, (updated) {
      emit(state.copyWith(devices: [for (final d in state.devices) d.id == updated.id ? updated : d]));
      _applySelection();
      return true;
    });
  }

  Future<void> _applySelection() async {
    final id = state.selectedId;
    if (id == null) {
      _current.select(null);
      return;
    }
    final endpoint = (await _repo.endpoint(id)).getOrElse(() => null);
    _current.select(endpoint, onEndpointChanged: (e) {
      emit(state.copyWith(devices: [
        for (final d in state.devices) d.id == e.deviceId ? d.copyWith(host: () => e.host, port: e.port) : d,
      ]));
    });
    if (endpoint == null && state.selected != null && state.selected!.host == null) {
      await locate();
    }
  }
}
