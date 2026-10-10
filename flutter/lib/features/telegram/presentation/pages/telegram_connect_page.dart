import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/errors/error_localizer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../bloc/telegram_connect_cubit.dart';
import '../widgets/telegram_widgets.dart';

enum TelegramConnectMode {
  setup, // first time: bot → token → pairing code right after saving
  replaceToken, // replace only the token (chats stay. code when wanted)
  addChat, // one more chat (code only)
}

/// Design "Connect Telegram" (opened from the chats screen to replace the token or add a chat). Closes with true when done
class TelegramConnectPage extends StatelessWidget {
  const TelegramConnectPage({super.key, required this.mode});

  final TelegramConnectMode mode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (mode) {
          TelegramConnectMode.addChat => l.tgAddChatTitle,
          TelegramConnectMode.replaceToken => l.tgReplaceToken,
          TelegramConnectMode.setup => l.tgConnectTitle,
        }),
      ),
      body: TelegramConnectView(mode: mode, onDone: () => Navigator.pop(context, true)),
    );
  }
}

/// Body of the connection steps. TelegramPage shows this directly when there is no token
class TelegramConnectView extends StatelessWidget {
  const TelegramConnectView({super.key, required this.mode, required this.onDone});

  final TelegramConnectMode mode;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = sl<TelegramConnectCubit>();
        if (mode == TelegramConnectMode.addChat) {
          cubit.startPairing();
        } else {
          cubit.init();
        }
        return cubit;
      },
      child: BlocBuilder<TelegramConnectCubit, TelegramConnectState>(
        builder: (context, s) {
          final withToken = mode != TelegramConnectMode.addChat;
          final saved = s.save == TokenSave.saved;
          final finished = mode == TelegramConnectMode.replaceToken ? saved : s.pairing == Pairing.paired;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (withToken) ...[
                _BotFatherCard(done: s.check == TokenCheck.valid),
                const SizedBox(height: 12),
                _TokenCard(mode: mode, state: s),
                const SizedBox(height: 12),
              ],
              _PairingCard(
                number: withToken ? 3 : 1,
                state: s,
                locked: withToken && !saved,
                onDone: onDone,
              ),
              if (finished && mode == TelegramConnectMode.replaceToken) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onDone, child: Text(AppLocalizations.of(context).tgDone)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BotFatherCard extends StatelessWidget {
  const _BotFatherCard({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TgStepCard(
      number: 1,
      title: l.tgStep1Title,
      done: done,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.tgStep1Body, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 14)),
        TextButton.icon(
          onPressed: () => openTelegramLink(context, 'https://t.me/BotFather'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(l.tgOpenBotFather),
        ),
      ]),
    );
  }
}

class _TokenCard extends StatefulWidget {
  const _TokenCard({required this.mode, required this.state});

  final TelegramConnectMode mode;
  final TelegramConnectState state;

  @override
  State<_TokenCard> createState() => _TokenCardState();
}

