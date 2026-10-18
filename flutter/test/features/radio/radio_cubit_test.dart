import 'dart:async';

import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/core/services/device_event_service.dart';
import 'package:aispeaker/features/devices/domain/entities/device_status.dart';
import 'package:aispeaker/features/radio/data/repositories/radio_repository.dart';
import 'package:aispeaker/features/radio/domain/entities/radio_preset.dart';
import 'package:aispeaker/features/radio/domain/radio_rules.dart';
import 'package:aispeaker/features/radio/presentation/bloc/radio_cubit.dart';
import 'package:aispeaker/features/radio/presentation/bloc/radio_search_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements RadioRepository {}

class MockEvents extends Mock implements DeviceEventService {}

const presets = [
  RadioPreset(name: 'CNN', url: 'https://tunein.cdnstream1.com/2868_96.mp3', genre: 'news,talk,english'),
  RadioPreset(name: 'Big B', url: 'https://antares.dribbcast.com/proxy/kpop?mp=/s', genre: 'kpop,korean'),
];
const playing = RadioNow(media: MediaNow(source: 'radio', state: 'playing', station: 'CNN'), preset: 0);

void main() {
  late MockRepo repo;
  late MockEvents events;
  late StreamController<DeviceEvent> stream;

  setUpAll(() => registerFallbackValue(<RadioPreset>[]));

  setUp(() {
    repo = MockRepo();
    events = MockEvents();
    stream = StreamController<DeviceEvent>.broadcast();
    when(() => events.on(DeviceEventType.mediaState))
        .thenAnswer((_) => stream.stream.where((e) => e.type == DeviceEventType.mediaState));
    when(() => repo.presets()).thenAnswer((_) async => const Right(presets));
    when(() => repo.now()).thenAnswer((_) async => const Right(RadioNow()));
    when(() => repo.media(any())).thenAnswer((_) async => const Right(unit));
  });

  RadioCubit build() => RadioCubit(repo, events);

  test('loads presets and what is playing now', () async {
    when(() => repo.now()).thenAnswer((_) async => const Right(playing));
    final c = build();
    await c.load();
    expect(c.state.loaded, isTrue);
    expect(c.state.presets, presets);
    expect(c.state.playingIndex, 0);
    await c.close();
  });

  test('media_state event updates the header card', () async {
    final c = build();
    await c.load();
    expect(c.state.now.media.isActive, isFalse);
    stream.add(const DeviceEvent('media_state',
        {'source': 'radio', 'state': 'playing', 'title': 'Song', 'artist': 'A', 'station': 'Big B', 'preset': 1}));
    await Future<void>.delayed(Duration.zero);
    expect(c.state.now.media.state, 'playing');
    expect(c.state.now.media.title, 'Song');
    expect(c.state.playingIndex, 1);
    stream.add(const DeviceEvent('media_state', {'source': 'none', 'state': 'stopped'}));
    await Future<void>.delayed(Duration.zero);
    expect(c.state.playingIndex, isNull);
    await c.close();
  });

  test('preset playback sends the preset number', () async {
    when(() => repo.playPreset(1)).thenAnswer((_) async => const Right(unit));
    final c = build();
    await c.load();
    await c.playPreset(1);
    verify(() => repo.playPreset(1)).called(1);
    expect(c.state.busy, isFalse);
    await c.close();
  });

  test('playing a search result sends the URL and name (up to 48 bytes)', () async {
    when(() => repo.playUrl(any(), any())).thenAnswer((_) async => const Right(unit));
    final c = build();
    await c.playStation(RadioStation(name: '€' * 20, url: 'http://a.example/live'));
    verify(() => repo.playUrl('http://a.example/live', '€' * 16)).called(1);
    await c.close();
  });

  test('pauses while playing, resumes when stopped', () async {
    when(() => repo.now()).thenAnswer((_) async => const Right(playing));
    final c = build();
    await c.load();
    await c.togglePause();
    verify(() => repo.media('pause')).called(1);

    stream.add(const DeviceEvent('media_state', {'source': 'radio', 'state': 'paused', 'station': 'CNN'}));
    await Future<void>.delayed(Duration.zero);
    await c.togglePause();
    verify(() => repo.media('resume')).called(1);
    await c.close();
  });

  test('409 NOT_PLAYING reports failure and re-fetches the current state', () async {
    when(() => repo.media('next')).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'NOT_PLAYING')));
    final c = build();
    await c.load();
    await c.media('next');
    expect(c.state.failure, isA<DeviceFailure>().having((f) => f.code, 'code', 'NOT_PLAYING'));
    verify(() => repo.now()).called(2);
    await c.close();
  });

  test('saving edits PUTs the whole list and uses the list the device returns', () async {
    final edited = [presets[1].copyWith(name: 'K-pop'), presets[0]];
    when(() => repo.savePresets(any())).thenAnswer((i) async => Right(i.positionalArguments[0] as List<RadioPreset>));
    final c = build();
    await c.load();
    expect(await c.savePresets(edited), isTrue);
    verify(() => repo.savePresets(edited)).called(1);
    expect(c.state.presets, edited);
    await c.close();
  });

  test('does not send presets that break firmware rules', () async {
    final c = build();
    await c.load();
    expect(await c.savePresets([...presets, const RadioPreset(name: 'x', url: 'rtsp://a/b')]), isFalse);
    expect(c.state.invalid, PresetError.urlInvalid);
    expect(await c.savePresets(List.filled(21, presets[0])), isFalse);
    expect(c.state.invalid, PresetError.tooMany);
    verifyNever(() => repo.savePresets(any()));
    await c.close();
  });

  test('adds to the end, rejects a duplicate URL', () async {
    const added = RadioPreset(name: 'BBC', url: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service', genre: 'news');
    when(() => repo.savePresets(any())).thenAnswer((i) async => Right(i.positionalArguments[0] as List<RadioPreset>));
    final c = build();
    await c.load();
    expect(await c.addPreset(added), isTrue);
    verify(() => repo.savePresets([...presets, added])).called(1);
    expect(await c.addPreset(added), isFalse);
    expect(c.state.invalid, PresetError.duplicate);
    await c.close();
  });

  test('save failure (400) becomes failure', () async {
    when(() => repo.savePresets(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(400, 'INVALID_ARG')));
    final c = build();
    await c.load();
    expect(await c.savePresets(presets), isFalse);
    expect(c.state.failure?.errorKey, ErrorKeys.deviceInvalidArg);
    expect(c.state.presets, presets);
    await c.close();
  });

  group('station search', () {
    test('searches by name or genre and shows results', () async {
      const result = [RadioStation(name: 'Jazz FM', url: 'http://jazz.example/live', codec: 'MP3')];
      when(() => repo.search(any(), byTag: any(named: 'byTag'))).thenAnswer((_) async => const Right(result));
      final c = RadioSearchCubit(repo);
      await c.search('  jazz ');
      verify(() => repo.search('jazz', byTag: false)).called(1);
      expect(c.state.results, result);

      c.setByTag(true);
      await Future<void>.delayed(Duration.zero);
      verify(() => repo.search('jazz', byTag: true)).called(1);
      await c.close();
    });

    test('failure leaves no results and sets failure', () async {
      when(() => repo.search(any(), byTag: any(named: 'byTag')))
          .thenAnswer((_) async => const Left(NetworkFailure(message: 'x')));
      final c = RadioSearchCubit(repo);
      await c.search('jazz');
      expect(c.state.failure, isNotNull);
      expect(c.state.results, isNull);
      await c.close();
    });
  });
}
