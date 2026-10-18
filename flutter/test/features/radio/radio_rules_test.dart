import 'package:aispeaker/features/devices/domain/entities/device_status.dart';
import 'package:aispeaker/features/radio/domain/entities/radio_preset.dart';
import 'package:aispeaker/features/radio/domain/radio_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firmware radio_presets.c DEFAULTS (2026-10-03)
const defaults = [
  RadioPreset(name: 'KEXP Seattle', url: 'https://kexp-mp3-128.streamguys1.com/kexp128.mp3', genre: 'alternative,indie,eclectic'),
  RadioPreset(name: 'KCRW Eclectic24', url: 'https://streams.kcrw.com/e24_mp3', genre: 'eclectic,indie,electronic'),
  RadioPreset(name: 'WQXR Classical', url: 'https://stream.wqxr.org/wqxr', genre: 'classical'),
  RadioPreset(name: 'WWOZ New Orleans', url: 'https://wwoz-sc.streamguys1.com/wwoz-hi.mp3', genre: 'jazz,blues,roots'),
  RadioPreset(name: 'WFMU Freeform', url: 'http://stream0.wfmu.org/freeform-128k', genre: 'freeform,eclectic,rock'),
  RadioPreset(name: 'KJazz 88.1', url: 'https://streaming.live365.com/a49833', genre: 'jazz'),
  RadioPreset(name: 'CNN', url: 'https://tunein.cdnstream1.com/2868_96.mp3', genre: 'news,talk,english'),
  RadioPreset(name: 'CNN International', url: 'https://tunein.cdnstream1.com/3519_96.aac', genre: 'news,world,english'),
  RadioPreset(name: 'Bloomberg Radio', url: 'https://tunein.cdnstream1.com/3521_96.mp3', genre: 'business,finance,news,english'),
  RadioPreset(name: 'NPR', url: 'http://npr-ice.streamguys1.com/live.mp3', genre: 'talk,news,english'),
  RadioPreset(name: 'WNYC', url: 'https://fm939.wnyc.org/wnycfm-web', genre: 'talk,news,english'),
  RadioPreset(name: 'C-SPAN Radio', url: 'https://playerservices.streamtheworld.com/api/livestream-redirect/CSPANRADIO.mp3', genre: 'politics,talk,english'),
  RadioPreset(name: 'BBC World Service', url: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service', genre: 'news,world,english'),
];

Map<String, dynamic> station({String codec = 'MP3', String url = 'http://a.example/live', Object? hls = 0}) =>
    {'name': 'X', 'codec': codec, 'url_resolved': url, 'hls': hls};

void main() {
  group('groups', () {
    test('default presets: same groups as the design, each exactly once', () {
      final groups = groupPresets(defaults);
      final all = [for (final (_, idx) in groups) ...idx]..sort();
      expect(all, List.generate(defaults.length, (i) => i));
      final by = {for (final (g, idx) in groups) g: idx};
      expect(by[PresetGroup.music], [0, 1, 2, 3, 4, 5]);
      expect(by[PresetGroup.talk], [9, 10, 11]);
      expect(by[PresetGroup.news], [6, 7, 8, 12]);
      expect(groups.map((g) => g.$1), [PresetGroup.music, PresetGroup.news, PresetGroup.talk]);
    });

    test('no tags or unknown tags go to Other', () {
      final groups = groupPresets(const [
        RadioPreset(name: 'a', url: 'http://a/x'),
        RadioPreset(name: 'b', url: 'http://b/x', genre: 'jazz'),
        RadioPreset(name: 'c', url: 'http://c/x', genre: 'Jazz, Korean'),
      ]);
      expect([for (final (g, idx) in groups) '${g.name}:${idx.join(',')}'], ['music:1', 'korean:2', 'other:0']);
    });

    test('display tags drop korean and english', () {
      expect(defaults[0].displayTags, ['alternative', 'indie', 'eclectic']);
      expect(const RadioPreset(name: 'k', url: 'http://k/x', genre: 'kpop,pop,korean').displayTags, ['kpop', 'pop']);
      expect(defaults[8].displayTags, ['business', 'finance', 'news']);
    });
  });

  group('playable stations (radio_search.c playable)', () {
    test('direct MP3/AAC streams only', () {
      expect(isPlayable(station()), isTrue);
      expect(isPlayable(station(url: 'https://a.example/live', codec: 'AAC')), isTrue);
      expect(isPlayable(station(codec: 'AAC+')), isTrue);
      expect(isPlayable(station(codec: 'OGG')), isFalse);
      expect(isPlayable(station(codec: 'mp3')), isFalse); // the firmware is case-sensitive
      expect(isPlayable(station(codec: '')), isFalse);
    });

    test('drops HLS (.m3u8 URL or hls flag)', () {
      expect(isPlayable(station(url: 'https://kbs.example/live/playlist.m3u8')), isFalse);
      expect(isPlayable(station(hls: 1)), isFalse);
      expect(isPlayable(station(hls: null)), isTrue);
    });

    test('drops non-http(s) URLs and URLs over 256 bytes', () {
      expect(isPlayable(station(url: 'rtsp://a.example/live')), isFalse);
      expect(isPlayable(station(url: 'http://a.example/${'x' * 239}')), isTrue); // 256 bytes
      expect(isPlayable(station(url: 'http://a.example/${'x' * 240}')), isFalse);
      expect(isPlayable({'codec': 'MP3'}), isFalse);
      expect(isPlayable({'codec': 'MP3', 'url_resolved': 3}), isFalse);
    });
  });

  group('preset validation (radio_presets.c presets_valid)', () {
    test('default presets pass', () => expect(validatePresets(defaults), isNull));

    test('up to 20', () {
      final p = const RadioPreset(name: 'a', url: 'http://a/x');
      expect(validatePresets(List.filled(20, p)), isNull);
      expect(validatePresets(List.filled(21, p)), PresetError.tooMany);
    });

    test('name is 1–48 bytes (€ is 3 bytes)', () {
      expect(validatePreset(const RadioPreset(name: '', url: 'http://a/x')), PresetError.nameEmpty);
      expect(validatePreset(RadioPreset(name: '€' * 16, url: 'http://a/x')), isNull);
      expect(validatePreset(RadioPreset(name: '€' * 17, url: 'http://a/x')), PresetError.nameTooLong);
      expect(validatePreset(RadioPreset(name: 'a' * 48, url: 'http://a/x')), isNull);
    });

    test('URL is http(s), 8–256 bytes', () {
      expect(validatePreset(const RadioPreset(name: 'a', url: 'ftp://a/x')), PresetError.urlInvalid);
      expect(validatePreset(const RadioPreset(name: 'a', url: 'http://')), PresetError.urlInvalid);
      expect(validatePreset(const RadioPreset(name: 'a', url: 'http://a')), isNull);
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://${'a' * 250}')), PresetError.urlTooLong);
    });

    test('genre up to 64 bytes', () {
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://a/x', genre: 'a' * 64)), isNull);
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://a/x', genre: 'a' * 65)), PresetError.genreTooLong);
    });

    test('rejects a body over 8 KB', () {
      // Even within the limit, JSON escaping (\") can make the body larger
      final big = RadioPreset(name: '"' * 48, url: 'https://${'"' * 248}', genre: '"' * 64);
      expect(validatePreset(big), isNull);
      expect(validatePresets(List.filled(20, big)), PresetError.tooLarge);
    });
  });

  test('search result → preset: trims name and genre to the byte limits', () {
    final p = presetFromStation(RadioStation(
      name: '€' * 20,
      url: 'http://a/x',
      tags: 'Jazz, smooth jazz,${'x' * 50},jazz,blues',
    ));
    expect(utf8Length(p.name), 48);
    expect(p.name, '€' * 16);
    expect(p.genre, 'jazz,smooth jazz');
    expect(validatePreset(p), isNull);
  });

  test('playing preset: by number if it matches, by name if the order changed', () {
    RadioNow now(int? preset, String station) =>
        RadioNow(media: MediaNow(source: 'radio', state: 'playing', station: station), preset: preset);
    expect(playingPresetIndex(defaults, now(8, 'Bloomberg Radio')), 8);
    expect(playingPresetIndex(defaults, now(0, 'CNN')), 6);
    expect(playingPresetIndex(defaults, now(null, 'Some URL')), isNull);
    expect(playingPresetIndex(defaults, const RadioNow(preset: 0)), isNull); // stopped
  });
}
