import 'package:aispeaker/core/ai/ai_choice.dart';
import 'package:aispeaker/features/devices/data/models/device_status_model.dart';
import 'package:aispeaker/features/system/data/models/system_status_model.dart';
import 'package:aispeaker/features/system/domain/entities/system_status.dart';
import 'package:aispeaker/features/system/presentation/system_format.dart';
import 'package:aispeaker/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exactly the shape of the firmware device_status()
const statusJson = <String, dynamic>{
  'fw': '0.5.0',
  'build_date': 'Oct  3 2026 10:12:00',
  'protocol_version': 1,
  'uptime_s': 11520,
  'reset_reason': 1,
  'wifi_rssi': -51,
  'heap_internal_free': 81920,
  'heap_internal_min': 40960,
  'psram_free': 4194304,
  'voice_state': 'idle',
  'media': {'source': 'none', 'state': 'stopped'},
  'volume': 40,
  'secrets': {'openai_key': true, 'tg_bot_token': false, 'spotify': false, 'stock_key': false},
  'telegram': {'state': 'off', 'unread': 0},
  'spotify_state': 'off',
  'failures': [],
};

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('/status parsing', () {
    final s = SystemStatusModel.fromJson(statusJson);
    expect(s.firmware, '0.5.0');
    expect(s.buildDate, 'Oct  3 2026 10:12:00');
    expect(s.uptime, const Duration(hours: 3, minutes: 12));
    expect(s.wifiRssi, -51);
    expect(s.resetCause, ResetCause.powerOn);
    expect(s.heapInternalFree, 81920);
    expect(s.heapInternalMin, 40960);
    expect(s.hasSecret('openai_key'), isTrue);
    expect(s.hasSecret('tg_bot_token'), isFalse);
    expect(s.failures, isEmpty);
  });

  test('wifi_rssi null (not connected) and missing fields', () {
    final s = SystemStatusModel.fromJson(const {'fw': '0.5.0', 'wifi_rssi': null, 'failures': ['ota fail', {'c': 1}]});
    expect(s.wifiRssi, isNull);
    expect(s.wifiBand, isNull);
    expect(s.uptime, Duration.zero);
    expect(s.failures, ['ota fail', '{"c":1}']);
    expect(formatWifi(en, null), 'Not connected');
  });

  test('uptime text', () {
    expect(formatUptime(en, const Duration(hours: 3, minutes: 12, seconds: 40)), '3 h 12 min');
    expect(formatUptime(en, const Duration(minutes: 7)), '7 min');
    expect(formatUptime(en, const Duration(seconds: 20)), '0 min');
    expect(formatUptime(en, const Duration(days: 2, hours: 5, minutes: 30)), '2 d 5 h');
  });

  test('Wi-Fi signal bands (same thresholds as Home: -60, -72)', () {
    expect(WifiBand.fromRssi(-51), WifiBand.good);
    expect(WifiBand.fromRssi(-60), WifiBand.good);
    expect(WifiBand.fromRssi(-61), WifiBand.fair);
    expect(WifiBand.fromRssi(-72), WifiBand.fair);
    expect(WifiBand.fromRssi(-73), WifiBand.weak);
    expect(formatWifi(en, -51), 'Good (-51 dBm)');
    expect(formatWifi(en, -80), 'Weak (-80 dBm)');
  });

  test('reset reason', () {
    expect(formatResetReason(en, 3), 'Restart');
    expect(formatResetReason(en, 6), 'Restarted after a hang');
    expect(formatResetReason(en, 12), 'Other (12)');
    expect(formatKb(en, 81920), '80 KB');
  });

  test('phone list: {"phones": [...]}, self, created 0 = unknown', () {
    final list = RegisteredPhoneModel.listFromJson({
      'phones': [
        {'phone_id': 'p1', 'name': "Mom's Galaxy S24", 'created': 1790000000, 'self': true},
        {'phone_id': 'p2', 'name': "Dad's iPhone", 'created': 0, 'self': false},
      ],
    });
    expect(list.length, 2);
    expect(list[0].self, isTrue);
    expect(list[0].created, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
    expect(list[1].self, isFalse);
    expect(list[1].created, isNull);
  });

  group('/status.ai', () {
    test('new firmware: provider, mode, available', () {
      final j = {
        ...statusJson,
        'secrets': {'openai_key': true, 'gemini_key': false},
        'ai': {
          'provider': 'openai',
          'mode': 'saver',
          'available': ['openai.live', 'openai.saver'],
        },
      };
      final s = SystemStatusModel.fromJson(j);
      expect(s.ai.provider, AiProvider.openai);
      expect(s.ai.mode, AiMode.saver);
      expect(s.ai.reported, isTrue);
      expect(s.ai.isAvailable(AiProvider.openai, AiMode.saver), isTrue);
      expect(s.ai.providerAvailable(AiProvider.gemini), isFalse);
      expect(s.hasSecret('gemini_key'), isFalse);
      // Home shows the same value
      expect(DeviceStatusModel.fromJson(j).ai, s.ai);
    });

    test('old firmware (no ai) or malformed: OpenAI real-time only', () {
      for (final ai in [null, 'x', 3, <String, dynamic>{}]) {
        final s = SystemStatusModel.fromJson({...statusJson, 'ai': ai});
        expect(s.ai.provider, AiProvider.openai, reason: '$ai');
        expect(s.ai.mode, AiMode.live, reason: '$ai');
        expect(s.ai.available, {'openai.live'}, reason: '$ai');
      }
      expect(SystemStatusModel.fromJson(statusJson).ai, AiStatus.legacy);
      expect(DeviceStatusModel.fromJson(statusJson).ai, AiStatus.legacy);
    });

    test('unknown values fall back to defaults, non-string available entries are dropped', () {
      final ai = AiStatus.fromJson({
        'provider': 'claude',
        'mode': 'turbo',
        'available': ['gemini.saver', 7, null],
      });
      expect(ai.provider, AiProvider.openai);
      expect(ai.mode, AiMode.live);
      expect(ai.available, {'gemini.saver'});
      expect(ai.reported, isTrue);
    });
  });
}
