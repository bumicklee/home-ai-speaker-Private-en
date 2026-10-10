/// Input parts for the assistant screens: byte-limited input, text edit dialog, single-choice sheet
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/assistant_settings.dart';

/// Truncates by UTF-8 byte count (the firmware limit is in bytes, not characters)
class Utf8LengthLimitingFormatter extends TextInputFormatter {
  Utf8LengthLimitingFormatter(this.maxBytes);

  final int maxBytes;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (utf8Bytes(newValue.text) <= maxBytes) return newValue;
    // Don't block while Hangul is being composed (it is checked again when composition ends)
    if (newValue.composing.isValid) return newValue;
    return oldValue;
  }
}

/// Byte-counting character counter + error text when over
String? byteError(AppLocalizations l, String text, int max) =>
    utf8Bytes(text) > max ? l.asstTooLong(max) : null;

/// Edit one text field. null if cancelled
Future<String?> editText(
  BuildContext context, {
  required String title,
  required String initial,
  required int maxBytes,
  String? hint,
  String? helper,
  bool multiline = false,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      initial: initial,
      maxBytes: maxBytes,
      hint: hint,
      helper: helper,
      multiline: multiline,
      required: required,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.maxBytes,
    this.hint,
    this.helper,
    required this.multiline,
    required this.required,
  });

  final String title;
  final String initial;
  final int maxBytes;
  final String? hint;
  final String? helper;
  final bool multiline;
  final bool required;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final value = _text.text;
    final empty = widget.required && value.trim().isEmpty;
    final error = byteError(l, value, widget.maxBytes) ?? (empty && value.isNotEmpty ? l.asstNameEmpty : null);
    final ok = error == null && !empty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: widget.multiline ? 4 : 1,
          maxLines: widget.multiline ? 8 : 1,
          keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
          textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
          inputFormatters: [Utf8LengthLimitingFormatter(widget.maxBytes)],
          onSubmitted: widget.multiline || !ok ? null : (_) => Navigator.pop(context, value),
          decoration: InputDecoration(
            hintText: widget.hint,
            helperText: widget.helper,
            errorText: error,
            counterText: l.asstBytes(utf8Bytes(value), widget.maxBytes),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        TextButton(onPressed: ok ? () => Navigator.pop(context, value) : null, child: Text(l.commonOk)),
      ],
    );
  }
}

/// Pick one from a list (checkmark on the selected one). null if cancelled
Future<T?> pickOne<T>(
  BuildContext context, {
  required String title,
  String? note,
  required List<T> options,
  required T selected,
  required String Function(T) label,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (note != null) Text(note, style: theme.textTheme.bodySmall),
                ]),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final o in options)
                      ListTile(
                        minTileHeight: 52,
                        title: Text(label(o)),
                        trailing: o == selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                        selected: o == selected,
                        onTap: () => Navigator.pop(context, o),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
