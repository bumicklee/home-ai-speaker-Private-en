/// Radio feature (`/radio`). injection_container uses [registerRadioFeature]; the router uses [RadioPage]
library;

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import 'data/datasources/radio_browser_datasource.dart';
import 'data/repositories/radio_repository.dart';
import 'presentation/bloc/radio_cubit.dart';
import 'presentation/bloc/radio_search_cubit.dart';

export 'presentation/pages/radio_page.dart' show RadioPage;

void registerRadioFeature(GetIt sl) {
  sl
    ..registerLazySingleton<RadioBrowserDataSource>(() => RadioBrowserDataSource(sl<Dio>(instanceName: 'external')))
    ..registerLazySingleton<RadioRepository>(() => RadioRepository(sl(), sl()))
    ..registerFactory<RadioCubit>(() => RadioCubit(sl(), sl()))
    ..registerFactory<RadioSearchCubit>(() => RadioSearchCubit(sl()));
}
