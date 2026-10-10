/// Dependency registration (design document Section 3.2).
/// Bloc = Factory, Repository·DataSource·Service = LazySingleton.
/// Exception: app-wide state (SettingsCubit, DevicesCubit) is LazySingleton + BlocProvider.value.
library;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/ble/ble_speaker.dart';
import 'core/device/current_device.dart';
import 'core/network/device_api_client.dart';
import 'core/network/device_token_storage.dart';
import 'core/network/external_http.dart';
import 'core/services/ble_permission_service.dart';
import 'core/services/device_discovery_service.dart';
import 'core/services/device_event_service.dart';
import 'core/settings/settings_cubit.dart';
import 'core/storage/install_state.dart';
import 'core/storage/key_vault.dart';
import 'features/assistant/assistant_feature.dart';
import 'features/audio/audio_feature.dart';
import 'features/devices/data/datasources/devices_local_datasource.dart';
import 'features/english/english_feature.dart';
import 'features/notes/notes_feature.dart';
import 'features/devices/data/repositories/device_control_repository.dart';
import 'features/devices/data/repositories/devices_repository_impl.dart';
import 'features/devices/domain/repositories/devices_repository.dart';
import 'features/devices/presentation/bloc/devices_cubit.dart';
import 'features/devices/presentation/bloc/home_cubit.dart';
import 'features/provisioning/data/repositories/provisioning_repository_impl.dart';
import 'features/provisioning/domain/repositories/provisioning_repository.dart';
import 'features/provisioning/presentation/bloc/provisioning_cubit.dart';
import 'features/radio/radio_feature.dart';
import 'features/system/system_feature.dart';
import 'features/telegram/telegram_feature.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  const secure = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  sl
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<FlutterSecureStorage>(secure)
    ..registerSingleton<InstallState>(InstallState(prefs, secure));
  await sl<InstallState>().init(); // On reinstall, clear the Keychain (before reading tokens)

  // core
  sl
    ..registerLazySingleton<DeviceTokenStorage>(() => DeviceTokenStorage(sl()))
    ..registerLazySingleton<KeyVault>(() => KeyVault(sl()))
    ..registerLazySingleton<DeviceDiscoveryService>(DeviceDiscoveryService.new)
    ..registerLazySingleton<DeviceApiClientFactory>(() => DeviceApiClientFactory(resolver: sl<DeviceDiscoveryService>()))
    ..registerLazySingleton<DeviceEventService>(DeviceEventService.new, dispose: (s) => s.dispose())
    ..registerLazySingleton<CurrentDevice>(() => CurrentDevice(sl(), sl()))
    ..registerLazySingleton<BlePermissionService>(BlePermissionService.new)
    ..registerLazySingleton<BleSpeakerDataSource>(() => BleSpeakerDataSourceImpl(sl()))
    ..registerLazySingleton<Dio>(createExternalHttp, instanceName: 'external')
    ..registerLazySingleton<SettingsCubit>(() => SettingsCubit(sl()));

  // devices
  sl
    ..registerLazySingleton<DevicesLocalDataSource>(() => DevicesLocalDataSource(sl(), sl()))
    ..registerLazySingleton<DevicesRepository>(() => DevicesRepositoryImpl(sl(), sl(), sl()))
    ..registerLazySingleton<DeviceControlRepository>(() => DeviceControlRepository(sl()))
    ..registerLazySingleton<DevicesCubit>(() => DevicesCubit(sl(), sl()))
    ..registerFactory<HomeCubit>(() => HomeCubit(sl(), sl(), sl(), sl()));

  // provisioning
  sl
    ..registerLazySingleton<ProvisioningRepository>(() => ProvisioningRepositoryImpl(sl(), sl(), sl(), sl()))
    ..registerFactory<ProvisioningCubit>(() => ProvisioningCubit(sl(), sl()));

  // feature screens
  registerRadioFeature(sl);
  registerTelegramFeature(sl);
  registerAssistantFeature(sl);
  registerAudioFeature(sl);
  registerSystemFeature(sl);
  registerEnglishFeature(sl);
  registerNotesFeature(sl);
}
