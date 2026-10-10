import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/lesson.dart';
import '../bloc/english_cubit.dart';
import 'english_lesson_page.dart';
import 'english_texts.dart';

/// English Tutor: choosing a course (design "English Tutor: Choose a Course")
class EnglishPage extends StatelessWidget {
  const EnglishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => sl<EnglishCubit>()..checkKey(), child: const _EnglishView());
  }
}

class _EnglishView extends StatelessWidget {
  const _EnglishView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocConsumer<EnglishCubit, EnglishState>(
      listenWhen: (a, b) => a.started != b.started || a.failure != b.failure,
      listener: (context, s) {
        if (s.failure != null) showFailure(context, s.failure!);
        final started = s.started;
        if (started != null) {
          context.read<EnglishCubit>().consumeStarted();
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => EnglishLessonPage(initial: started)));
        }
      },
      builder: (context, s) {
        final cubit = context.read<EnglishCubit>();
        final o = s.options;
        return Scaffold(
          appBar: AppBar(title: Text(l.engTitle)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(l.engIntro, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              for (final c in LessonCourse.values) ...[
                _CourseCard(course: c, selected: c == o.course, onTap: () => cubit.select(o.copyWith(course: c))),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(children: [
                  _ChoiceRow<bool>(
                    label: l.engExplain,
                    value: o.explainKorean,
                    options: {true: l.engExplainKorean, false: l.engExplainEnglish},
                    onChanged: (v) => cubit.select(o.copyWith(explainKorean: v)),
                  ),
                  const SizedBox(height: 10),
                  _ChoiceRow<bool>(
                    label: l.engSpeed,
                    value: o.slow,
                    options: {true: l.engSpeedSlow, false: l.engSpeedNormal},
                    onChanged: (v) => cubit.select(o.copyWith(slow: v)),
                  ),
                  const SizedBox(height: 10),
                  _ChoiceRow<int>(
                    label: l.engLength,
                    value: o.minutes,
                    options: {for (final m in LessonOptions.allowedMinutes) m: l.engMinutes(m)},
                    onChanged: (v) => cubit.select(o.copyWith(minutes: v)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(l.engCostNote, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s.openAiKey == false) ...[
                  // English lessons always use OpenAI Live (design docs/design-voice-saver-mode.md Section 9, item 2)
                  NoticeBox(warning: true, icon: Icons.key_off_rounded, child: Text(l.engNeedOpenAiKey)),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: s.canStart ? cubit.start : null,
                  icon: s.starting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(l.engStart(o.course.title(l))),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: l.engRealtimeNote),
                    TextSpan(text: '\n${l.engVoiceHint}'),
                  ]),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.selected, required this.onTap});

  final LessonCourse course;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(course.badge(l),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(course.title(l), style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                    Text(course.description(l), style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
                  ]),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    child: Text(course.level(l), style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label + picking one of a few buttons
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.value, required this.options, required this.onChanged});

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      SizedBox(width: 74, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13))),
      Expanded(
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 44), visualDensity: VisualDensity.standard),
          segments: [for (final e in options.entries) ButtonSegment<T>(value: e.key, label: Text(e.value))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    ]);
  }
}
