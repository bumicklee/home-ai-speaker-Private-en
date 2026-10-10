import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';
import 'radio_texts.dart';

/// Rename (only the name field when just [initial] is given) or add directly by URL ([full]). Checked against the firmware limits right away
Future<RadioPreset?> showPresetForm(BuildContext context, {RadioPreset? initial, bool full = false}) =>
    showModalBottomSheet<RadioPreset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PresetForm(initial: initial, full: full),
    );

class _PresetForm extends StatefulWidget {
  const _PresetForm({this.initial, required this.full});

  final RadioPreset? initial;
  final bool full;

  @override
  State<_PresetForm> createState() => _PresetFormState();
}

class _PresetFormState extends State<_PresetForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _url = TextEditingController(text: widget.initial?.url ?? '');
  late final _genre = TextEditingController(text: widget.initial?.genre ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _genre.dispose();
    super.dispose();
  }

  RadioPreset get _value => RadioPreset(
        name: _name.text.trim(),
        url: widget.full ? _url.text.trim() : widget.initial?.url ?? '',
        genre: widget.full ? normalizeGenre(_genre.text) : widget.initial?.genre ?? '',
      );

  void _submit() {
    if (_form.currentState?.validate() ?? false) Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String? check(Set<PresetError> mine) {
      final e = validatePreset(_value);
      return e != null && mine.contains(e) ? l.presetErrorText(e) : null;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.full ? l.radioAddCustom : l.radioRename, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: widget.full ? TextInputAction.next : TextInputAction.done,
              decoration: InputDecoration(labelText: l.radioFormName),
              validator: (_) => check({PresetError.nameEmpty, PresetError.nameTooLong}),
              onFieldSubmitted: widget.full ? null : (_) => _submit(),
            ),
            if (widget.full) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l.radioFormUrl, helperText: l.radioFormUrlHint, helperMaxLines: 2),
                validator: (_) => check({PresetError.urlInvalid, PresetError.urlTooLong}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _genre,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l.radioFormGenre, helperText: l.radioFormGenreHint),
                validator: (_) => check({PresetError.genreTooLong}),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: Text(widget.full ? l.radioFormAdd : l.commonOk)),
          ],
        ),
      ),
    );
  }
}
