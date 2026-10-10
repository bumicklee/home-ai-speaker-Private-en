import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/telegram.dart';
import '../bloc/telegram_cubit.dart';
import '../widgets/telegram_widgets.dart';
import 'telegram_connect_page.dart';

/// Telegram (route `/telegram`). Connection steps if the speaker has no bot token, otherwise the chats screen (design "Telegram chats")
class TelegramPage extends StatelessWidget {
  const TelegramPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TelegramCubit>()..load(),
      child: const _TelegramView(),
    );
  }
}

class _TelegramView extends StatefulWidget {
  const _TelegramView();

  @override
  State<_TelegramView> createState() => _TelegramViewState();
}

class _TelegramViewState extends State<_TelegramView> {
  /// Once the connection steps start, keep them until they finish (the pairing code step must still show even though the state changes the moment the token is saved)
  bool _setup = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocConsumer<TelegramCubit, TelegramViewState>(
      listenWhen: (a, b) => a.actionFailure != b.actionFailure || a.needsSetup != b.needsSetup,
      listener: (context, s) {
        if (s.actionFailure != null) showFailure(context, s.actionFailure!);
        if (s.needsSetup && !_setup) setState(() => _setup = true);
      },
      builder: (context, s) {
        final setup = _setup || s.needsSetup;
        final Widget body;
        if (setup) {
          body = TelegramConnectView(
            mode: TelegramConnectMode.setup,
            onDone: () {
              setState(() => _setup = false);
              context.read<TelegramCubit>().load();
            },
          );
        } else if (s.overview == null && s.loading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (s.overview == null) {
          body = FailureView(failure: s.failure!, onRetry: () => context.read<TelegramCubit>().load());
        } else {
          body = _ChatsView(state: s);
        }
        return Scaffold(
          appBar: AppBar(title: Text(setup ? l.tgConnectTitle : l.tgTitle)),
          body: body,
        );
      },
    );
  }
}

class _ChatsView extends StatelessWidget {
  const _ChatsView({required this.state});

  final TelegramViewState state;

  Future<void> _open(BuildContext context, TelegramConnectMode mode) async {
    final cubit = context.read<TelegramCubit>();
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TelegramConnectPage(mode: mode)),
    );
    if (!cubit.isClosed) await cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<TelegramCubit>();
    final o = state.overview!;
    final opts = state.options;
    final linkStyle = TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8));
    return RefreshIndicator(
      onRefresh: cubit.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _StatusCard(overview: o, onReplaceToken: () => _open(context, TelegramConnectMode.replaceToken)),
          if (o.state == TelegramState.conflict || o.state == TelegramState.tokenInvalid) ...[
            const SizedBox(height: 12),
            NoticeBox(
              warning: true,
              child: Text(o.state == TelegramState.conflict ? l.tgStateConflictBody : l.tgStateTokenInvalidBody),
            ),
          ],
          const SizedBox(height: 14),
          SectionTitle(
            l.tgChatsTitle,
            trailing: TextButton(
              onPressed: () => _open(context, TelegramConnectMode.addChat),
              style: linkStyle,
              child: Text(l.tgAddChat),
            ),
          ),
          if (o.chats.isEmpty)
            AppCard(child: Text(l.tgChatsEmpty, style: theme.textTheme.bodyMedium))
          else
            ListGroup(children: [for (final c in o.chats) _ChatRow(chat: c)]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(l.tgChatsHint, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 14),
          SectionTitle(l.tgNotifyTitle),
          ListGroup(children: [
            SwitchRow(
              title: l.tgAutoRead,
              subtitle: l.tgAutoReadBody,
              value: opts.autoRead,
              onChanged: cubit.setAutoRead,
            ),
            ListRow(
              title: l.tgQuietHours,
              onTap: () async {
                final picked = await showQuietHoursSheet(context, opts);
                if (picked != null) await cubit.setQuietHours(picked.$1, picked.$2);
              },
              trailing: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('${tgHour(opts.quietStart)} – ${tgHour(opts.quietEnd)}',
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.overview, required this.onReplaceToken});

  final TelegramOverview overview;
  final VoidCallback onReplaceToken;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, color) = switch (overview.state) {
      TelegramState.ok => (l.tgStateOk, theme.brightness == Brightness.dark ? scheme.primary : AppColors.ok),
      TelegramState.connecting => (l.tgStateConnecting, scheme.onSurfaceVariant),
      TelegramState.conflict => (l.tgStateConflict, scheme.error),
      TelegramState.tokenInvalid => (l.tgStateTokenInvalid, scheme.error),
      _ => (l.tgStateOff, scheme.onSurfaceVariant),
    };
    final detail = [if (overview.bot.isNotEmpty) '@${overview.bot}', l.tgUnread(overview.unread)].join(' · ');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        StatusDot(color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(detail, style: theme.textTheme.bodySmall),
          ]),
        ),
        TextButton(onPressed: onReplaceToken, child: Text(l.tgReplaceToken)),
      ]),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});

  final TelegramChat chat;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<TelegramCubit>();
    return ListRow(
      leading: TgChatAvatar(chat: chat),
      title: chat.alias,
      subtitle: tgChatSubtitle(l, chat),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: l.tgRenameLabel(chat.alias),
          icon: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
          onPressed: () async {
            final alias = await showRenameDialog(context, chat);
            if (alias != null && alias != chat.alias) await cubit.rename(chat.chatId, alias);
          },
        ),
        IconButton(
          tooltip: l.tgDeleteLabel(chat.alias),
          icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
          onPressed: () async {
            final ok = await confirm(
              context,
              title: l.tgDeleteTitle(chat.alias),
              body: l.tgDeleteBody,
              action: l.tgDeleteAction,
              destructive: true,
            );
            if (ok) await cubit.remove(chat.chatId);
          },
        ),
      ]),
    );
  }
}
