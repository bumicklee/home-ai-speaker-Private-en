import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every ErrorKeys key must be in both ARBs (otherwise the screen shows only errorUnknown)
void main() {
  test('ErrorKeys ↔ ARB', () {
    final source = File('lib/core/errors/error_keys.dart').readAsStringSync();
    final keys = RegExp(r"static const \w+ = '(error\w+)';").allMatches(source).map((m) => m[1]!).toSet();
    expect(keys, isNotEmpty);
    for (final lang in ['ko', 'en']) {
      final arb = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
      expect(keys.difference(arb.keys.toSet()), isEmpty, reason: 'app_$lang.arb에 없는 키');
    }
  });

  test('ko·en ARB 키가 같다', () {
    Set<String> keysOf(String lang) =>
        (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>).keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(keysOf('ko'), keysOf('en'));
  });
}
