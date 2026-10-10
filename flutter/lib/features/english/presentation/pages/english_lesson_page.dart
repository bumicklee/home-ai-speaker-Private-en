import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/lesson_repository.dart';
import '../../domain/entities/lesson.dart';
import '../bloc/lesson_cubit.dart';
import 'english_report_page.dart';
import 'english_texts.dart';

/// During the lesson (design "In Lesson": free talking + expressions the tutor corrected)
class EnglishLessonPage extends StatelessWidget {
  const EnglishLessonPage({super.key, this.initial});

  final Lesson? initial;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LessonCubit(sl<LessonRepository>(), initial: initial)..refresh(),
      child: const _LessonView(),
    );
  }
}

class _LessonView extends StatelessWidget {
  const _LessonView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocConsumer<LessonCubit, LessonState>(
      listenWhen: (a, b) => a.failure != b.failure || a.lesson?.state != b.lesson?.state,
      listener: (context, s) {
        if (s.failure != null) showFailure(context, s.failure!);
        final lesson = s.lesson;
        if (lesson == null) return;
        if (lesson.isSummarizing || lesson.isDone) {
          // When the lesson ends, go to the summary screen (go even while it is summarizing, and wait there)
          Navigator.pushReplacement(
              context, MaterialPageRoute<void>(builder: (_) => EnglishReportPage(initial: lesson)));
        } else if (lesson.state == 'idle') {
          // The lesson session did not open (connection failure etc.): back to the course screen
          Navigator.pop(context);
        }
      },
      builder: (context, s) {
        final lesson = s.lesson ?? const Lesson(state: 'starting');
        final cubit = context.read<LessonCubit>();
        final course = lesson.options.course.title(l);
        final starting = !lesson.isActive;
        return Scaffold(
          appBar: AppBar(title: Text(l.engLessonTitle)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(l.engFreeTalk(course),
                            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFD6F0EE), fontWeight: FontWeight.w600)),
                      ),
                      if (lesson.remaining != null)
                        DecoratedBox(
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            child: Text(l.engRemaining(formatRemaining(lesson.remaining!)),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      if (starting)
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      else
                        const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 30),
                      const SizedBox(width: 12),
                      Text(starting ? l.engStarting : l.engListening,
                          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontSize: 22)),
                    ]),
                    const SizedBox(height: 8),
                    Text(l.engListeningBody, style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFD6F0EE))),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.engTopic, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(lesson.topic.isEmpty ? l.engTopicUnknown : lesson.topic, style: theme.textTheme.titleMedium),
                    ]),
                  ),
                  OutlinedButton(
                    onPressed: lesson.isActive && !s.busy ? cubit.changeTopic : null,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(44, 40)),
                    child: Text(l.engChangeTopic),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              _CorrectionsCard(lesson: lesson),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: s.busy ? null : cubit.stop,
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.onSurface, foregroundColor: theme.colorScheme.surface),
                child: Text(l.engEnd),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Corrected expressions + pronunciation tips (also used on the summary screen)
class _CorrectionsCard extends StatelessWidget {
  const _CorrectionsCard({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = <Widget>[
      for (final c in lesson.corrections)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.original,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error, decoration: TextDecoration.lineThrough, fontSize: 14)),
          const SizedBox(height: 2),
          Text(c.better, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
          if (c.note.isNotEmpty) Text(c.note, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
        ]),
      for (final p in lesson.pronunciation)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DecoratedBox(
            decoration: BoxDecoration(color: theme.colorScheme.error, borderRadius: BorderRadius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(l.engPronunciationBadge,
                  style: TextStyle(color: theme.colorScheme.onError, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: p.word, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (p.tip.isNotEmpty) TextSpan(text: ' — ${p.tip}'),
            ])),
          ),
        ]),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.engCorrections, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (items.isEmpty) Text(l.engCorrectionsEmpty, style: theme.textTheme.bodySmall),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
          items[i],
        ],
      ]),
    );
  }
}
