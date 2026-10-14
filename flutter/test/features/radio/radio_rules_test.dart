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
  group('묶음', () {
    test('기본 프리셋: 디자인과 같은 묶음, 모두 정확히 한 번', () {
      final groups = groupPresets(defaults);
      final all = [for (final (_, idx) in groups) ...idx]..sort();
      expect(all, List.generate(defaults.length, (i) => i));
      final by = {for (final (g, idx) in groups) g: idx};
      expect(by[PresetGroup.music], [0, 1, 2, 3, 4, 5]);
      expect(by[PresetGroup.talk], [9, 10, 11]);
      expect(by[PresetGroup.news], [6, 7, 8, 12]);
      expect(groups.map((g) => g.$1), [PresetGroup.music, PresetGroup.news, PresetGroup.talk]);
    });

    test('태그가 없거나 모르는 태그면 기타', () {
      final groups = groupPresets(const [
        RadioPreset(name: 'a', url: 'http://a/x'),
        RadioPreset(name: 'b', url: 'http://b/x', genre: 'jazz'),
        RadioPreset(name: 'c', url: 'http://c/x', genre: 'Jazz, Korean'),
      ]);
      expect([for (final (g, idx) in groups) '${g.name}:${idx.join(',')}'], ['music:1', 'korean:2', 'other:0']);
    });

    test('화면 태그에서 korean·english는 뺀다', () {
      expect(defaults[0].displayTags, ['alternative', 'indie', 'eclectic']);
      expect(const RadioPreset(name: 'k', url: 'http://k/x', genre: 'kpop,pop,korean').displayTags, ['kpop', 'pop']);
      expect(defaults[8].displayTags, ['business', 'finance', 'news']);
    });
  });

  group('틀 수 있는 방송 (radio_search.c playable)', () {
    test('MP3·AAC 직접 스트림만', () {
      expect(isPlayable(station()), isTrue);
      expect(isPlayable(station(url: 'https://a.example/live', codec: 'AAC')), isTrue);
      expect(isPlayable(station(codec: 'AAC+')), isTrue);
      expect(isPlayable(station(codec: 'OGG')), isFalse);
      expect(isPlayable(station(codec: 'mp3')), isFalse); // the firmware is case-sensitive
      expect(isPlayable(station(codec: '')), isFalse);
    });

    test('HLS는 뺀다 (주소 .m3u8 또는 hls 표시)', () {
      expect(isPlayable(station(url: 'https://kbs.example/live/playlist.m3u8')), isFalse);
      expect(isPlayable(station(hls: 1)), isFalse);
      expect(isPlayable(station(hls: null)), isTrue);
    });

    test('http(s)가 아니거나 256바이트 넘는 주소는 뺀다', () {
      expect(isPlayable(station(url: 'rtsp://a.example/live')), isFalse);
      expect(isPlayable(station(url: 'http://a.example/${'x' * 239}')), isTrue); // 256 bytes
      expect(isPlayable(station(url: 'http://a.example/${'x' * 240}')), isFalse);
      expect(isPlayable({'codec': 'MP3'}), isFalse);
      expect(isPlayable({'codec': 'MP3', 'url_resolved': 3}), isFalse);
    });
  });

  group('프리셋 검증 (radio_presets.c presets_valid)', () {
    test('기본 프리셋은 통과', () => expect(validatePresets(defaults), isNull));

    test('20개까지', () {
      final p = const RadioPreset(name: 'a', url: 'http://a/x');
      expect(validatePresets(List.filled(20, p)), isNull);
      expect(validatePresets(List.filled(21, p)), PresetError.tooMany);
    });

    test('이름은 1–48바이트 (한글 3바이트)', () {
      expect(validatePreset(const RadioPreset(name: '', url: 'http://a/x')), PresetError.nameEmpty);
      expect(validatePreset(RadioPreset(name: '가' * 16, url: 'http://a/x')), isNull);
      expect(validatePreset(RadioPreset(name: '가' * 17, url: 'http://a/x')), PresetError.nameTooLong);
      expect(validatePreset(RadioPreset(name: 'a' * 48, url: 'http://a/x')), isNull);
    });

    test('주소는 http(s), 8–256바이트', () {
      expect(validatePreset(const RadioPreset(name: 'a', url: 'ftp://a/x')), PresetError.urlInvalid);
      expect(validatePreset(const RadioPreset(name: 'a', url: 'http://')), PresetError.urlInvalid);
      expect(validatePreset(const RadioPreset(name: 'a', url: 'http://a')), isNull);
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://${'a' * 250}')), PresetError.urlTooLong);
    });

    test('장르는 64바이트까지', () {
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://a/x', genre: 'a' * 64)), isNull);
      expect(validatePreset(RadioPreset(name: 'a', url: 'http://a/x', genre: 'a' * 65)), PresetError.genreTooLong);
    });

    test('본문이 8KB를 넘으면 거절', () {
      // Even within the limit, JSON escaping (\") can make the body larger
      final big = RadioPreset(name: '"' * 48, url: 'https://${'"' * 248}', genre: '"' * 64);
      expect(validatePreset(big), isNull);
      expect(validatePresets(List.filled(20, big)), PresetError.tooLarge);
    });
  });

  test('검색 결과 → 프리셋: 이름·장르를 바이트 한도로 자른다', () {
    final p = presetFromStation(RadioStation(
      name: '가' * 20,
      url: 'http://a/x',
      tags: 'Jazz, smooth jazz,${'x' * 50},jazz,blues',
    ));
    expect(utf8Length(p.name), 48);
    expect(p.name, '가' * 16);
    expect(p.genre, 'jazz,smooth jazz');
    expect(validatePreset(p), isNull);
  });

  test('재생 중 프리셋: 번호가 맞으면 번호로, 순서가 바뀌면 이름으로', () {
    RadioNow now(int? preset, String station) =>
        RadioNow(media: MediaNow(source: 'radio', state: 'playing', station: station), preset: preset);
    expect(playingPresetIndex(defaults, now(8, 'Bloomberg Radio')), 8);
    expect(playingPresetIndex(defaults, now(0, 'CNN')), 6);
    expect(playingPresetIndex(defaults, now(null, 'Some URL')), isNull);
    expect(playingPresetIndex(defaults, const RadioNow(preset: 0)), isNull); // stopped
  });
}
