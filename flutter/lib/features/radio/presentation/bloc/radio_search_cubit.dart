import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../data/repositories/radio_repository.dart';
import '../../domain/entities/radio_preset.dart';

class RadioSearchState extends Equatable {
  const RadioSearchState({this.byTag = false, this.query = '', this.results, this.loading = false, this.failure});

  /// Search by genre tag (otherwise by name)
  final bool byTag;
  final String query;

  /// null = not searched yet
  final List<RadioStation>? results;
  final bool loading;
  final Failure? failure;

  RadioSearchState copyWith({
    bool? byTag,
    String? query,
    List<RadioStation>? Function()? results,
    bool? loading,
    Failure? Function()? failure,
  }) =>
      RadioSearchState(
        byTag: byTag ?? this.byTag,
        query: query ?? this.query,
        results: results != null ? results() : this.results,
        loading: loading ?? this.loading,
        failure: failure != null ? failure() : this.failure,
      );

  @override
  List<Object?> get props => [byTag, query, results, loading, failure];
}

/// Station search (Radio-Browser). Shows only what the speaker can play
class RadioSearchCubit extends Cubit<RadioSearchState> {
  RadioSearchCubit(this._repo) : super(const RadioSearchState());

  final RadioRepository _repo;

  void setByTag(bool byTag) {
    if (byTag == state.byTag) return;
    emit(state.copyWith(byTag: byTag));
    if (state.query.isNotEmpty) search(state.query);
  }

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final byTag = state.byTag;
    emit(state.copyWith(query: q, loading: true, failure: () => null));
    final r = await _repo.search(q, byTag: byTag);
    // Drop results of an earlier search that arrive late
    if (isClosed || state.query != q || state.byTag != byTag) return;
    r.fold(
      (f) => emit(state.copyWith(loading: false, failure: () => f, results: () => null)),
      (list) => emit(state.copyWith(loading: false, results: () => list)),
    );
  }
}
