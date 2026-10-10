import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';
import '../bloc/radio_cubit.dart';
import '../widgets/preset_form_sheet.dart';
import '../widgets/radio_texts.dart';
import 'radio_page.dart';

/// Preset editing: drag to reorder, rename, delete, add by URL. Saving sends the whole list with PUT
class PresetEditPage extends StatefulWidget {
  const PresetEditPage({super.key});

  @override
  State<PresetEditPage> createState() => _PresetEditPageState();
}

class _PresetEditPageState extends State<PresetEditPage> {
  late List<RadioPreset> _items = List.of(context.read<RadioCubit>().state.presets);

  /// Key for dragging (different per row even when URLs repeat)
  late List<int> _keys = List.generate(_items.length, (i) => i);
  late int _nextKey = _items.length;

  bool get _dirty {
    final saved = context.read<RadioCubit>().state.presets;
    if (saved.length != _items.length) return true;
    for (var i = 0; i < saved.length; i++) {
      if (saved[i] != _items[i]) return true;
    }
    return false;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final ok = await context.read<RadioCubit>().savePresets(_items);
    if (!mounted || !ok) return;
    showMessage(context, l.radioSaved);
    Navigator.pop(context);
  }

  Future<void> _rename(int i) async {
    final p = await showPresetForm(context, initial: _items[i]);
    if (p != null && mounted) setState(() => _items = List.of(_items)..[i] = p);
  }

  Future<void> _delete(int i) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.radioDeleteTitle(_items[i].name), action: l.radioDelete, destructive: true);
    if (ok && mounted) {
      setState(() {
        _items = List.of(_items)..removeAt(i);
        _keys = List.of(_keys)..removeAt(i);
      });
    }
  }

  Future<void> _addCustom() async {
    final l = AppLocalizations.of(context);
    if (_items.length >= RadioLimits.maxPresets) {
      showMessage(context, l.presetErrorText(PresetError.tooMany));
      return;
    }
    final p = await showPresetForm(context, full: true);
    if (p == null || !mounted) return;
    if (_items.any((x) => x.url == p.url)) {
      showMessage(context, l.presetErrorText(PresetError.duplicate));
      return;
    }
    setState(() {
      _items = [..._items, p];
      _keys = [..._keys, _nextKey++];
    });
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    if (await confirm(context, title: l.radioDiscardTitle, action: l.radioDiscard, destructive: true)) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = context.select<RadioCubit, bool>((c) => c.state.busy);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.radioEditTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(onPressed: busy || !_dirty ? null : _save, child: Text(l.radioSave)),
            ),
          ],
        ),
        body: RadioMessages(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(l.radioEditHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              SectionTitle(l.radioCount(_items.length, RadioLimits.maxPresets)),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _items.length,
                    onReorder: (from, to) => setState(() {
                      _items = _moved(_items, from, to);
                      _keys = _moved(_keys, from, to);
                    }),
                    itemBuilder: (context, i) => _EditRow(
                      key: ValueKey(_keys[i]),
                      index: i,
                      preset: _items[i],
                      divider: i > 0,
                      onRename: () => _rename(i),
                      onDelete: () => _delete(i),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : _addCustom,
                icon: const Icon(Icons.add_link_rounded),
                label: Text(l.radioAddCustom),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// onReorder of ReorderableListView: when moving down, [to] arrives one larger
List<T> _moved<T>(List<T> list, int from, int to) {
  final out = List.of(list);
  final item = out.removeAt(from);
  out.insert(to > from ? to - 1 : to, item);
  return out;
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.preset,
    required this.divider,
    required this.onRename,
    required this.onDelete,
  });

  final int index;
  final RadioPreset preset;
  final bool divider;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tags = preset.displayTags;
    return Material(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (divider) const Divider(height: 1, indent: 16),
          ListRow(
            title: preset.name,
            subtitle: tags.isEmpty ? null : tags.join(' · '),
            onTap: onRename,
            leading: ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 32,
                height: 44,
                child: Icon(Icons.drag_indicator_rounded, color: scheme.onSurfaceVariant),
              ),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: l.radioRename, onPressed: onRename, icon: const Icon(Icons.edit_outlined)),
              IconButton(
                tooltip: l.radioDelete,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
