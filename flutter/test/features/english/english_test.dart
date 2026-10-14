import 'dart:async';

import 'package:aispeaker/core/errors/error_keys.dart';
import 'package:aispeaker/core/errors/failures.dart';
import 'package:aispeaker/features/english/data/models/lesson_model.dart';
import 'package:aispeaker/features/english/data/repositories/lesson_repository.dart';
import 'package:aispeaker/features/english/domain/entities/lesson.dart';
import 'package:aispeaker/features/english/presentation/bloc/english_cubit.dart';
import 'package:aispeaker/features/english/presentation/bloc/lesson_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRepo extends Mock implements LessonRepository {}

/// Shape of the firmware lesson_json()
const firmwareJson = {
  'state': 'active',
  'course': 'biz',
  'explain': 'ko',
  'speed': 'slow',
  'minutes': 5,
  'elapsed_s': 138,
  'remaining_s': 162,
  'topic': "Preparing for next week's team meeting",
  'corrections': [
    {'original': '다른 방법 말하고 싶어요.', 'better': '다른 방법을 제안드리고 싶습니다. (dareun bangbeobeul jeandeurigo sipseumnida)', 'note': 'More polite: I would like to suggest a different approach'},
  ],
  'pronunciation': [
    {'word': '제안', 'tip': 'je-an, two clear syllables'},
  ],
  'next_topic': '',
};

void main() {
  setUpAll(() => registerFallbackValue(const LessonOptions()));

  group('LessonModel', () {
    test('펌웨어 JSON을 읽는다', () {
      final l = LessonModel.fromJson(Map<String, dynamic>.from(firmwareJson));
      expect(l.isActive, isTrue);
      expect(l.options, const LessonOptions(course: LessonCourse.biz, explainKorean: true, slow: true, minutes: 5));
      expect(l.remaining, const Duration(seconds: 162));
      expect(l.corrections.single.better, startsWith('다른 방법을 제안드리고 싶습니다.'));
      expect(l.pronunciation.single.word, '제안');
    });

    test('빈 값·모르는 값은 기본값', () {
      final l = LessonModel.fromJson({'state': 'idle', 'course': 'xx', 'minutes': 15});
      expect(l.options.course, LessonCourse.basic);
      expect(l.options.explainKorean, isFalse);
      expect(l.options.toJson()['explain'], 'en');
      expect(l.options.minutes, 5);
      expect(l.corrections, isEmpty);
      expect(l.remaining, isNull);
    });

    test('시작 본문은 펌웨어 키 그대로', () {
      expect(const LessonOptions(course: LessonCourse.adv, explainKorean: false, slow: false, minutes: 3).toJson(),
          {'course': 'adv', 'explain': 'en', 'speed': 'normal', 'minutes': 3});
    });
  });

  group('EnglishCubit', () {
    late MockRepo repo;
    setUp(() {
      repo = MockRepo();
      when(() => repo.savedOptions()).thenReturn(const LessonOptions(course: LessonCourse.daily));
      when(() => repo.saveOptions(any())).thenAnswer((_) async {});
    });

    test('기억해 둔 옵션으로 시작하고, 시작하면 수업을 넘긴다', () async {
      final started = LessonModel.fromJson({'state': 'starting', 'course': 'pron', 'minutes': 5});
      when(() => repo.start(any())).thenAnswer((_) async => Right(started));
      final c = EnglishCubit(repo);
      expect(c.state.options.course, LessonCourse.daily);
      c.select(c.state.options.copyWith(course: LessonCourse.pron));
      await c.start();
      expect(c.state.started, started);
      verify(() => repo.saveOptions(const LessonOptions(course: LessonCourse.pron))).called(1);
      verify(() => repo.start(const LessonOptions(course: LessonCourse.pron))).called(1);
      await c.close();
    });

    test('대화 중이면 실패를 보인다', () async {
      when(() => repo.start(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'VOICE_ACTIVE')));
      final c = EnglishCubit(repo);
      await c.start();
      expect(c.state.failure?.errorKey, ErrorKeys.deviceVoiceActive);
      expect(c.state.starting, isFalse);
      expect(c.state.openAiKey, isNull);
      await c.close();
    });

    test('스피커에 OpenAI 키가 없으면 시작을 잠근다 (Gemini를 써도 수업은 OpenAI)', () async {
      when(() => repo.openAiKeySaved()).thenAnswer((_) async => const Right(false));
      final c = EnglishCubit(repo);
      expect(c.state.canStart, isTrue); // not blocked before it is confirmed
      await c.checkKey();
      expect(c.state.openAiKey, isFalse);
      expect(c.state.canStart, isFalse);
      when(() => repo.openAiKeySaved()).thenAnswer((_) async => const Right(true));
      await c.checkKey();
      expect(c.state.canStart, isTrue);
      await c.close();
    });

    test('키 확인에 실패하면 모르는 채로 (시작 가능), 시작이 409 NO_API_KEY면 잠근다', () async {
      when(() => repo.openAiKeySaved()).thenAnswer((_) async => const Left(NetworkFailure()));
      when(() => repo.start(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'NO_API_KEY')));
      final c = EnglishCubit(repo);
      await c.checkKey();
      expect(c.state.openAiKey, isNull);
      expect(c.state.canStart, isTrue);
      await c.start();
      expect(c.state.failure?.errorKey, ErrorKeys.deviceNoApiKey);
      expect(c.state.canStart, isFalse);
      await c.close();
    });
  });

  group('LessonCubit', () {
    late MockRepo repo;
    late StreamController<Lesson> updates;
    setUp(() {
      repo = MockRepo();
      updates = StreamController<Lesson>.broadcast();
      when(() => repo.updates()).thenAnswer((_) => updates.stream);
      when(() => repo.current()).thenAnswer((_) async => Right(LessonModel.fromJson(Map<String, dynamic>.from(firmwareJson))));
    });

    test('불러오고, WS로 고친 표현이 늘면 바뀐다', () async {
      final c = LessonCubit(repo);
      await c.refresh();
      expect(c.state.lesson?.corrections, hasLength(1));
      final more = Map<String, dynamic>.from(firmwareJson)
        ..['corrections'] = [
          ...(firmwareJson['corrections']! as List),
          {'original': 'Can we delay', 'better': 'Could we push', 'note': ''},
        ];
      updates.add(LessonModel.fromJson(more));
      await Future<void>.delayed(Duration.zero);
      expect(c.state.lesson?.corrections, hasLength(2));
      await c.close();
    });

    test('남은 시간을 화면에서 1초씩 줄인다 (수업 중일 때만)', () async {
      final c = LessonCubit(repo, tick: const Duration(milliseconds: 10));
      await c.refresh();
      final before = c.state.lesson!.remaining!;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(c.state.lesson!.remaining! < before, isTrue);
      updates.add(LessonModel.fromJson({'state': 'summarizing', 'remaining_s': 0}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.state.lesson!.remaining, Duration.zero);
      await c.close();
    });

    test('주제 바꾸기·끝내기 실패는 화면에 알린다', () async {
      when(() => repo.changeTopic()).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'NOT_ACTIVE')));
      when(() => repo.stop()).thenAnswer((_) async => const Right(unit));
      final c = LessonCubit(repo);
      await c.changeTopic();
      expect(c.state.failure, isNotNull);
      await c.stop();
      expect(c.state.failure, isNull);
      verify(() => repo.stop()).called(1);
      await c.close();
    });
  });
}
