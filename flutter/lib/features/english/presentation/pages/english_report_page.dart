import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/lesson_repository.dart';
import '../../domain/entities/lesson.dart';
import '../bloc/lesson_cubit.dart';
import 'english_texts.dart';

/// Lesson summary (design "Lesson Summary"). Waits until summarizing is done, then shows it
class EnglishReportPage extends StatelessWidget {
  const EnglishReportPage({super.key, this.initial});

  final Lesson? initial;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LessonCubit(sl<LessonRepository>(), initial: initial)..refresh(),
      child: const _ReportView(),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<LessonCubit, LessonState>(
      builder: (context, s) {
        final lesson = s.lesson ?? const Lesson();
        if (lesson.isSummarizing || lesson.isRunning) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.engSummarizing),
              ]),
            ),
          );
        }
        final minutes = ((lesson.elapsed?.inSeconds ?? 0) / 60).ceil();
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primary,
                    child: Icon(Icons.check_rounded, color: theme.colorScheme.onPrimary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.engDoneTitle, style: theme.textTheme.titleLarge?.copyWith(fontSize: 22)),
                      Text(l.engDoneMeta(lesson.options.course.title(l), minutes > 0 ? minutes : lesson.options.minutes),
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(l.engTodayCorrections, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    if (lesson.corrections.isEmpty) Text(l.engNoCorrections),
                    for (var i = 0; i < lesson.corrections.length; i++) ...[
                      if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
                      Text(lesson.corrections[i].better, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                      if (lesson.corrections[i].note.isNotEmpty)
                        Text(lesson.corrections[i].note, style: theme.textTheme.bodySmall),
                    ],
                  ]),
                ),
                if (lesson.pronunciation.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(l.engPractice, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in lesson.pronunciation)
                          Tooltip(
                            message: p.tip,
                            child: Chip(
                              label: Text(p.word),
                              backgroundColor: theme.colorScheme.errorContainer,
                              labelStyle: TextStyle(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
                              side: BorderSide.none,
                            ),
                          ),
                      ]),
                    ]),
                  ),
                ],
                if (lesson.nextTopic.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: theme.colorScheme.primaryContainer,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.engNextTopic,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(lesson.nextTopic, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context), // back to choosing a course to start again
                  child: Text(l.engAgain),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(l.engHome),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
