import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings: theme and language (the led-app way). The default language is the system language, or ko if it isn't supported.
class SettingsState extends Equatable {
  const SettingsState({this.themeMode = ThemeMode.system, this.locale});

  final ThemeMode themeMode;

  /// null = system language
  final Locale? locale;

  SettingsState copyWith({ThemeMode? themeMode, Locale? Function()? locale}) =>
      SettingsState(themeMode: themeMode ?? this.themeMode, locale: locale != null ? locale() : this.locale);

  @override
  List<Object?> get props => [themeMode, locale];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;
  static const _themeKey = 'theme_mode';
  static const _localeKey = 'locale';
  static const supportedLanguages = ['ko', 'en'];

  static SettingsState _load(SharedPreferences p) {
    final theme = ThemeMode.values.asNameMap()[p.getString(_themeKey)] ?? ThemeMode.system;
    final lang = p.getString(_localeKey);
    return SettingsState(themeMode: theme, locale: supportedLanguages.contains(lang) ? Locale(lang!) : null);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    emit(state.copyWith(themeMode: mode));
  }

  /// null = system language
  Future<void> setLanguage(String? languageCode) async {
    if (languageCode == null) {
      await _prefs.remove(_localeKey);
      emit(state.copyWith(locale: () => null));
    } else if (supportedLanguages.contains(languageCode)) {
      await _prefs.setString(_localeKey, languageCode);
      emit(state.copyWith(locale: () => Locale(languageCode)));
    }
  }

  /// If the system language isn't in the supported list, use ko
  static Locale resolve(Locale? device, Iterable<Locale> supported) {
    for (final l in supported) {
      if (l.languageCode == device?.languageCode) return l;
    }
    return const Locale('ko');
  }
}
