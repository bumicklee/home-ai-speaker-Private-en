import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/lesson.dart';

/// Course names, descriptions, levels (design order: pronunciation → basics → daily life → business → advanced)
extension LessonCourseText on LessonCourse {
  String title(AppLocalizations l) => switch (this) {
        LessonCourse.pron => l.engCoursePron,
        LessonCourse.basic => l.engCourseBasic,
        LessonCourse.daily => l.engCourseDaily,
        LessonCourse.biz => l.engCourseBiz,
        LessonCourse.adv => l.engCourseAdv,
      };

  String description(AppLocalizations l) => switch (this) {
        LessonCourse.pron => l.engCoursePronDesc,
        LessonCourse.basic => l.engCourseBasicDesc,
        LessonCourse.daily => l.engCourseDailyDesc,
        LessonCourse.biz => l.engCourseBizDesc,
        LessonCourse.adv => l.engCourseAdvDesc,
      };

  String level(AppLocalizations l) => switch (this) {
        LessonCourse.pron => l.engLevelAll,
        LessonCourse.basic => l.engLevelBeginner,
        LessonCourse.daily => l.engLevelEasy,
        LessonCourse.biz => l.engLevelMid,
        LessonCourse.adv => l.engLevelAdvanced,
      };

  /// The single character in the icon slot (design). A Hangul syllable is one character = one UTF-16 unit
  String badge(AppLocalizations l) => title(l).substring(0, 1);
}

String formatRemaining(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
