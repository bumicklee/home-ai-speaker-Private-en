import 'package:aispeaker/core/settings/settings_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('defaults: system theme, system language', () {
    expect(SettingsCubit(prefs).state, const SettingsState());
  });

  blocTest<SettingsCubit, SettingsState>(
    'changes and saves theme and language',
    build: () => SettingsCubit(prefs),
    act: (c) async {
      await c.setThemeMode(ThemeMode.dark);
      await c.setLanguage('en');
      await c.setLanguage('fr'); // not supported → ignored
      await c.setLanguage(null);
    },
    expect: () => const [
      SettingsState(themeMode: ThemeMode.dark),
      SettingsState(themeMode: ThemeMode.dark, locale: Locale('en')),
      SettingsState(themeMode: ThemeMode.dark),
    ],
    verify: (_) {
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getString('locale'), isNull);
    },
  );

  test('loads saved values', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light', 'locale': 'en'});
    final c = SettingsCubit(await SharedPreferences.getInstance());
    expect(c.state, const SettingsState(themeMode: ThemeMode.light, locale: Locale('en')));
  });

  test('unsupported system language falls back to ko', () {
    const supported = [Locale('en'), Locale('ko')];
    expect(SettingsCubit.resolve(const Locale('ja'), supported), const Locale('ko'));
    expect(SettingsCubit.resolve(const Locale('en', 'US'), supported), const Locale('en'));
  });
}
