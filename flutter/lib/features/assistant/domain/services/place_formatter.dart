/// Phone reverse-geocoding result → neighborhood name to store on the speaker (design document Section 3.0).
/// In Korea, keep only `province city/county neighborhood` and drop lot numbers, building names and road names (e.g. "서울 강남구 역삼동").
library;

import '../entities/assistant_settings.dart';

/// Reverse-geocoding address parts (only what we need from geocoding `Placemark`, so it can be tested without the plugin)
class PlaceParts {
  const PlaceParts({
    this.isoCountryCode,
    this.country,
    this.administrativeArea,
    this.subAdministrativeArea,
    this.locality,
    this.subLocality,
    this.thoroughfare,
    this.name,
  });

  final String? isoCountryCode;
  final String? country;
  final String? administrativeArea;
  final String? subAdministrativeArea;
  final String? locality;
  final String? subLocality;
  final String? thoroughfare;
  final String? name;
}

class PlaceFormatter {
  PlaceFormatter._();

  static final _sido = RegExp(r'^[가-힣]+(특별시|광역시|특별자치시|특별자치도|도)$');
  static final _sigungu = RegExp(r'^[가-힣]+(시|군|구)$');

  /// 동/읍/면 neighborhoods, numbered 동 (역삼1동), and 가 (을지로3가)
  static final _dong = RegExp(r'^[가-힣]+(\d*동|읍|면|\d+가)$');

  /// Empty string if it can't build one
  static String format(PlaceParts p) {
    final text = p.isoCountryCode?.toUpperCase() == 'KR' || _looksKorean(p) ? _korean(p) : _other(p);
    return _fit(text);
  }

  static bool _looksKorean(PlaceParts p) => p.isoCountryCode == null && _sido.hasMatch(p.administrativeArea ?? '');

  /// Field layout differs by platform (Android: locality = district, iOS: subLocality = district, etc.), so split every part into words and pick from them
  static String _korean(PlaceParts p) {
    final words = <String>[];
    for (final f in [p.administrativeArea, p.subAdministrativeArea, p.locality, p.subLocality, p.thoroughfare, p.name]) {
      for (final w in (f ?? '').split(RegExp(r'\s+'))) {
        if (w.isNotEmpty && !words.contains(w)) words.add(w);
      }
    }
    String? sido;
    final sigungu = <String>[];
    String? dong;
    for (final w in words) {
      if (sido == null && _sido.hasMatch(w)) {
        sido = w;
      } else if (_sigungu.hasMatch(w) && w != sido && sigungu.length < 2 && !sigungu.contains(w)) {
        sigungu.add(w); // there can be two city/district levels, as in 수원시 영통구
      } else if (dong == null && _dong.hasMatch(w)) {
        dong = w;
      }
    }
    return [if (sido != null) _shortSido(sido), ...sigungu, ?dong].join(' ');
  }

  /// 서울특별시 → 서울, 부산광역시 → 부산, 세종특별자치시 → 세종, 제주특별자치도 → 제주도. 경기도 stays as is
  static String _shortSido(String s) {
    for (final suffix in ['특별자치시', '특별시', '광역시']) {
      if (s.endsWith(suffix)) return s.substring(0, s.length - suffix.length);
    }
    if (s.endsWith('특별자치도')) return '${s.substring(0, s.length - 5)}도';
    return s;
  }

  /// Abroad: whichever of "neighborhood, city, state, country" exist (no lot numbers or road names)
  static String _other(PlaceParts p) {
    final parts = <String>[];
    for (final f in [p.subLocality, p.locality, p.administrativeArea, p.country]) {
      final v = f?.trim() ?? '';
      if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
    }
    return parts.join(', ');
  }

  /// Over 96 bytes: keep from the front (the larger region) and drop the end
  static String _fit(String text) {
    var t = text;
    while (utf8Bytes(t) > AssistantLimits.locationBytes) {
      final cut = t.lastIndexOf(RegExp(r'[ ,]'));
      t = cut > 0 ? t.substring(0, cut).replaceAll(RegExp(r'[ ,]+$'), '') : '';
    }
    return t;
  }
}

/// Whether the speaker knows the phone's time zone. If not, candidates to pick from (Asia/Seoul, UTC — the closer one first)
class TimezoneSuggestion {
  const TimezoneSuggestion._(this.phone, this.supported, this.fallbacks);

  factory TimezoneSuggestion.of(String? phone) {
    if (phone != null && AssistantLimits.timezones.contains(phone)) {
      return TimezoneSuggestion._(phone, true, const []);
    }
    final asia = phone != null && (phone.startsWith('Asia/') || phone == 'ROK' || phone == 'Japan');
    return TimezoneSuggestion._(phone, false, asia ? const ['Asia/Seoul', 'UTC'] : const ['UTC', 'Asia/Seoul']);
  }

  /// Phone IANA name (null if it can't be read)
  final String? phone;

  /// In the firmware `TIMEZONES` → can be used as is
  final bool supported;
  final List<String> fallbacks;
}
