import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/settings/settings_cubit.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../l10n/app_localizations.dart';

/// App settings (this phone): theme mode, language. Uses the app-wide SettingsCubit
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sysAppTitle)),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, s) {
          final settings = context.read<SettingsCubit>();
          final themes = [
            (ThemeMode.system, l.settingsThemeSystem),
            (ThemeMode.light, l.settingsThemeLight),
            (ThemeMode.dark, l.settingsThemeDark),
          ];
          final languages = [
            (null, l.sysLanguageSystem),
            ('ko', l.sysLanguageKo),
            ('en', l.sysLanguageEn),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SectionTitle(l.settingsTheme),
              ListGroup(children: [
                for (final (mode, label) in themes)
                  _ChoiceRow(
                    label: label,
                    selected: s.themeMode == mode,
                    onTap: () => settings.setThemeMode(mode),
                  ),
              ]),
              const SizedBox(height: 16),
              SectionTitle(l.settingsLanguage),
              ListGroup(children: [
                for (final (code, label) in languages)
                  _ChoiceRow(
                    label: label,
                    selected: s.locale?.languageCode == code,
                    onTap: () => settings.setLanguage(code),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(l.sysAppHint, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Single-choice row (checked when selected)
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: ListRow(
          title: label,
          selected: selected,
          onTap: onTap,
          trailing: selected
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary),
                )
              : null,
        ),
      );
}
