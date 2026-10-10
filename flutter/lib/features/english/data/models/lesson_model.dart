import '../../domain/entities/lesson.dart';

/// Firmware lesson_json() → Lesson
class LessonModel {
  static Lesson fromJson(Map<String, dynamic> j) {
    final minutes = (j['minutes'] as num?)?.toInt() ?? 5;
    return Lesson(
      state: j['state'] as String? ?? 'idle',
      options: LessonOptions(
        course: LessonCourse.fromId(j['course'] as String?),
        explainKorean: (j['explain'] as String? ?? 'ko') == 'ko',
        slow: (j['speed'] as String? ?? 'slow') == 'slow',
        minutes: LessonOptions.allowedMinutes.contains(minutes) ? minutes : 5,
      ),
      elapsed: j['elapsed_s'] is num ? Duration(seconds: (j['elapsed_s'] as num).toInt()) : null,
      remaining: j['remaining_s'] is num ? Duration(seconds: (j['remaining_s'] as num).toInt()) : null,
      topic: j['topic'] as String? ?? '',
      corrections: [
        for (final c in (j['corrections'] as List<dynamic>? ?? const []))
          if (c is Map<String, dynamic>)
            LessonCorrection(
              original: c['original'] as String? ?? '',
              better: c['better'] as String? ?? '',
              note: c['note'] as String? ?? '',
            ),
      ],
      pronunciation: [
        for (final p in (j['pronunciation'] as List<dynamic>? ?? const []))
          if (p is Map<String, dynamic>) LessonPronunciation(word: p['word'] as String? ?? '', tip: p['tip'] as String? ?? ''),
      ],
      nextTopic: j['next_topic'] as String? ?? '',
    );
  }
}
