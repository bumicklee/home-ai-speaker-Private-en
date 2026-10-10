/// Audio and wake word feature (route `/audio`). Wires [registerAudioFeature] into injection_container
/// and [AudioPage] into app_router.
library;

import 'package:get_it/get_it.dart';

import 'data/repositories/audio_repository.dart';
import 'presentation/bloc/audio_cubit.dart';

export 'presentation/pages/audio_page.dart' show AudioPage;

void registerAudioFeature(GetIt sl) {
  sl
    ..registerLazySingleton<AudioRepository>(() => AudioRepository(sl()))
    ..registerFactory<AudioCubit>(() => AudioCubit(sl(), sl()));
}
