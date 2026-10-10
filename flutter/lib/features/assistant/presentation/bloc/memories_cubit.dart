import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/assistant_settings.dart';
import '../../domain/repositories/assistant_repository.dart';

class MemoriesState extends Equatable {
  const MemoriesState({this.memories, this.loading = false, this.failure, this.deleting = const {}});

  /// null = not loaded yet
  final List<AssistantMemory>? memories;
  final bool loading;
  final Failure? failure;

  /// Key being deleted
  final Set<String> deleting;

  @override
  List<Object?> get props => [memories, loading, failure, deleting];
}

/// Assistant memory list and deletion
class MemoriesCubit extends Cubit<MemoriesState> {
  MemoriesCubit(this._repo) : super(const MemoriesState());

  final AssistantRepository _repo;

  Future<void> load() async {
    emit(MemoriesState(memories: state.memories, loading: true));
    final r = await _repo.memories();
    if (isClosed) return;
    r.fold(
      (f) => emit(MemoriesState(memories: state.memories, failure: f)),
      (m) => emit(MemoriesState(memories: m)),
    );
  }

  /// On success, removes it from the list. On failure, Failure
  Future<Failure?> forget(String key) async {
    emit(MemoriesState(memories: state.memories, deleting: {...state.deleting, key}));
    final r = await _repo.forget(key);
    if (isClosed) return r.fold((f) => f, (_) => null);
    final left = {...state.deleting}..remove(key);
    return r.fold((f) {
      emit(MemoriesState(memories: state.memories, deleting: left));
      return f;
    }, (_) {
      emit(MemoriesState(memories: [...?state.memories?.where((m) => m.key != key)], deleting: left));
      return null;
    });
  }
}
