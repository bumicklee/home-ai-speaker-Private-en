/// System feature (design document, Sections 2.13–2.14): device info, registered phones, restart, key management, app settings.
/// `injection_container.dart` calls registerSystemFeature(sl), and the `/system` route goes to SystemPage.
library;

import 'package:get_it/get_it.dart';

import 'data/repositories/system_repository_impl.dart';
import 'domain/repositories/system_repository.dart';
import 'presentation/bloc/keys_cubit.dart';
import 'presentation/bloc/system_cubit.dart';

export 'presentation/pages/app_settings_page.dart' show AppSettingsPage;
export 'presentation/pages/keys_page.dart' show KeysPage;
export 'presentation/pages/system_page.dart' show SystemPage;

/// Requires: CurrentDevice, BleSpeakerDataSource, KeyVault (registered in core)
void registerSystemFeature(GetIt sl) {
  sl
    ..registerLazySingleton<SystemRepository>(() => SystemRepositoryImpl(sl(), sl()))
    ..registerFactory<SystemCubit>(() => SystemCubit(sl()))
    ..registerFactory<KeysCubit>(() => KeysCubit(sl(), sl()));
}
