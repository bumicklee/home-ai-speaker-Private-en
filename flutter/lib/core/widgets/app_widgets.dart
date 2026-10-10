/// Shared widgets from the design. Feature screens are assembled from these (don't rebuild the look on every screen).
library;

import 'package:flutter/material.dart';

import '../errors/error_localizer.dart';
import '../errors/failures.dart';
import '../../l10n/app_localizations.dart';

/// White card (corner radius 16)
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: border == null ? null : Border.fromBorderSide(border!),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Section title (small gray text)
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(children: [Expanded(child: Text(text, style: style)), ?trailing]),
    );
  }
}

/// List group inside a card (dividers between rows)
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One list row (height 56 or more)
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap, this.selected = false});

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: trailing == null ? 16 : 4, top: 8, bottom: 8),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? theme.colorScheme.primary : null,
                          )),
                      if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch row
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Title + value + slider
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.valueText,
    this.onChanged,
    this.onChangeEnd,
    this.minLabel,
    this.maxLabel,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueText;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? minLabel;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14))),
          Text(valueText, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        if (minLabel != null || maxLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text(minLabel ?? '', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
              const Spacer(),
              Text(maxLabel ?? '', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
            ]),
          ),
      ],
    );
  }
}

/// First-time setup step bar (step current of n, starting at 1)
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$total / $current',
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? scheme.primary : scheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Notice box (info: teal background, warning: amber background)
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.child, this.warning = false, this.icon});

  final Widget child;
  final bool warning;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = warning ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? (warning ? Icons.warning_amber_rounded : Icons.info_outline), color: fg, size: 22),
            const SizedBox(width: 12),
            Expanded(child: DefaultTextStyle.merge(style: TextStyle(color: scheme.onSurface, height: 1.6), child: child)),
          ],
        ),
      ),
    );
  }
}

/// Status dot (connected, etc.)
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Load failure view (try again)
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(l.errorText(failure), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(l.commonRetry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Show a failure as a snackbar
void showFailure(BuildContext context, Failure failure) {
  final l = AppLocalizations.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l.errorText(failure))));
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Confirmation dialog (destructive for dangerous actions)
Future<bool> confirm(BuildContext context,
    {required String title, String? body, required String action, bool destructive = false}) async {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.commonCancel)),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: scheme.error) : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
