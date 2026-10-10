import 'package:dio/dio.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';

/// Radio-Browser station search (straight from the phone, design document Chapter 6 "Radio"). Uses the external Dio (User-Agent required)
class RadioBrowserDataSource {
  RadioBrowserDataSource(this._dio);

  final Dio _dio;

  /// Same server as firmware `radio_search.c`
  static const host = 'https://de1.api.radio-browser.info';
  static const limit = 30;

  /// Most popular first. Leaves out stations the speaker can't play (HLS, other codecs). Each URL only once
  Future<List<RadioStation>> search(String query, {bool byTag = false}) async {
    try {
      final r = await _dio.get<List<dynamic>>(
        '$host/json/stations/search',
        queryParameters: {
          byTag ? 'tag' : 'name': query,
          'hidebroken': 'true',
          'order': 'clickcount',
          'reverse': 'true',
          'limit': limit,
        },
      );
      final seen = <String>{};
      return [
        for (final s in (r.data ?? const []).whereType<Map<String, dynamic>>())
          if (isPlayable(s) && seen.add(s['url_resolved'] as String))
            RadioStation(
              name: (s['name'] as String? ?? '').trim(),
              url: s['url_resolved'] as String,
              codec: s['codec'] as String,
              bitrate: (s['bitrate'] as num? ?? 0).toInt(),
              country: s['countrycode'] as String? ?? '',
              tags: s['tags'] as String? ?? '',
            ),
      ];
    } on DioException catch (e) {
      throw NetworkException(e.message);
    }
  }
}
