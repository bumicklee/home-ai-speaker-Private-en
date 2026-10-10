import 'package:dartz/dartz.dart';

import '../../../../core/constants/api_paths.dart';
import '../../../../core/device/current_device.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/repository/guard.dart';
import '../../../devices/data/models/device_status_model.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';
import '../datasources/radio_browser_datasource.dart';

/// Radio: presets and playback go to the selected speaker (local_api.c); station search goes to Radio-Browser
class RadioRepository {
  RadioRepository(this._device, this._browser);

  final CurrentDevice _device;
  final RadioBrowserDataSource _browser;

  /// GET /radio/presets → `{"presets": [...]}`
  Future<Either<Failure, List<RadioPreset>>> presets() =>
      guard(() async => parsePresets(await _device.client.get<dynamic>(ApiPaths.radioPresets)));

  /// PUT /radio/presets `{"presets": [...]}` (replaces the whole list). Returns the list the device saved. 400 INVALID_ARG if validation fails
  Future<Either<Failure, List<RadioPreset>>> savePresets(List<RadioPreset> presets) =>
      guard(() async => parsePresets(await _device.client.put<dynamic>(ApiPaths.radioPresets, presetsBody(presets))));

  /// GET /media/now (Spotify state if the radio is off and Spotify is connected)
  Future<Either<Failure, RadioNow>> now() =>
      guard(() async => parseNow(await _device.client.get<dynamic>(ApiPaths.mediaNow) as Map<String, dynamic>));

  /// POST /media/play `{"preset": n}`. 400 for a number that doesn't exist
  Future<Either<Failure, Unit>> playPreset(int index) => _post(ApiPaths.mediaPlay, {'preset': index});

  /// POST /media/play `{"url", "title"}`. 400 if not http(s) or over 256 bytes
  Future<Either<Failure, Unit>> playUrl(String url, String title) =>
      _post(ApiPaths.mediaPlay, {'url': url, 'title': title});

  /// pause / resume / stop / next / previous. 409 NOT_PLAYING if nothing is playing
  Future<Either<Failure, Unit>> media(String action) => _post(ApiPaths.mediaControl(action));

  Future<Either<Failure, List<RadioStation>>> search(String query, {bool byTag = false}) =>
      guard(() => _browser.search(query, byTag: byTag));

  Future<Either<Failure, Unit>> _post(String path, [Object? body]) => guard(() async {
        await _device.client.post<dynamic>(path, body);
        return unit;
      });

  static List<RadioPreset> parsePresets(dynamic body) {
    final list = body is Map ? body['presets'] : body;
    return [for (final p in (list as List? ?? const []).whereType<Map<String, dynamic>>()) RadioPreset.fromJson(p)];
  }

  /// Shared by `/media/now` and WS `media_state` (the event key is ignored)
  static RadioNow parseNow(Map<String, dynamic> j) =>
      RadioNow(media: DeviceStatusModel.mediaFromJson(j), preset: (j['preset'] as num?)?.toInt());
}
