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

const gangnam = PlaceParts(
  isoCountryCode: 'KR',
  country: '대한민국',
  administrativeArea: '서울특별시',
  subLocality: '강남구',
  thoroughfare: '테헤란로',
  name: '역삼동 736-1',
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
        (_) async => const Right([AssistantMemory(key: 'favorite_food', value: '김치찌개')]));
  });

  Future<AssistantCubit> loaded() async {
    final c = AssistantCubit(repo, location);
    await c.load();
    return c;
  }

  test('설정·보이스·기억 수를 불러온다', () async {
    final c = await loaded();
    expect(c.state.original, saved);
    expect(c.state.draft, saved);
    expect(c.state.voices, ['alloy', 'marin', 'verse']);
    expect(c.state.memoryCount, 1);
    expect(c.state.dirty, isFalse);
    await c.close();
  });

  test('불러오기 실패면 failure', () async {
    when(() => repo.settings()).thenAnswer((_) async => const Left(DeviceFailure.timeout()));
    final c = await loaded();
    expect(c.state.draft, isNull);
    expect(c.state.failure?.errorKey, ErrorKeys.deviceTimeout);
    await c.close();
  });

  test('저장은 바뀐 키만 보내고 기기 응답으로 원본을 바꾼다', () async {
    final edited = saved.copyWith(name: '자비스', autoMemory: true);
    when(() => repo.update(any())).thenAnswer((_) async => Right(edited));
    final c = await loaded();
    c.edit((d) => d.copyWith(name: '자비스'));
    c.edit((d) => d.copyWith(autoMemory: true));
    c.edit((d) => d.copyWith(units: 'imperial'));
    c.edit((d) => d.copyWith(units: 'metric')); // a value changed back is not sent
    expect(c.state.dirty, isTrue);

    expect(await c.save(), isNull);
    final sent = verify(() => repo.update(captureAny())).captured.single as Map<String, dynamic>;
    expect(sent, {'name': '자비스', 'auto_memory': true});
    expect(c.state.original, edited);
    expect(c.state.dirty, isFalse);
    await c.close();
  });

  test('바뀐 것이 없으면 보내지 않는다', () async {
    final c = await loaded();
    c.edit((d) => d.copyWith(location: '  '));
    c.edit((d) => d.copyWith(location: ''));
    expect(await c.save(), isNull);
    verifyNever(() => repo.update(any()));
    await c.close();
  });

  test('저장 실패(400 INVALID_ARG)면 고친 값을 남긴다', () async {
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

  group('검사 (UTF-8 바이트)', () {
    test('이름은 32바이트까지: 한글 10자(30바이트) 통과, 11자(33바이트) 거부', () async {
      final c = await loaded();
      c.edit((d) => d.copyWith(name: '가나다라마바사아자차'));
      expect(c.state.errors, isEmpty);
      c.edit((d) => d.copyWith(name: '가나다라마바사아자차카'));
      expect(c.state.errors, [AssistantFieldError.nameTooLong]);
      expect(await c.save(), isNull);
      verifyNever(() => repo.update(any()));
      await c.close();
    });

    test('빈 이름은 거부', () {
      expect(saved.copyWith(name: '  ').validate(), [AssistantFieldError.nameEmpty]);
    });

    test('동네는 96바이트까지', () {
      expect(saved.copyWith(location: '가' * 32).validate(), isEmpty); // 96 bytes
      expect(saved.copyWith(location: '${'가' * 32}a').validate(), [AssistantFieldError.locationTooLong]);
    });

    test('목적은 600바이트까지', () {
      expect(saved.copyWith(purpose: 'a' * 600).validate(), isEmpty);
      expect(saved.copyWith(purpose: 'a' * 601).validate(), [AssistantFieldError.purposeTooLong]);
    });
  });

  group('현재 위치로', () {
    test('동네 이름과 (표에 있는) 휴대폰 시간대를 넣는다. 좌표는 보내지 않는다', () async {
      when(() => location.currentPlace()).thenAnswer((_) async => gangnam);
      when(() => location.phoneTimezone()).thenAnswer((_) async => 'Asia/Tokyo');
      when(() => repo.update(any())).thenAnswer((_) async => Right(saved.copyWith(location: '서울 강남구 역삼동')));
      final c = await loaded();
      expect(await c.locate(), LocateResult.filled);
      expect(c.state.draft?.location, '서울 강남구 역삼동');
      expect(c.state.draft?.timezone, 'Asia/Tokyo');
      expect(c.state.timezone, isNull);

      await c.save();
      final sent = verify(() => repo.update(captureAny())).captured.single as Map<String, dynamic>;
      expect(sent, {'location': '서울 강남구 역삼동', 'timezone': 'Asia/Tokyo'});
      await c.close();
    });

    test('표에 없는 시간대면 시간대는 그대로 두고 Asia/Seoul·UTC 후보를 보인다', () async {
      when(() => location.currentPlace()).thenAnswer((_) async => gangnam);
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

    test('권한 거부는 결과로 알리고 값은 바꾸지 않는다', () async {
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
