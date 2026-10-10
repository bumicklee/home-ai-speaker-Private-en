/// Radio rules. These must match the firmware:
/// - Preset validation: `radio_presets.c` `presets_valid()` + `media_radio.h` limits + `local_api.c` BODY_MAX
/// - Playable stations: `radio_search.c` `playable()`
/// Lengths are UTF-8 byte counts, because the firmware measures them with `strlen` (one Hangul character = 3 bytes).
library;

import 'dart:convert';

import 'entities/radio_preset.dart';

class RadioLimits {
  RadioLimits._();

  /// RADIO_MAX_PRESETS
  static const maxPresets = 20;

  /// RADIO_NAME_MAX (bytes)
  static const nameMax = 48;

  /// RADIO_URL_MAX (bytes)
  static const urlMax = 256;

  /// "http://" + one character. The firmware rejects URLs shorter than 8 bytes
  static const urlMin = 8;

  /// RADIO_GENRE_MAX (bytes)
  static const genreMax = 64;

  /// local_api.c BODY_MAX: the whole PUT body
  static const bodyMax = 8192;
}

enum PresetError { tooMany, nameEmpty, nameTooLong, urlInvalid, urlTooLong, genreTooLong, tooLarge, duplicate }

int utf8Length(String s) => utf8.encode(s).length;

bool isHttpUrl(String url) => url.startsWith('http://') || url.startsWith('https://');

/// Validate one preset (firmware order: name → URL → genre)
PresetError? validatePreset(RadioPreset p) {
  final name = utf8Length(p.name);
  if (name < 1) return PresetError.nameEmpty;
  if (name > RadioLimits.nameMax) return PresetError.nameTooLong;
  final url = utf8Length(p.url);
  if (url > RadioLimits.urlMax) return PresetError.urlTooLong;
  if (url < RadioLimits.urlMin || !isHttpUrl(p.url)) return PresetError.urlInvalid;
  if (utf8Length(p.genre) > RadioLimits.genreMax) return PresetError.genreTooLong;
  return null;
}

/// Validate the whole list before the PUT. null if it passes
PresetError? validatePresets(List<RadioPreset> presets) {
  if (presets.length > RadioLimits.maxPresets) return PresetError.tooMany;
  for (final p in presets) {
    final e = validatePreset(p);
    if (e != null) return e;
  }
  if (utf8Length(jsonEncode(presetsBody(presets))) > RadioLimits.bodyMax) return PresetError.tooLarge;
  return null;
}

Map<String, dynamic> presetsBody(List<RadioPreset> presets) => {'presets': [for (final p in presets) p.toJson()]};

/// Trim to fit the byte limit (never cuts in the middle of a character)
String truncateUtf8(String s, int maxBytes) {
  if (utf8Length(s) <= maxBytes) return s;
  final out = StringBuffer();
  var used = 0;
  for (final r in s.runes) {
    final n = utf8Length(String.fromCharCode(r));
    if (used + n > maxBytes) break;
    out.writeCharCode(r);
    used += n;
  }
  return out.toString().trimRight();
}

/// Entered tags → genre string (tidies spaces, capitals, and empty tags; does not trim length)
String normalizeGenre(String text) =>
    text.split(',').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toSet().join(',');

/// Search result tags → genre string. Tags over the limit are dropped whole
String genreFromTags(Iterable<String> tags) {
  final out = <String>[];
  for (final t in tags.map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty)) {
    if (out.contains(t)) continue;
    if (utf8Length([...out, t].join(',')) > RadioLimits.genreMax) break;
    out.add(t);
  }
  return out.join(',');
}

/// Whether one Radio-Browser station will play on the speaker (same rules as `radio_search.c` `playable()`)
/// - `url_resolved` is http(s) and 256 bytes or less
/// - Not HLS: no `.m3u8` in the URL and the `hls` flag is 0
/// - Codec starts with MP3 or AAC (AAC+ and so on)
bool isPlayable(Map<String, dynamic> s) {
  final codec = s['codec'];
  final url = s['url_resolved'];
  if (codec is! String || url is! String || utf8Length(url) > RadioLimits.urlMax) return false;
  final hlsFlag = s['hls'];
  final hls = url.contains('.m3u8') || (hlsFlag is num && hlsFlag.toInt() != 0);
  final codecOk = codec == 'MP3' || codec.startsWith('AAC');
  return isHttpUrl(url) && !hls && codecOk;
}

/// Search result → preset (name and genre trimmed to the firmware limits)
RadioPreset presetFromStation(RadioStation s) => RadioPreset(
      name: truncateUtf8(s.name.trim().isEmpty ? 'Radio' : s.name.trim(), RadioLimits.nameMax),
      url: s.url,
      genre: genreFromTags(s.tags.split(',')),
    );

/// Screen groups (design order)
enum PresetGroup { korean, news, talk, other }

const _talkTags = {'talk', 'community', 'politics'};
const _newsTags = {'news', 'business', 'finance', 'world', 'economy'};
const _koreanTags = {'korean', 'kpop', 'k-pop', 'korea', 'trot'};

/// Pick the group. Talk beats music; when news and talk are both present, the tag that comes first wins
/// (CNN "news,talk" → News & Business, NPR "talk,news" → Talk. Same as the design)
PresetGroup groupOf(RadioPreset p) {
  final tags = p.tags;
  final talkAt = tags.indexWhere(_talkTags.contains);
  final newsAt = tags.indexWhere(_newsTags.contains);
  if (talkAt >= 0 && (newsAt < 0 || talkAt < newsAt)) return PresetGroup.talk;
  if (newsAt >= 0) return PresetGroup.news;
  if (tags.any(_koreanTags.contains)) return PresetGroup.korean;
  return PresetGroup.other;
}

/// Preset numbers by group (every preset exactly once, in saved order within a group). Empty groups are left out
List<(PresetGroup, List<int>)> groupPresets(List<RadioPreset> presets) {
  final groups = {for (final g in PresetGroup.values) g: <int>[]};
  for (var i = 0; i < presets.length; i++) {
    groups[groupOf(presets[i])]!.add(i);
  }
  return [
    for (final g in PresetGroup.values)
      if (groups[g]!.isNotEmpty) (g, groups[g]!),
  ];
}

/// Number of the preset playing now. Checks the name first so it stays right after reordering
int? playingPresetIndex(List<RadioPreset> presets, RadioNow now) {
  if (!now.isRadio) return null;
  final i = now.preset;
  final station = now.media.station;
  if (i != null && i >= 0 && i < presets.length && (station.isEmpty || presets[i].name == station)) return i;
  if (station.isEmpty) return null;
  final byName = presets.indexWhere((p) => p.name == station);
  return byName >= 0 ? byName : null;
}
