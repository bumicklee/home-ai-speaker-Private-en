import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_keys.dart';
import '../../../../core/errors/failures.dart';
import '../../data/repositories/lesson_repository.dart';
import '../../domain/entities/lesson.dart';

class EnglishState extends Equatable {
  const EnglishState({
    this.options = const LessonOptions(),
    this.starting = false,
    this.started,
    this.failure,
    this.openAiKey,
  });

  final LessonOptions options;
  final bool starting;

  /// The lesson, once it starts successfully (the screen moves on to the lesson screen)
  final Lesson? started;
  final Failure? failure;

  /// Whether the speaker has an OpenAI key. null if unknown (start is not blocked; the speaker blocks it with 409)
  final bool? openAiKey;

  /// Locks the start button once it is confirmed there is no key
  bool get canStart => !starting && openAiKey != false;

  EnglishState copyWith({
    LessonOptions? options,
    bool? starting,
    Lesson? Function()? started,
    Failure? Function()? failure,
    bool? Function()? openAiKey,
  }) =>
      EnglishState(
        options: options ?? this.options,
        starting: starting ?? this.starting,
        started: started != null ? started() : this.started,
        failure: failure != null ? failure() : this.failure,
        openAiKey: openAiKey != null ? openAiKey() : this.openAiKey,
      );

  @override
  List<Object?> get props => [options, starting, started, failure, openAiKey];
}

/// Choosing a course (design "English Tutor: Choose a Course")
class EnglishCubit extends Cubit<EnglishState> {
  EnglishCubit(this._repo) : super(EnglishState(options: _repo.savedOptions()));

  final LessonRepository _repo;

  /// When the screen opens: whether the speaker has an OpenAI key (left unknown if it can't be read)
  Future<void> checkKey() async {
    final r = await _repo.openAiKeySaved();
    if (isClosed) return;
    r.fold((_) {}, (has) => emit(state.copyWith(openAiKey: () => has)));
  }

  void select(LessonOptions options) => emit(state.copyWith(options: options, failure: () => null));

  Future<void> start() async {
    emit(state.copyWith(starting: true, failure: () => null, started: () => null));
    await _repo.saveOptions(state.options);
    final r = await _repo.start(state.options);
    if (isClosed) return;
    r.fold(
      (f) => emit(state.copyWith(
            starting: false,
            failure: () => f,
            // 409 NO_API_KEY: the key was deleted in the meantime → lock start and show a notice
            openAiKey: f.errorKey == ErrorKeys.deviceNoApiKey ? () => false : null,
          )),
      (lesson) => emit(state.copyWith(starting: false, started: () => lesson)),
    );
  }

  /// So it can be pressed again after moving on to the lesson screen
  void consumeStarted() => emit(state.copyWith(started: () => null));
}
