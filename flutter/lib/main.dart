import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app.dart';
import 'features/devices/presentation/bloc/devices_cubit.dart';
import 'injection_container.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the native splash (design "Splash") until the device list is read → no flash of an empty loading screen
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  await initDependencies();
  sl<DevicesCubit>().load().whenComplete(FlutterNativeSplash.remove);
  runApp(const AiSpeakerApp());
}
