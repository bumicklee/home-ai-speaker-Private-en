/// Assistant feature entry point. `injection_container.dart` calls [registerAssistantFeature],
/// and `app_router.dart` connects `AppRoutes.assistant` to [AssistantPage].
library;

import 'package:get_it/get_it.dart';

import 'data/datasources/assistant_local_api_datasource.dart';
import 'data/repositories/assistant_repository_impl.dart';
import 'data/services/location_service.dart';
import 'domain/repositories/assistant_repository.dart';
import 'presentation/bloc/ai_mode_cubit.dart';
import 'presentation/bloc/assistant_cubit.dart';
import 'presentation/bloc/memories_cubit.dart';

export 'presentation/pages/ai_mode_page.dart' show AiModePage;
export 'presentation/pages/assistant_page.dart' show AssistantPage;
export 'presentation/pages/memories_page.dart' show MemoriesPage;

void registerAssistantFeature(GetIt sl) {
  sl
    ..registerLazySingleton<AssistantLocalApiDataSource>(() => AssistantLocalApiDataSource(sl()))
    ..registerLazySingleton<AssistantRepository>(() => AssistantRepositoryImpl(sl()))
    ..registerLazySingleton<LocationService>(DeviceLocationService.new)
    ..registerFactory<AssistantCubit>(() => AssistantCubit(sl(), sl()))
    // SystemRepository (key status, sending keys over BLE) is registered by registerSystemFeature; KeyVault is registered in core
    ..registerFactory<AiModeCubit>(() => AiModeCubit(sl(), sl(), sl()))
    ..registerFactory<MemoriesCubit>(() => MemoriesCubit(sl()));
}
