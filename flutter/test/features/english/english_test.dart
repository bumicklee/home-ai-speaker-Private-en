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
    {
      'original': 'dareun bangbeop malhago sipeoyo',
      'better': 'dareun bangbeobeul jeandeurigo sipseumnida — I would like to suggest a different approach',
      'note': 'More polite for a meeting',
    },
  ],
  'pronunciation': [
    {'word': 'gamsahamnida', 'tip': 'the b before n sounds like m'},
  ],
  'next_topic': '',
};

void main() {
  setUpAll(() => registerFallbackValue(const LessonOptions()));

  group('LessonModel', () {
    test('reads the firmware JSON', () {
      final l = LessonModel.fromJson(Map<String, dynamic>.from(firmwareJson));
      expect(l.isActive, isTrue);
      expect(l.options, const LessonOptions(course: LessonCourse.biz, explainKorean: true, slow: true, minutes: 5));
      expect(l.remaining, const Duration(seconds: 162));
      expect(l.corrections.single.better, startsWith('dareun bangbeobeul jeandeurigo sipseumnida'));
      expect(l.pronunciation.single.word, 'gamsahamnida');
    });

    test('empty or unknown values fall back to defaults', () {
      final l = LessonModel.fromJson({'state': 'idle', 'course': 'xx', 'minutes': 15});
      expect(l.options.course, LessonCourse.basic);
      expect(l.options.explainKorean, isFalse);
      expect(l.options.toJson()['explain'], 'en');
      expect(l.options.minutes, 5);
      expect(l.corrections, isEmpty);
      expect(l.remaining, isNull);
    });

    test('start body uses the firmware keys as is', () {
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

    test('starts from the remembered options and hands over the lesson once started', () async {
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

    test('shows a failure while a conversation is active', () async {
      when(() => repo.start(any())).thenAnswer((_) async => Left(DeviceFailure.fromStatus(409, 'VOICE_ACTIVE')));
      final c = EnglishCubit(repo);
      await c.start();
      expect(c.state.failure?.errorKey, ErrorKeys.deviceVoiceActive);
      expect(c.state.starting, isFalse);
      expect(c.state.openAiKey, isNull);
      await c.close();
    });

    test('locks start when the speaker has no OpenAI key (lessons use OpenAI even with Gemini)', () async {
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

    test('if the key check fails it stays unknown (can start); locks on a 409 NO_API_KEY start', () async {
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

    test('loads, then updates when WS adds a correction', () async {
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

    test('counts the remaining time down each second on screen (only while active)', () async {
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

    test('shows change-topic and stop failures on screen', () async {
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
