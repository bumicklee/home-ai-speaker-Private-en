import 'package:flutter/material.dart';

import '../features/assistant/assistant_feature.dart';
import '../features/audio/audio_feature.dart';
import '../features/english/english_feature.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/notes/notes_feature.dart';
import '../features/provisioning/presentation/pages/provisioning_page.dart';
import '../features/radio/radio_feature.dart';
import '../features/system/system_feature.dart';
import '../features/telegram/telegram_feature.dart';
import '../l10n/app_localizations.dart';
import 'routes.dart';

/// Route → screen
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final Widget page = switch (settings.name) {
    AppRoutes.home => const HomePage(),
    AppRoutes.provisioning => const ProvisioningPage(),
    AppRoutes.radio => const RadioPage(),
    AppRoutes.telegram => const TelegramPage(),
    AppRoutes.assistant => const AssistantPage(),
    AppRoutes.aiMode => const AiModePage(),
    AppRoutes.audio => const AudioPage(),
    AppRoutes.system => const SystemPage(),
    AppRoutes.english => const EnglishPage(),
    AppRoutes.notes => const NotesPage(),
    _ => const _ComingSoonPage(),
  };
  return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(AppLocalizations.of(context).homeComingSoon)),
      );
}
