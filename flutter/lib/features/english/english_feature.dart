import 'package:get_it/get_it.dart';

import 'data/repositories/lesson_repository.dart';
import 'presentation/bloc/english_cubit.dart';

export 'presentation/pages/english_page.dart' show EnglishPage;

/// English Tutor (firmware lesson.c, LAN /api/v1/lesson, WS `lesson`)
void registerEnglishFeature(GetIt sl) {
  sl
    ..registerLazySingleton<LessonRepository>(() => LessonRepository(sl(), sl(), sl()))
    ..registerFactory<EnglishCubit>(() => EnglishCubit(sl()));
}
