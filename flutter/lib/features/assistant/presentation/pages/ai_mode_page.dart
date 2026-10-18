import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/ai/ai_choice.dart';
import '../../../../core/ai/ai_texts.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/send_key_sheet.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../provisioning/domain/entities/provisioning_input.dart';
import '../bloc/ai_mode_cubit.dart';

/// Assistant > AI · Conversation mode (design "AI · Conversation mode"): ① AI (locked if no key or coming soon) → ② that AI's Live / Saver
class AiModePage extends StatelessWidget {
  const AiModePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => sl<AiModeCubit>()..load(), child: const _AiModeView());
  }
}

class _AiModeView extends StatelessWidget {
  const _AiModeView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.aiModeTitle)),
      body: BlocBuilder<AiModeCubit, AiModeState>(
        builder: (context, s) {
          if (s.settings == null) {
            return s.failure != null && !s.loading
                ? FailureView(failure: s.failure!, onRetry: () => context.read<AiModeCubit>().load())
                : const Center(child: CircularProgressIndicator());
          }
          return _Body(state: s);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final AiModeState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = state.provider;
    final heading = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(l.aiPickProvider, style: heading),
        const SizedBox(height: 10),
        Row(children: [
          for (final x in AiProvider.values) ...[
            if (x != AiProvider.values.first) const SizedBox(width: 10),
            Expanded(child: _ProviderCard(provider: x, state: state)),
          ],
        ]),
        for (final x in AiProvider.values)
          if (state.hasKey(x) == false) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.saving ? null : () => _addKey(context, x),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.aiAddKey(x.displayName), textAlign: TextAlign.center),
            ),
          ],
        const SizedBox(height: 22),
        Text(l.aiPickMode(p.displayName), style: heading),
        const SizedBox(height: 10),
        for (final m in const [AiMode.saver, AiMode.live]) ...[
          _ModeCard(provider: p, mode: m, state: state),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        NoticeBox(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${l.aiInfoTitle}\n', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: l.aiInfoBody),
          ])),
        ),
      ],
    );
  }

  Future<void> _addKey(BuildContext context, AiProvider p) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AiModeCubit>();
    final initial = await cubit.rememberedKey(p);
    if (!context.mounted) return;
    final sent = await showSendKeySheet(
      context,
      label: l.aiKeyLabel(p.displayName),
      initial: initial,
      pattern: ProvisioningInput.keyPattern(p),
      invalidText: p == AiProvider.openai ? l.sysKeyInvalidOpenAi : l.aiKeyInvalidGemini,
      onSend: (v) => cubit.sendKey(p, v),
    );
    if (sent && context.mounted) showMessage(context, l.aiKeySent(p.displayName));
  }
}

/// Report the result of a change (a no-key rejection in plain words)
void _report(BuildContext context, Failure? f, AiProvider provider, bool changed) {
  final l = AppLocalizations.of(context);
  if (f == null) {
    if (changed) showMessage(context, l.aiChanged);
  } else if (AiModeCubit.isNoKey(f)) {
    showMessage(context, l.aiNoKeyError(provider.displayName));
  } else {
    showFailure(context, f);
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.state});

  final AiProvider provider;
  final AiModeState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = provider == state.provider;
    final lock = state.providerLock(provider);
    final usable = lock == AiLock.none;
    final note = switch (lock) {
      AiLock.noKey => l.aiKeyMissing,
      AiLock.notReady => l.aiNotReady,
      AiLock.none => l.aiKeyPresent,
    };
    final fg = selected ? scheme.primary : (usable ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.6));
    return Semantics(
      selected: selected,
      enabled: usable,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : (usable ? scheme.surface : scheme.surfaceContainerHighest),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: state.saving ? null : () => _tap(context, lock),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(provider.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(note,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: usable ? (selected ? scheme.primary : scheme.onSurfaceVariant) : scheme.error,
                    )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, AiLock lock) async {
    final l = AppLocalizations.of(context);
    switch (lock) {
      case AiLock.noKey:
        showMessage(context, l.aiNoKeyError(provider.displayName));
      case AiLock.notReady:
        showMessage(context, l.aiNotReadyHint);
      case AiLock.none:
        final cubit = context.read<AiModeCubit>();
        final before = cubit.state.settings;
        final f = await cubit.chooseProvider(provider);
        if (context.mounted) _report(context, f, provider, before != cubit.state.settings);
    }
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.provider, required this.mode, required this.state});

  final AiProvider provider;
  final AiMode mode;
  final AiModeState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = mode == state.settings?.modeOf(provider);
    final usable = state.modeLock(provider, mode) == AiLock.none;
    final muted = usable ? null : scheme.onSurfaceVariant.withValues(alpha: 0.6);
    final tags = [if (!usable) l.aiNotReady, ...l.aiTags(provider, mode)];
    return Semantics(
      selected: selected,
      enabled: usable,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: usable ? scheme.surface : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: state.saving ? null : () => _tap(context, usable),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(l.aiModeName(mode),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: muted)),
                ),
                Text(l.aiPrice(provider, mode),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: muted ?? (mode == AiMode.saver ? scheme.primary : scheme.error),
                    )),
              ]),
              const SizedBox(height: 6),
              Text(l.aiDescription(provider, mode), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in tags)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: usable ? scheme.primaryContainer : scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(t,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: usable ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                          )),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, bool usable) async {
    if (!usable) {
      showMessage(context, AppLocalizations.of(context).aiNotReadyHint);
      return;
    }
    final cubit = context.read<AiModeCubit>();
    final before = cubit.state.settings;
    final f = await cubit.chooseMode(mode);
    if (context.mounted) _report(context, f, provider, before != cubit.state.settings);
  }
}
