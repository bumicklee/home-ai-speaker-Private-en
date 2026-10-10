import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/ble_protocol.dart';
import '../../../../core/errors/error_localizer.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/send_key_sheet.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../provisioning/domain/entities/provisioning_input.dart';
import '../bloc/keys_cubit.dart';

/// Key management: keys remembered on this phone, keys saved on the speaker (change over BLE, delete over LAN)
class KeysPage extends StatelessWidget {
  const KeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<KeysCubit>()..load(),
      child: const _KeysView(),
    );
  }
}

String _label(AppLocalizations l, String key) => switch (key) {
      SecretKey.openai => l.sysKeyOpenAi,
      SecretKey.gemini => l.sysKeyGemini,
      _ => l.sysKeyTelegram,
    };

RegExp _pattern(String key) => switch (key) {
      SecretKey.openai => ProvisioningInput.openAiKeyPattern,
      SecretKey.gemini => ProvisioningInput.geminiKeyPattern,
      _ => ProvisioningInput.telegramTokenPattern,
    };

String _invalid(AppLocalizations l, String key) => switch (key) {
      SecretKey.openai => l.sysKeyInvalidOpenAi,
      SecretKey.gemini => l.sysKeyInvalidGemini,
      _ => l.sysKeyInvalidTelegram,
    };

class _KeysView extends StatelessWidget {
  const _KeysView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sysKeysTitle)),
      body: BlocBuilder<KeysCubit, KeysState>(
        builder: (context, s) {
          if (!s.loaded) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SectionTitle(l.sysKeysSpeakerSection),
              if (s.speakerFailure != null) ...[
                NoticeBox(warning: true, icon: Icons.wifi_off_rounded, child: Text(l.errorText(s.speakerFailure!))),
                const SizedBox(height: 8),
              ],
              ListGroup(children: [
                for (final k in KeysCubit.keys) _SpeakerKeyRow(keyName: k, state: s),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(l.sysKeysSpeakerHint, style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 16),
              SectionTitle(l.sysKeysPhoneSection),
              ListGroup(children: [
                for (final k in KeysCubit.keys) _PhoneKeyRow(keyName: k, value: s.onPhone[k]),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(l.sysKeysPhoneHint, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpeakerKeyRow extends StatelessWidget {
  const _SpeakerKeyRow({required this.keyName, required this.state});

  final String keyName;
  final KeysState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final saved = state.onSpeaker?[keyName];
    final idle = state.sending == null && !state.busy;
    return ListRow(
      title: _label(l, keyName),
      subtitle: saved == null ? l.sysKeyUnknown : (saved ? l.sysKeySaved : l.sysKeyNotSaved),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (saved == true)
          TextButton(
            onPressed: idle ? () => _delete(context) : null,
            style: TextButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size(44, 44)),
            child: Text(l.sysKeyDelete),
          ),
        TextButton(
          onPressed: idle ? () => _send(context) : null,
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          child: Text(saved == false ? l.sysKeyAdd : l.sysKeyReplace),
        ),
      ]),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<KeysCubit>();
    if (!await confirm(context,
        title: l.sysKeyDeleteTitle,
        body: switch (keyName) {
          SecretKey.openai => l.sysKeyDeleteBodyOpenAi,
          SecretKey.gemini => l.sysKeyDeleteBodyGemini,
          _ => l.sysKeyDeleteBodyTelegram,
        },
        action: l.sysKeyDelete,
        destructive: true)) {
      return;
    }
    final f = await cubit.deleteOnSpeaker(keyName);
    if (!context.mounted) return;
    f == null ? showMessage(context, l.sysKeyDeleted) : showFailure(context, f);
  }

  Future<void> _send(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<KeysCubit>();
    final sent = await showSendKeySheet(
      context,
      label: _label(l, keyName),
      initial: cubit.state.onPhone[keyName] ?? '',
      pattern: _pattern(keyName),
      invalidText: _invalid(l, keyName),
      onSend: (v) => cubit.sendToSpeaker(keyName, v),
    );
    if (sent && context.mounted) showMessage(context, l.sysKeySent);
  }
}

class _PhoneKeyRow extends StatelessWidget {
  const _PhoneKeyRow({required this.keyName, required this.value});

  final String keyName;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = value;
    return ListRow(
      title: _label(l, keyName),
      subtitle: v == null ? l.sysKeyNotSaved : KeysCubit.mask(v),
      trailing: v == null
          ? null
          : TextButton(
              onPressed: () => _forget(context),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error, minimumSize: const Size(44, 44)),
              child: Text(l.sysKeyForget),
            ),
    );
  }

  Future<void> _forget(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<KeysCubit>();
    if (!await confirm(context,
        title: l.sysKeyForgetTitle, body: l.sysKeyForgetBody, action: l.sysKeyForget, destructive: true)) {
      return;
    }
    await cubit.forgetOnPhone(keyName);
  }
}
