import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app_router.dart';
import 'app/routes.dart';
import 'core/settings/settings_cubit.dart';
import 'core/theme/app_theme.dart';
import 'features/devices/presentation/bloc/devices_cubit.dart';
import 'injection_container.dart';
import 'l10n/app_localizations.dart';

/// App root. Only app-wide state (settings, device selection) is provided here; feature BLoCs are created per page
/// (led-app created everything at the root, and app.dart grew to 1,172 lines).
class AiSpeakerApp extends StatelessWidget {
  const AiSpeakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<SettingsCubit>()),
        BlocProvider.value(value: sl<DevicesCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          locale: settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (device, supported) => SettingsCubit.resolve(device, supported),
          initialRoute: AppRoutes.home,
          onGenerateRoute: onGenerateRoute,
        ),
      ),
    );
  }
}
