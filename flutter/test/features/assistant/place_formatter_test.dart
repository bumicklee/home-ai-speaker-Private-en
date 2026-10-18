import 'package:aispeaker/features/assistant/domain/services/place_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Korean address → province, district, neighborhood (Korean-specific logic, Korean geocoder output)', () {
    test('iOS layout (subLocality = district, name = neighborhood + lot number)', () {
      const p = PlaceParts(
        isoCountryCode: 'KR',
        administrativeArea: '서울특별시',
        subLocality: '강남구',
        thoroughfare: '테헤란로',
        name: '역삼동 736-1',
      );
      expect(PlaceFormatter.format(p), '서울 강남구 역삼동');
    });

    test('Android layout (locality = district, subLocality = neighborhood; road and building names are dropped)', () {
      const p = PlaceParts(
        isoCountryCode: 'KR',
        administrativeArea: '서울특별시',
        locality: '강남구',
        subLocality: '역삼1동',
        thoroughfare: '테헤란로',
        name: '강남파이낸스센터 152',
      );
      expect(PlaceFormatter.format(p), '서울 강남구 역삼1동');
    });

    test('province + city + district + neighborhood', () {
      const p = PlaceParts(
        isoCountryCode: 'KR',
        administrativeArea: '경기도',
        locality: '수원시',
        subLocality: '영통구',
        thoroughfare: '매탄동',
        name: '123-4',
      );
      expect(PlaceFormatter.format(p), '경기도 수원시 영통구 매탄동');
    });

    test('shortens metropolitan cities and special self-governing provinces; -eup and -myeon', () {
      expect(
        PlaceFormatter.format(const PlaceParts(
            isoCountryCode: 'KR', administrativeArea: '부산광역시', locality: '해운대구', subLocality: '우동')),
        '부산 해운대구 우동',
      );
      expect(
        PlaceFormatter.format(const PlaceParts(
            isoCountryCode: 'KR', administrativeArea: '제주특별자치도', locality: '서귀포시', subLocality: '남원읍')),
        '제주도 서귀포시 남원읍',
      );
    });

    test('a neighborhood ending in number + -ga (Euljiro 3-ga)', () {
      const p = PlaceParts(isoCountryCode: 'KR', administrativeArea: '서울특별시', subLocality: '중구', name: '을지로3가 12');
      expect(PlaceFormatter.format(p), '서울 중구 을지로3가');
    });

    test('recognizes Korea by the province name even without a country code', () {
      const p = PlaceParts(administrativeArea: '서울특별시', locality: '마포구', subLocality: '서교동');
      expect(PlaceFormatter.format(p), '서울 마포구 서교동');
    });
  });

  test('outside Korea: neighborhood, city, state, country (no street number)', () {
    const p = PlaceParts(
      isoCountryCode: 'US',
      country: 'United States',
      administrativeArea: 'California',
      locality: 'San Francisco',
      subLocality: 'Mission District',
      thoroughfare: 'Valencia St',
      name: '500 Valencia St',
    );
    expect(PlaceFormatter.format(p), 'Mission District, San Francisco, California, United States');
  });

  test('drops the end when over 96 bytes', () {
    final p = PlaceParts(
      isoCountryCode: 'US',
      subLocality: 'A' * 40,
      locality: 'B' * 40,
      administrativeArea: 'C' * 40,
      country: 'D',
    );
    final s = PlaceFormatter.format(p);
    expect(s, '${'A' * 40}, ${'B' * 40}');
  });

  group('time zone candidates', () {
    test('kept as is when in the firmware table', () {
      final t = TimezoneSuggestion.of('America/Los_Angeles');
      expect(t.supported, isTrue);
      expect(t.phone, 'America/Los_Angeles');
    });

    test('not in the table: Asia/Seoul and UTC (Asia/Seoul first in Asia)', () {
      expect(TimezoneSuggestion.of('Asia/Ho_Chi_Minh').fallbacks, ['Asia/Seoul', 'UTC']);
      expect(TimezoneSuggestion.of('Europe/Paris').fallbacks, ['UTC', 'Asia/Seoul']);
      expect(TimezoneSuggestion.of('Europe/Paris').supported, isFalse);
    });

    test('UTC first when it cannot be read', () {
      final t = TimezoneSuggestion.of(null);
      expect(t.supported, isFalse);
      expect(t.fallbacks.first, 'UTC');
    });
  });
}
