import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/features/assistant/data/services/location_service.dart';
import 'package:aispeaker/features/assistant/domain/entities/assistant_settings.dart';
import 'package:aispeaker/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:aispeaker/features/assistant/domain/services/place_formatter.dart';
import 'package:aispeaker/features/assistant/presentation/bloc/assistant_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements AssistantRepository {}

class MockLocation extends Mock implements LocationService {}

/// Same values as the firmware DEFAULTS
const saved = AssistantSettings(
  name: 'Jarvis',
  purpose: 'A helpful family home assistant.',
  language: 'ko',
  voice: 'marin',
  location: '',
  units: 'metric',
  webSearch: true,
  deviceControls: true,
  autoMemory: false,
  timezone: 'Asia/Seoul',
);

const mission = PlaceParts(
  isoCountryCode: 'US',
  country: 'United States',
  administrativeArea: 'California',
  locality: 'San Francisco',
  subLocality: 'Mission District',
  thoroughfare: 'Valencia St',
  name: '500 Valencia St',
);

void main() {
  late MockRepo repo;
  late MockLocation location;

  setUp(() {
    repo = MockRepo();
    location = MockLocation();
    when(() => repo.settings()).thenAnswer((_) async => const Right(saved));
    when(() => repo.voices()).thenAnswer((_) async => const Right(['alloy', 'marin', 'verse']));
    when(() => repo.memories()).thenAnswer(
        (_) async => const Right([AssistantMemory(key: 'favorite_food', value: 'kimchi stew')]));
  });

  Future<AssistantCubit> loaded() async {
    final c = AssistantCubit(repo, location);
    await c.load();
    return c;
  }

  test('loads settings, voices and memory count', () async {
    final c = await loaded();
    expect(c.state.original, saved);
    expect(c.state.draft, saved);
    expect(c.state.voices, ['alloy', 'marin', 'verse']);
    expect(c.state.memoryCount, 1);
    expect(c.state.dirty, isFalse);
    await c.close();
  });

  test('load failure gives failure', () async {
    when(() => repo.settings()).thenAnswer((_) async => const Left(DeviceFailure.timeout()));
    final c = await loaded();
    expect(c.state.draft, isNull);
    expect(c.state.failure?.errorKey, ErrorKeys.deviceTimeout);
    await c.close();
  });

  test('save sends only changed keys and replaces the original with the device response', () async {
    final edited = saved.copyWith(name: 'Friday', autoMemory: true);
    when(() => repo.update(any())).thenAnswer((_) async => Right(edited));
    final c = await loaded();
    c.edit((d) => d.copyWith(name: 'Friday'));
    c.edit((d) => d.copyWith(autoMemory: true));
    c.edit((d) => d.copyWith(units: 'imperial'));
    c.edit((d) => d.copyWith(units: 'metric')); // a value changed back is not sent
    expect(c.state.dirty, isTrue);

    expect(await c.save(), isNull);
    final sent = verify(() => repo.update(captureAny())).captured.single as Map<String, dynamic>;
    expect(sent, {'name': 'Friday', 'auto_memory': true});
    expect(c.state.original, edited);
    expect(c.state.dirty, isFalse);
    await c.close();
  });

  test('sends nothing when nothing changed', () async {
    final c = await loaded();
    c.edit((d) => d.copyWith(location: '  '));
    c.edit((d) => d.copyWith(location: ''));
    expect(await c.save(), isNull);
    verifyNever(() => repo.update(any()));
    await c.close();
  });

  test('save failure (400 INVALID_ARG) keeps the edited values', () async {
    when(() => repo.update(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(400, 'INVALID_ARG')));
    final c = await loaded();
    c.edit((d) => d.copyWith(voice: 'verse'));
    final f = await c.save();
    expect(f?.errorKey, ErrorKeys.deviceInvalidArg);
    expect(c.state.draft?.voice, 'verse');
    expect(c.state.dirty, isTrue);
    expect(c.state.saving, isFalse);
    await c.close();
  });

  group('validation (UTF-8 bytes)', () {
    test('name up to 32 bytes: 10 three-byte chars (30 bytes) pass, 11 (33 bytes) rejected', () async {
      final c = await loaded();
      c.edit((d) => d.copyWith(name: '€' * 10));
      expect(c.state.errors, isEmpty);
      c.edit((d) => d.copyWith(name: '€' * 11));
      expect(c.state.errors, [AssistantFieldError.nameTooLong]);
      expect(await c.save(), isNull);
      verifyNever(() => repo.update(any()));
      await c.close();
    });

    test('rejects an empty name', () {
      expect(saved.copyWith(name: '  ').validate(), [AssistantFieldError.nameEmpty]);
    });

    test('location up to 96 bytes', () {
      expect(saved.copyWith(location: '€' * 32).validate(), isEmpty); // 96 bytes
      expect(saved.copyWith(location: '${'€' * 32}a').validate(), [AssistantFieldError.locationTooLong]);
    });

    test('purpose up to 600 bytes', () {
      expect(saved.copyWith(purpose: 'a' * 600).validate(), isEmpty);
      expect(saved.copyWith(purpose: 'a' * 601).validate(), [AssistantFieldError.purposeTooLong]);
    });
  });

  group('use current location', () {
    test('fills in the place name and the phone time zone (when in the table); coordinates are not sent', () async {
      when(() => location.currentPlace()).thenAnswer((_) async => mission);
      when(() => location.phoneTimezone()).thenAnswer((_) async => 'Asia/Tokyo');
      when(() => repo.update(any())).thenAnswer((_) async => Right(saved.copyWith(location: 'Mission District, San Francisco, California, United States')));
      final c = await loaded();
      expect(await c.locate(), LocateResult.filled);
      expect(c.state.draft?.location, 'Mission District, San Francisco, California, United States');
      expect(c.state.draft?.timezone, 'Asia/Tokyo');
      expect(c.state.timezone, isNull);

      await c.save();
      final sent = verify(() => repo.update(captureAny())).captured.single as Map<String, dynamic>;
      expect(sent, {'location': 'Mission District, San Francisco, California, United States', 'timezone': 'Asia/Tokyo'});
      await c.close();
    });

    test('time zone not in the table: keeps the time zone and offers Asia/Seoul and UTC', () async {
      when(() => location.currentPlace()).thenAnswer((_) async => mission);
      when(() => location.phoneTimezone()).thenAnswer((_) async => 'Asia/Kolkata');
      final c = await loaded();
      expect(await c.locate(), LocateResult.filledTimezoneUnsupported);
      expect(c.state.draft?.timezone, 'Asia/Seoul');
      expect(c.state.timezone?.supported, isFalse);
      expect(c.state.timezone?.fallbacks, ['Asia/Seoul', 'UTC']);

      c.setTimezone('UTC');
      expect(c.state.draft?.timezone, 'UTC');
      expect(c.state.timezone, isNull);
      await c.close();
    });

    test('permission denial is reported as the result and values stay unchanged', () async {
      when(() => location.currentPlace())
          .thenThrow(const LocationLookupException(LocationError.deniedForever));
      final c = await loaded();
      expect(await c.locate(), LocateResult.deniedForever);
      expect(c.state.draft, saved);
      expect(c.state.locating, isFalse);
      await c.close();
    });
  });
}
