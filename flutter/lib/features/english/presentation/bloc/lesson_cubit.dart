import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../data/repositories/lesson_repository.dart';
import '../../domain/entities/lesson.dart';

class LessonState extends Equatable {
  const LessonState({this.lesson, this.failure, this.busy = false});

  final Lesson? lesson;
  final Failure? failure;
  final bool busy;

  LessonState copyWith({Lesson? lesson, Failure? Function()? failure, bool? busy}) =>
      LessonState(lesson: lesson ?? this.lesson, failure: failure != null ? failure() : this.failure, busy: busy ?? this.busy);

  @override
  List<Object?> get props => [lesson, failure, busy];
}

/// Lesson and summary screens: updated by WS `lesson`; the screen counts down the time left every second
class LessonCubit extends Cubit<LessonState> {
  LessonCubit(this._repo, {Lesson? initial, Duration tick = const Duration(seconds: 1)})
      : super(LessonState(lesson: initial)) {
    _sub = _repo.updates().listen((l) {
      if (!isClosed) emit(state.copyWith(lesson: l));
    });
    _timer = Timer.periodic(tick, (_) => _countDown(tick));
  }

  final LessonRepository _repo;
  late final StreamSubscription<Lesson> _sub;
  late final Timer _timer;

  Future<void> refresh() async {
    final r = await _repo.current();
    if (isClosed) return;
    r.fold((f) => emit(state.copyWith(failure: () => f)), (l) => emit(state.copyWith(lesson: l, failure: () => null)));
  }

  Future<void> changeTopic() => _act(_repo.changeTopic);

  Future<void> stop() => _act(_repo.stop);

  Future<void> _act(Future<Either<Failure, Unit>> Function() run) async {
    emit(state.copyWith(busy: true));
    final r = await run();
    if (isClosed) return;
    emit(state.copyWith(busy: false, failure: () => r.fold((f) => f, (_) => null)));
  }

  void _countDown(Duration tick) {
    final l = state.lesson;
    final left = l?.remaining;
    if (isClosed || l == null || !l.isActive || left == null || left <= Duration.zero) return;
    final next = left - tick;
    emit(state.copyWith(lesson: l.copyWith(remaining: next < Duration.zero ? Duration.zero : next)));
  }

  @override
  Future<void> close() async {
    _timer.cancel();
    await _sub.cancel();
    return super.close();
  }
}
