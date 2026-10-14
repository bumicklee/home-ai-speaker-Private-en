import 'package:equatable/equatable.dart';

/// Course (same ids as COURSE_IDS in firmware lesson.c)
enum LessonCourse {
  pron('pron'),
  basic('basic'),
  daily('daily'),
  biz('biz'),
  adv('adv');

  const LessonCourse(this.id);
  final String id;

  static LessonCourse fromId(String? id) => values.firstWhere((c) => c.id == id, orElse: () => basic);
}

/// Lesson start settings
class LessonOptions extends Equatable {
  const LessonOptions({this.course = LessonCourse.basic, this.explainKorean = false, this.slow = true, this.minutes = 5});

  final LessonCourse course;

  /// true = "explain":"ko" (Korean only), false = "explain":"en" (mix in English when stuck, default)
  final bool explainKorean;
  final bool slow;

  /// 10, 20, 30
  final int minutes;

  /// At most 5 minutes because of cost (2026-10-04). The firmware also accepts only 3 and 5
  static const allowedMinutes = [3, 5];

  Map<String, Object> toJson() => {
        'course': course.id,
        'explain': explainKorean ? 'ko' : 'en',
        'speed': slow ? 'slow' : 'normal',
        'minutes': minutes,
      };

  LessonOptions copyWith({LessonCourse? course, bool? explainKorean, bool? slow, int? minutes}) => LessonOptions(
        course: course ?? this.course,
        explainKorean: explainKorean ?? this.explainKorean,
        slow: slow ?? this.slow,
        minutes: minutes ?? this.minutes,
      );

  @override
  List<Object?> get props => [course, explainKorean, slow, minutes];
}

class LessonCorrection extends Equatable {
  const LessonCorrection({required this.original, required this.better, this.note = ''});
  final String original;
  final String better;
  final String note;
  @override
  List<Object?> get props => [original, better, note];
}

class LessonPronunciation extends Equatable {
  const LessonPronunciation({required this.word, this.tip = ''});
  final String word;
  final String tip;
  @override
  List<Object?> get props => [word, tip];
}

/// GET /api/v1/lesson, WS `lesson`
class Lesson extends Equatable {
  const Lesson({
    this.state = 'idle',
    this.options = const LessonOptions(),
    this.elapsed,
    this.remaining,
    this.topic = '',
    this.corrections = const [],
    this.pronunciation = const [],
    this.nextTopic = '',
  });

  /// idle / waiting / starting / active / summarizing / done
  final String state;
  final LessonOptions options;
  final Duration? elapsed;
  final Duration? remaining;
  final String topic;
  final List<LessonCorrection> corrections;
  final List<LessonPronunciation> pronunciation;
  final String nextTopic;

  bool get isRunning => state == 'waiting' || state == 'starting' || state == 'active';
  bool get isActive => state == 'active';
  bool get isSummarizing => state == 'summarizing';
  bool get isDone => state == 'done';

  Lesson copyWith({Duration? remaining}) => Lesson(
        state: state,
        options: options,
        elapsed: elapsed,
        remaining: remaining ?? this.remaining,
        topic: topic,
        corrections: corrections,
        pronunciation: pronunciation,
        nextTopic: nextTopic,
      );

  @override
  List<Object?> get props => [state, options, elapsed, remaining, topic, corrections, pronunciation, nextTopic];
}