class _TokenCardState extends State<_TokenCard> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.state.token;
  }

  @override
  void didUpdateWidget(covariant _TokenCard old) {
    super.didUpdateWidget(old);
    // The remembered token was read in late
    if (_controller.text.isEmpty && widget.state.token.isNotEmpty) _controller.text = widget.state.token;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<TelegramConnectCubit>();
    final s = widget.state;
    final saving = s.save == TokenSave.saving;
    final saved = s.save == TokenSave.saved;
    final checking = s.check == TokenCheck.checking;
    return TgStepCard(
      number: 2,
      title: l.tgStep2Title,
      done: saved,
      active: !saved,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscure,
            enabled: !saving,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: l.tgTokenLabel,
              hintText: '123456789:AA…',
              suffixIcon: IconButton(
                tooltip: _obscure ? l.tgTokenShow : l.tgTokenHide,
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
            onChanged: cubit.tokenChanged,
            onSubmitted: (_) => cubit.checkToken(),
          ),
          const SizedBox(height: 10),
          switch (s.check) {
            TokenCheck.idle => const SizedBox.shrink(),
            TokenCheck.checking => TgStatusLine(text: l.tgTokenChecking, busy: true),
            TokenCheck.valid => TgStatusLine(
                text: saved ? l.tgTokenSaved(s.botName) : l.tgTokenValid(s.botName),
                icon: Icons.check_circle_rounded,
                color: Theme.of(context).brightness == Brightness.dark ? scheme.primary : AppColors.ok,
              ),
            TokenCheck.invalid => TgStatusLine(text: l.tgTokenInvalid, icon: Icons.error_outline, color: scheme.error),
            TokenCheck.failed => TgStatusLine(text: l.tgTokenNetwork, icon: Icons.wifi_off_rounded, color: scheme.error),
          },
          if (s.check != TokenCheck.valid) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: s.token.isEmpty || checking ? null : cubit.checkToken,
              child: Text(l.tgCheckToken),
            ),
          ] else if (!saved) ...[
            const SizedBox(height: 12),
            NoticeBox(
              icon: Icons.touch_app_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.bleKey2Hint, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(l.tgKey2Body, style: const TextStyle(fontSize: 13)),
              ]),
            ),
            if (s.save == TokenSave.failed && s.failure != null) ...[
              const SizedBox(height: 10),
              TgStatusLine(text: l.errorText(s.failure!), icon: Icons.error_outline, color: scheme.error),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving
                  ? null
                  : () => cubit.saveToSpeaker(pairAfter: widget.mode == TelegramConnectMode.setup),
              child: saving
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(l.tgSaving, overflow: TextOverflow.ellipsis)),
                    ])
                  : Text(l.tgSaveToSpeaker),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.number, required this.state, required this.locked, required this.onDone});

  final int number;
  final TelegramConnectState state;

  /// Token not yet saved to the speaker
  final bool locked;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<TelegramConnectCubit>();
    final s = state;
    final Widget body;
    if (locked) {
      body = Text(l.tgPairLocked, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 14));
    } else {
      body = switch (s.pairing) {
        Pairing.idle => OutlinedButton(onPressed: cubit.startPairing, child: Text(l.tgPairGetCode)),
        Pairing.requesting => const Center(
            child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
          ),
        Pairing.waiting => _CodeBox(state: s),
        Pairing.expired => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TgStatusLine(text: l.tgPairExpired, icon: Icons.timer_off_outlined, color: scheme.error),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: cubit.startPairing, child: Text(l.tgPairNewCode)),
          ]),
        Pairing.paired => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TgStatusLine(
              text: l.tgPaired(s.pairedChat?.title ?? ''),
              icon: Icons.check_circle_rounded,
              color: Theme.of(context).brightness == Brightness.dark ? scheme.primary : AppColors.ok,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: cubit.startPairing, child: Text(l.tgAddAnother))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(l.tgDone),
                ),
              ),
            ]),
          ]),
        Pairing.noToken => TgStatusLine(text: l.tgPairNoToken, icon: Icons.key_off_outlined, color: scheme.error),
        Pairing.failed => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.failure != null)
              TgStatusLine(text: l.errorText(s.failure!), icon: Icons.error_outline, color: scheme.error),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: cubit.startPairing, child: Text(l.commonRetry)),
          ]),
      };
    }
    return TgStepCard(
      number: number,
      title: l.tgStep3Title,
      done: s.pairing == Pairing.paired,
      active: !locked && s.pairing != Pairing.paired,
      child: body,
    );
  }
}

/// Large code, `/pair code`, time left, copy and open Telegram
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.state});

  final TelegramConnectState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final code = state.code?.code ?? '';
    final bot = state.bot;
    final left = state.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.tgPairBody, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.6)),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Semantics(
                label: code.split('').join(' '),
                excludeSemantics: true,
                child: Text(code,
                    style: GoogleFonts.ibmPlexMono(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: 4)),
              ),
              const SizedBox(height: 6),
              SelectableText('/pair $code', style: GoogleFonts.ibmPlexMono(fontSize: 15)),
              if (bot.isNotEmpty)
                Text(l.tgPairGroupHint(bot, code), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(l.tgPairRemaining(left.inMinutes, left.inSeconds % 60), style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '/pair $code'));
                if (context.mounted) showMessage(context, l.tgCopied);
              },
              child: Text(l.tgCopy),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: bot.isEmpty ? null : () => openTelegramLink(context, 'https://t.me/$bot'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(l.tgOpenTelegram),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TgStatusLine(text: l.tgPairWaiting, busy: true),
      ],
    );
  }
}
