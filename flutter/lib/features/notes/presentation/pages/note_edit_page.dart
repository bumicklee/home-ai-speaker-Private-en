import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/note.dart';
import '../../domain/notes_view.dart';
import '../bloc/notes_cubit.dart';
import 'notes_texts.dart';
import 'notes_widgets.dart';

/// Create/edit a note or event (design "일정 편집"). NotesCubit is passed in from the list screen
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, this.note, this.newKind = NoteKind.event});

  /// null means create new
  final Note? note;
  final NoteKind newKind;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Note? _note;
  late NoteKind _kind;
  late DateTime _date;
  late bool _allDay;
  late TimeOfDay _time;
  late List<int> _remind;

  /// If reminders weren't touched on a new event, don't send remind (speaker's default reminders)
  bool _remindTouched = false;
  bool _titleMissing = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _fill(_note, context.read<NotesCubit>().state.settings);
  }

  void _fill(Note? n, NotesSettings settings) {
    final now = DateTime.now();
    _kind = n?.kind ?? widget.newKind;
    _title.text = n?.title ?? '';
    _body.text = n?.body ?? '';
    final start = n?.start;
    _allDay = start?.allDay ?? false;
    final next = DateTime(now.year, now.month, now.day, now.hour + 1);
    _date = start?.day ?? DateTime(next.year, next.month, next.day);
    _time = start != null && !start.allDay
        ? TimeOfDay(hour: start.at.hour, minute: start.at.minute)
        : TimeOfDay(hour: next.hour, minute: 0);
    _remind = n != null && n.isEvent ? [...n.remind] : _defaults(settings);
    _remindTouched = n != null;
  }

  List<int> _defaults(NotesSettings s) => [...(_allDay ? s.defaultRemindAllDay : s.defaultRemind)];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  NoteDraft _draft() {
    final event = _kind == NoteKind.event;
    final start = !event
        ? null
        : _allDay
            ? NoteTime.date(_date)
            : NoteTime.at(DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute));
    return NoteDraft(
      kind: _kind,
      title: _title.text.trim(),
      body: _body.text.trim(),
      start: start,
      end: event ? _note?.end : null,
      remind: !event ? (_note == null ? null : const []) : (_note == null && !_remindTouched ? null : _remind),
    );
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _titleMissing = true);
      return;
    }
    final cubit = context.read<NotesCubit>();
    final ok = await cubit.save(_note, _draft());
    if (!mounted) return;
    if (ok) {
      showMessage(context, l.notesSaved);
      Navigator.pop(context);
      return;
    }
    // Just changed on the speaker: refill with the latest content (the list screen shows the message)
    final latest = _note == null ? null : cubit.state.byId(_note!.id);
    if (cubit.state.failure?.code == 'CONFLICT' && latest != null) {
      setState(() {
        _note = latest;
        _fill(latest, cubit.state.settings);
      });
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final note = _note;
    if (note == null) return;
    final cubit = context.read<NotesCubit>();
    final ok = await confirm(context,
        title: l.notesDeleteTitle(note.title), body: l.notesDeleteBody, action: l.notesDeleteAction, destructive: true);
    if (!ok || !mounted) return;
    if (await cubit.delete(note) && mounted) {
      showMessage(context, l.notesDeleted);
      Navigator.pop(context);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  void _toggleAllDay(bool on, NotesSettings settings) => setState(() {
        final before = _defaults(settings);
        _allDay = on;
        // If it was still the default, switch to the all-day default
        if (_sameSet(_remind, before)) _remind = _defaults(settings);
      });

  static bool _sameSet(List<int> a, List<int> b) => a.length == b.length && a.toSet().containsAll(b);

  void _toggleRemind(int minutes) => setState(() {
        _remind = toggleRemind(_remind, minutes);
        _remindTouched = true;
      });

  Future<void> _customRemind() async {
    final m = await showCustomRemindDialog(context);
    if (m != null && !_remind.contains(m)) _toggleRemind(m);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<NotesCubit, NotesState>(
      builder: (context, s) {
        final readOnly = s.readOnly;
        final event = _kind == NoteKind.event;
        final heading = _note == null
            ? (event ? l.notesNewEvent : l.notesNewMemo)
            : (event ? l.notesEditEvent : l.notesEditMemo);
        return Scaffold(
          appBar: AppBar(title: Text(heading)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (readOnly) ...[
                NoticeBox(
                  warning: true,
                  icon: Icons.wifi_off_rounded,
                  child: Text(l.notesOffline, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
              ],
              KindChoice(
                labels: [l.notesTabMemos, l.notesTabEvents],
                selected: event ? 1 : 0,
                onChanged: readOnly ? null : (i) => setState(() => _kind = i == 1 ? NoteKind.event : NoteKind.memo),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: Column(children: [
                  TextField(
                    controller: _title,
                    enabled: !readOnly,
                    inputFormatters: [Utf8LengthFormatter(Note.titleMaxBytes)],
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    onChanged: (_) {
                      if (_titleMissing) setState(() => _titleMissing = false);
                    },
                    decoration: InputDecoration(
                      labelText: l.notesFieldTitle,
                      errorText: _titleMissing ? l.notesTitleRequired : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  const Divider(height: 1),
                  TextField(
                    controller: _body,
                    enabled: !readOnly,
                    inputFormatters: [Utf8LengthFormatter(Note.bodyMaxBytes)],
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: l.notesFieldBody,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ]),
              ),
              if (event) ...[
                const SizedBox(height: 12),
                _eventCard(context, s.settings, readOnly),
              ],
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(l.notesEditHint, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              ),
            ],
          ),
          bottomNavigationBar: readOnly
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(children: [
                      if (_note != null) ...[
                        OutlinedButton(
                          onPressed: s.busy ? null : _delete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.35)),
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          child: Text(l.notesDelete),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: s.busy ? null : _save,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                          child: s.busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(l.notesSave, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }

  Widget _eventCard(BuildContext context, NotesSettings settings, bool readOnly) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = _remind.length >= Note.maxReminders;
    final customs = _remind.where((m) => !remindPresets.contains(m)).toList();
    String label(int m) => remindLabel(context, m, allDay: _allDay, allDayTime: settings.allDayTime);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: readOnly ? null : _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(dayText(context, _date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              if (!_allDay)
                TextButton(
                  onPressed: readOnly ? null : _pickTime,
                  child: Text(MaterialLocalizations.of(context).formatTimeOfDay(_time),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
        const Divider(height: 1),
        Row(children: [
          Expanded(child: Text(l.notesAllDay, style: const TextStyle(fontSize: 15))),
          Switch(value: _allDay, onChanged: readOnly ? null : (v) => _toggleAllDay(v, settings)),
        ]),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(child: Text(l.notesRemindLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              Text(full ? l.notesRemindHintMax : l.notesRemindHintMany,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [...remindPresets, ...customs])
                RemindChip(
                  label: label(m),
                  selected: _remind.contains(m),
                  onTap: readOnly || (full && !_remind.contains(m)) ? null : () => _toggleRemind(m),
                ),
              RemindChip(
                label: l.notesRemindCustom,
                selected: false,
                custom: true,
                onTap: readOnly || full ? null : _customRemind,
              ),
            ]),
            const SizedBox(height: 10),
            Text(remindSummary(context, _remind, allDay: _allDay, allDayTime: settings.allDayTime),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
            if (!settings.enabled) ...[
              const SizedBox(height: 4),
              Text(l.notesRemindOff, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5, color: scheme.error)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Custom entry: 1–10080 minutes
Future<int?> showCustomRemindDialog(BuildContext context) {
  final l = AppLocalizations.of(context);
  final ctl = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (c) {
      int? value() {
        final v = int.tryParse(ctl.text.trim());
        return v != null && v >= 1 && v <= Note.maxRemindMinutes ? v : null;
      }

      return StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(l.notesCustomTitle),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(suffixText: l.notesCustomUnit, helperText: l.notesCustomHelp),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(l.commonCancel)),
            TextButton(onPressed: value() == null ? null : () => Navigator.pop(c, value()), child: Text(l.notesCustomAdd)),
          ],
        ),
      );
    },
  ).whenComplete(ctl.dispose);
}

/// Truncates by UTF-8 byte count (speaker title 80 bytes, body 600 bytes)
class Utf8LengthFormatter extends TextInputFormatter {
  Utf8LengthFormatter(this.maxBytes);

  final int maxBytes;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (utf8.encode(newValue.text).length <= maxBytes) return newValue;
    // If pasting etc. overflows it, trim character by character
    final runes = newValue.text.runes.toList();
    var bytes = 0, keep = 0;
    for (final r in runes) {
      final n = utf8.encode(String.fromCharCode(r)).length;
      if (bytes + n > maxBytes) break;
      bytes += n;
      keep++;
    }
    final text = String.fromCharCodes(runes.take(keep));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
