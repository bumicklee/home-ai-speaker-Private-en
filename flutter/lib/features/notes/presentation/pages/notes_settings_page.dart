import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/note.dart';
import '../../domain/notes_view.dart';
import '../bloc/notes_cubit.dart';
import 'notes_texts.dart';
import 'notes_widgets.dart';

/// Schedule reminder settings (design "Event reminders"): on/off, default reminders, all-day reminder time. Changes save to the speaker immediately
class NotesSettingsPage extends StatelessWidget {
  const NotesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<NotesCubit, NotesState>(
      builder: (context, s) {
        final cubit = context.read<NotesCubit>();
        final set = s.settings;
        final editable = !s.readOnly;
        final defaults = editable && set.enabled;
        Widget chips(List<int> selected, List<(int, String)> options, void Function(List<int>) onChanged) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (m, label) in options)
                  RemindChip(
                    label: label,
                    selected: selected.contains(m),
                    onTap: !defaults || (selected.length >= Note.maxReminders && !selected.contains(m))
                        ? null
                        : () => onChanged(toggleRemind(selected, m)),
                  ),
              ],
            );
        return Scaffold(
          appBar: AppBar(title: Text(l.notesSettingsTitle)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (s.readOnly) ...[
                NoticeBox(
                  warning: true,
                  icon: Icons.wifi_off_rounded,
                  child: Text(l.notesOffline, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
              ],
              ListGroup(children: [
                SwitchRow(
                  title: l.notesSettingsEnabled,
                  subtitle: l.notesSettingsEnabledSub,
                  value: set.enabled,
                  onChanged: editable ? (v) => cubit.saveSettings(set.copyWith(enabled: v)) : null,
                ),
              ]),
              const SizedBox(height: 6),
              Opacity(
                opacity: set.enabled ? 1 : 0.4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionTitle(l.notesSettingsDefaults),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.notesSettingsTimed, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      chips(
                        set.defaultRemind,
                        [for (final m in remindPresets) (m, remindLabel(context, m, allDay: false, allDayTime: set.allDayTime))],
                        (v) => cubit.saveSettings(set.copyWith(defaultRemind: v)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.notesSettingsAllDay, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      chips(
                        set.defaultRemindAllDay,
                        [(0, l.notesSettingsSameMorning), (1440, l.notesSettingsDayBeforeMorning)],
                        (v) => cubit.saveSettings(set.copyWith(defaultRemindAllDay: v)),
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: Text(l.notesSettingsAllDayTime, style: const TextStyle(fontSize: 14.5))),
                        OutlinedButton(
                          onPressed: !defaults
                              ? null
                              : () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(hour: set.allDayTime.hour, minute: set.allDayTime.minute),
                                  );
                                  if (t != null) await cubit.saveSettings(set.copyWith(allDayTime: ClockTime(t.hour, t.minute)));
                                },
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                          child: Text(clockText(context, set.allDayTime),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              AppCard(
                color: theme.colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.notesSettingsInfoTitle,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  Text(l.notesSettingsInfo, style: const TextStyle(fontSize: 13, height: 1.55)),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
