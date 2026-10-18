import 'package:aispeaker/core/device/current_device.dart';
import 'package:aispeaker/core/errors/exceptions.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/network/device_api_client.dart';
import 'package:aispeaker/features/radio/data/datasources/radio_browser_datasource.dart';
import 'package:aispeaker/features/radio/data/repositories/radio_repository.dart';
import 'package:aispeaker/features/radio/domain/entities/radio_preset.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCurrent extends Mock implements CurrentDevice {}

class MockClient extends Mock implements DeviceApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockCurrent current;
  late MockClient client;
  late MockDio dio;
  late RadioRepository repo;

  setUp(() {
    current = MockCurrent();
    client = MockClient();
    dio = MockDio();
    when(() => current.client).thenReturn(client);
    repo = RadioRepository(current, RadioBrowserDataSource(dio));
  });

  test('GET presets is {"presets": [...]} (genre optional)', () async {
    when(() => client.get<dynamic>('/api/v1/radio/presets')).thenAnswer((_) async => {
          'presets': [
            {'name': 'CNN', 'url': 'https://a/x', 'genre': 'news'},
            {'name': 'B', 'url': 'http://b/x'},
          ],
        });
    final r = await repo.presets();
    expect(r.getOrElse(() => []), const [
      RadioPreset(name: 'CNN', url: 'https://a/x', genre: 'news'),
      RadioPreset(name: 'B', url: 'http://b/x'),
    ]);
  });

  test('PUT presets sends the whole list as {"presets": [...]}', () async {
    const list = [RadioPreset(name: 'CNN', url: 'https://a/x', genre: 'news')];
    final body = {
      'presets': [
        {'name': 'CNN', 'url': 'https://a/x', 'genre': 'news'},
      ],
    };
    when(() => client.put<dynamic>('/api/v1/radio/presets', body)).thenAnswer((_) async => body);
    final r = await repo.savePresets(list);
    expect(r.getOrElse(() => []), list);
    verify(() => client.put<dynamic>('/api/v1/radio/presets', body)).called(1);
  });

  test('play: {"preset": n} or {"url", "title"}', () async {
    when(() => client.post<dynamic>(any(), any())).thenAnswer((_) async => {'ok': true});
    await repo.playPreset(3);
    verify(() => client.post<dynamic>('/api/v1/media/play', {'preset': 3})).called(1);
    await repo.playUrl('http://a/x', 'Jazz');
    verify(() => client.post<dynamic>('/api/v1/media/play', {'url': 'http://a/x', 'title': 'Jazz'})).called(1);
    await repo.media('pause');
    verify(() => client.post<dynamic>('/api/v1/media/pause', null)).called(1);
  });

  test('409 NOT_PLAYING becomes DeviceFailure', () async {
    when(() => client.post<dynamic>(any(), any())).thenThrow(const DeviceApiException(409, 'NOT_PLAYING'));
    final r = await repo.media('next');
    expect(r.fold((f) => f, (_) => null), isA<DeviceFailure>().having((f) => f.status, 'status', 409));
  });

  test('reads the preset number from /media/now', () async {
    when(() => client.get<dynamic>('/api/v1/media/now')).thenAnswer((_) async =>
        {'source': 'radio', 'state': 'playing', 'title': 't', 'artist': 'a', 'station': 'CNN', 'preset': 2});
    final now = (await repo.now()).getOrElse(() => throw StateError(''));
    expect(now.preset, 2);
    expect(now.media.station, 'CNN');
    expect(now.isRadio, isTrue);
  });

  test('Radio-Browser search keeps only playable stations, each URL once', () async {
    when(() => dio.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters'))).thenAnswer((_) async =>
        Response(requestOptions: RequestOptions(), data: [
          {'name': 'Ok', 'url_resolved': 'http://ok/live', 'codec': 'MP3', 'hls': 0, 'bitrate': 128, 'tags': 'jazz'},
          {'name': 'Dup', 'url_resolved': 'http://ok/live', 'codec': 'MP3', 'hls': 0},
          {'name': 'Hls', 'url_resolved': 'https://kbs/live.m3u8', 'codec': 'AAC', 'hls': 1},
          {'name': 'Ogg', 'url_resolved': 'http://ogg/live', 'codec': 'OGG', 'hls': 0},
        ]));
    final r = await repo.search('jazz', byTag: true);
    final list = r.getOrElse(() => []);
    expect(list.map((s) => s.name), ['Ok']);
    expect(list.first.bitrate, 128);
    final q = verify(() => dio.get<List<dynamic>>('https://de1.api.radio-browser.info/json/stations/search',
        queryParameters: captureAny(named: 'queryParameters'))).captured.single as Map<String, dynamic>;
    expect(q, {'tag': 'jazz', 'hidebroken': 'true', 'order': 'clickcount', 'reverse': 'true', 'limit': 30});
  });

  test('Radio-Browser connection failure is NetworkFailure', () async {
    when(() => dio.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')))
        .thenThrow(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError));
    final r = await repo.search('jazz');
    expect(r.fold((f) => f, (_) => null), isA<NetworkFailure>());
  });
}
