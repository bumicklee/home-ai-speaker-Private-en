import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/note.dart';
import '../../domain/notes_view.dart';
import '../bloc/notes_cubit.dart';
import 'note_edit_page.dart';
import 'notes_settings_page.dart';
import 'notes_texts.dart';
import 'notes_widgets.dart';

/// Notes and schedule list (design "메모·일정"): search, schedule/notes/trash tabs, create new
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => sl<NotesCubit>()..load(), child: const _NotesView());
  }
}

class _NotesView extends StatefulWidget {
  const _NotesView();

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  int _tab = 0; // 0 schedule, 1 notes, 2 trash

  void _open(BuildContext context, {Note? note, NoteKind kind = NoteKind.event}) {
    final cubit = context.read<NotesCubit>();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => BlocProvider.value(value: cubit, child: NoteEditPage(note: note, newKind: kind))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocConsumer<NotesCubit, NotesState>(
      listenWhen: (a, b) => a.failure != b.failure && b.failure != null,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, s) {
        final cubit = context.read<NotesCubit>();
        final now = DateTime.now();
        final found = s.items.where((n) => matchesQuery(n, s.query)).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(l.notesTitle),
            actions: [
              IconButton(
                tooltip: l.notesSettingsTitle,
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => BlocProvider.value(value: cubit, child: const NotesSettingsPage())),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          floatingActionButton: s.readOnly
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _open(context, kind: _tab == 1 ? NoteKind.memo : NoteKind.event),
                  icon: const Icon(Icons.add),
                  label: Text(l.notesNew),
                ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(children: [
                TextField(
                  onChanged: cubit.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.notesSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentTabs(
                  labels: [l.notesTabEvents, l.notesTabMemos, l.notesTabTrash],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ]),
            ),
            if (s.syncing && s.items.isEmpty) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: cubit.sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (s.offline) ...[
                      NoticeBox(
                        warning: true,
                        icon: Icons.wifi_off_rounded,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.notesOffline, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(l.notesOfflineBody),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...switch (_tab) {
                      0 => _events(context, s, found, now),
                      1 => _memos(context, s, found, now),
                      _ => _trash(context, s, found, now),
                    },
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.notesVoiceHint, style: theme.textTheme.bodySmall?.copyWith(height: 1.55)),
                        const SizedBox(height: 6),
                        Text(l.notesPrivacy, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.5)),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _empty(BuildContext context, NotesState s, String text) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(s.query.trim().isNotEmpty ? l.notesNoMatch : text,
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  List<Widget> _events(BuildContext context, NotesState s, List<Note> found, DateTime now) {
    final groups = groupEvents(found, now);
    if (groups.isEmpty) return [if (s.loaded) _empty(context, s, AppLocalizations.of(context).notesEmptyEvents)];
    return [
      for (final g in groups) ...[
        SectionTitle(groupTitle(context, g)),
        ListGroup(children: [
          for (final n in g.items)
            _EventRow(note: n, settings: s.settings, now: now, onTap: () => _open(context, note: n)),
        ]),
        const SizedBox(height: 6),
      ],
    ];
  }

  List<Widget> _memos(BuildContext context, NotesState s, List<Note> found, DateTime now) {
    final memos = sortedMemos(found);
    if (memos.isEmpty) return [if (s.loaded) _empty(context, s, AppLocalizations.of(context).notesEmptyMemos)];
    return [
      ListGroup(children: [
        for (final n in memos) _MemoRow(note: n, now: now, onTap: () => _open(context, note: n)),
      ]),
    ];
  }

  List<Widget> _trash(BuildContext context, NotesState s, List<Note> found, DateTime now) {
    final l = AppLocalizations.of(context);
    final trash = sortedTrash(found);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(l.notesTrashInfo, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
      ),
      if (trash.isEmpty)
        _empty(context, s, l.notesEmptyTrash)
      else
        ListGroup(children: [
          for (final n in trash) _TrashRow(note: n, now: now, readOnly: s.readOnly || s.busy),
        ]),
    ];
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.note, required this.settings, required this.now, required this.onTap});

  final Note note;
  final NotesSettings settings;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = note.start!;
    final badge = badgeOf(note, now, settings.allDayTime);
    final badgeLabel = badgeText(l, badge);
    final time = start.allDay
        ? l.notesAllDay
        : MaterialLocalizations.of(context)
            .formatTimeOfDay(TimeOfDay(hour: start.at.hour, minute: start.at.minute), alwaysUse24HourFormat: true);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            SizedBox(
              width: 58,
              child: Text(time,
                  style: TextStyle(
                      fontSize: start.allDay ? 13 : 15, fontWeight: FontWeight.w700, color: scheme.primary)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(note.remind.isEmpty ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      remindList(context, note.remind, allDay: start.allDay, allDayTime: settings.allDayTime),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                    ),
                  ),
                ]),
              ]),
            ),
            if (badgeLabel != null) ...[
              const SizedBox(width: 8),
              _Badge(label: badgeLabel, colors: badgeColors(context, badge)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colors});

  final String label;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: colors.$2, borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.$1)),
        ),
      );
}

class _MemoRow extends StatelessWidget {
  const _MemoRow({required this.note, required this.now, required this.onTap});

  final Note note;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (note.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(note.body,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Text(memoWhen(context, note, now), style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({required this.note, required this.now, required this.readOnly});

  final Note note;
  final DateTime now;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<NotesCubit>();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(l.notesTrashLeft(trashDaysLeft(note, now)), style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: readOnly
                ? null
                : () async {
                    if (await cubit.restore(note) && context.mounted) showMessage(context, l.notesRestored);
                  },
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Text(l.notesRestore),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            tooltip: l.notesDeleteForever,
            onPressed: readOnly
                ? null
                : () async {
                    final ok = await confirm(context,
                        title: l.notesDeleteTitle(note.title),
                        body: l.notesDeleteBody,
                        action: l.notesDeleteAction,
                        destructive: true);
                    if (ok && await cubit.delete(note) && context.mounted) showMessage(context, l.notesDeleted);
                  },
            icon: Icon(Icons.delete_outline_rounded, color: readOnly ? null : theme.colorScheme.error),
          ),
        ]),
      ),
    );
  }
}
