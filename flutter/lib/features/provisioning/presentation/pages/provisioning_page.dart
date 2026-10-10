import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/ai/ai_choice.dart';
import '../../../../core/ai/ai_texts.dart';
import '../../../../core/ble/ble_link.dart';
import '../../../../core/errors/error_localizer.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../devices/presentation/bloc/devices_cubit.dart';
import '../../domain/entities/provisioning_input.dart';
import '../bloc/provisioning_cubit.dart';

/// First-time setup, adding a phone, re-registration (design "First-time setup" 1–4)
class ProvisioningPage extends StatelessWidget {
  const ProvisioningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ProvisioningCubit>()..init(),
      child: const _ProvisioningView(),
    );
  }
}

class _ProvisioningView extends StatelessWidget {
  const _ProvisioningView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<ProvisioningCubit, ProvisioningState>(
      builder: (context, s) {
        final finished = s.step == ProvStep.done;
        return Scaffold(
          appBar: finished
              ? null
              : AppBar(
                  leading: IconButton(
                    tooltip: l.provCancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(s.speaker?.name ?? l.provTitle, style: Theme.of(context).textTheme.titleMedium),
                ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, finished ? 56 : 4, 20, 0),
                  child: StepProgress(current: s.stepNumber, total: 4),
                ),
                Expanded(child: _body(context, s)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, ProvisioningState s) {
    final l = AppLocalizations.of(context);
    return switch (s.step) {
      ProvStep.keys => _KeysStep(state: s),
      ProvStep.scanning => _ScanStep(state: s),
      ProvStep.connecting => _Busy(text: l.provConnecting),
      ProvStep.wifiChoice => const _WifiChoiceStep(),
      ProvStep.wifiScanning => _Busy(text: l.provWifiScanning),
      ProvStep.wifiList => _WifiStep(state: s),
      ProvStep.wifiConnecting => _Busy(text: l.provWifiConnecting(s.lastSsid ?? '')),
      ProvStep.sending => _Busy(text: l.provSending),
      ProvStep.phonesFull => _PhonesFullStep(state: s),
      ProvStep.discovering => _Busy(text: l.provDiscovering),
      ProvStep.done => _DoneStep(state: s),
      ProvStep.failed => _FailedStep(state: s),
    };
  }
}

/// Title + body + fixed button at the bottom
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, this.body, required this.children, this.footer});

  final String title;
  final String? body;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            children: [
              Text(title, style: t.headlineSmall),
              if (body != null) ...[const SizedBox(height: 8), Text(body!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))],
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
        if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: footer),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ]),
        ),
      );
}

// ── 1. AI · key · mode ─────────────────────────────────

class _KeysStep extends StatefulWidget {
  const _KeysStep({required this.state});

  final ProvisioningState state;

  @override
  State<_KeysStep> createState() => _KeysStepState();
}

class _KeysStepState extends State<_KeysStep> {
  final _form = GlobalKey<FormState>();
  late final _keys = {
    AiProvider.openai: TextEditingController(text: widget.state.input.openAiKey),
    AiProvider.gemini: TextEditingController(text: widget.state.input.geminiKey),
  };
  late final _tg = TextEditingController(text: widget.state.input.telegramToken);
  late final _phone = TextEditingController(text: widget.state.input.phoneName);
  late bool _remember = widget.state.remember;
  late AiProvider _provider = widget.state.missingKey ?? widget.state.input.provider;
  late AiMode _mode = widget.state.input.mode;
  late bool _existing = widget.state.input.existingKey;

  @override
  void initState() {
    super.initState();
    for (final c in _keys.values) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void didUpdateWidget(_KeysStep old) {
    super.didUpdateWidget(old);
    // init() fills in the remembered values late
    final input = widget.state.input;
    if (old.state.input.provider != input.provider) _provider = input.provider;
    for (final p in AiProvider.values) {
      if (_keys[p]!.text.isEmpty && input.keyFor(p).isNotEmpty) _keys[p]!.text = input.keyFor(p);
    }
    if (_tg.text.isEmpty && input.telegramToken.isNotEmpty) _tg.text = input.telegramToken;
    if (_phone.text.isEmpty && input.phoneName.isNotEmpty) _phone.text = input.phoneName;
  }

  @override
  void dispose() {
    for (final c in _keys.values) {
      c.dispose();
    }
    _tg.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _paste(TextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) c.text = data!.text!.trim();
  }

  ProvisioningInput get _input => ProvisioningInput(
        provider: _provider,
        mode: _mode,
        openAiKey: _keys[AiProvider.openai]!.text.trim(),
        geminiKey: _keys[AiProvider.gemini]!.text.trim(),
        existingKey: _existing,
        telegramToken: _tg.text.trim(),
        phoneName: _phone.text.trim().isEmpty ? 'Phone' : _phone.text.trim(),
      );

  String? _validateKey(AiProvider p, String? v, AppLocalizations l) {
    final t = v?.trim() ?? '';
    if (t.isEmpty || ProvisioningInput.keyPattern(p).hasMatch(t)) return null;
    return p == AiProvider.openai ? l.provOpenAiKeyInvalid : l.aiKeyInvalidGemini;
  }

  Widget _keyField(AiProvider p, AppLocalizations l, {String? label, String? helper, Color? helperColor}) =>
      TextFormField(
        key: ValueKey(p),
        controller: _keys[p],
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label ?? l.aiKeyLabel(p.displayName),
          hintText: p == AiProvider.openai ? 'sk-...' : 'AIza...',
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: helperColor == null ? null : TextStyle(color: helperColor),
          suffixIcon: TextButton(onPressed: () => _paste(_keys[p]!), child: Text(l.provPaste)),
        ),
        validator: (v) => _validateKey(p, v, l),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final input = _input;
    final typed = input.hasChosenKey;
    final keyLabel = l.aiKeyLabel(_provider.displayName);
    final other = _provider.other;
    final label = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600);
    return Form(
      key: _form,
      child: _StepScaffold(
        title: l.provKeysTitle,
        body: l.provKeysBody,
        footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
            onPressed: !input.canSearch
                ? null
                : () {
                    if (!_form.currentState!.validate()) return;
                    context.read<ProvisioningCubit>().submitKeys(_input, remember: _remember);
                  },
            child: Text(l.provFindSpeaker),
          ),
          if (!input.canSearch) ...[
            const SizedBox(height: 8),
            Text(l.provKeyBlocked(keyLabel),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
          ],
        ]),
        children: [
          if (widget.state.missingKey != null) ...[
            NoticeBox(warning: true, child: Text(l.provMissingKey(widget.state.missingKey!.displayName))),
            const SizedBox(height: 16),
          ],
          if (widget.state.notReady != null) ...[
            NoticeBox(warning: true, child: Text(l.provNotReady(widget.state.notReady!.displayName))),
            const SizedBox(height: 16),
          ],
          Text(l.provAiSection, style: label),
          const SizedBox(height: 8),
          Row(children: [
            for (final p in AiProvider.values) ...[
              if (p != AiProvider.values.first) const SizedBox(width: 10),
              Expanded(
                child: _ChoiceTile(
                  title: p.displayName,
                  selected: p == _provider,
                  height: 52,
                  onTap: () => setState(() => _provider = p),
                ),
              ),
            ],
          ]),
          // Before connecting, we don't know what this speaker can do (checked after connecting via device.info.ai)
          if (_provider == AiProvider.gemini) ...[
            const SizedBox(height: 6),
            Text(l.provMaybeNotReady, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          _keyField(
            _provider,
            l,
            label: '$keyLabel ${l.provRequired}',
            helper: typed ? l.provKeyTyped : (_existing ? l.provKeyExistingHint : l.provKeyRequiredHint),
            helperColor: typed ? scheme.primary : (_existing ? null : scheme.error),
          ),
          CheckboxListTile(
            value: _existing,
            onChanged: (v) => setState(() => _existing = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l.provExistingKey, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: [
            TextSpan(text: l.provModeSection, style: label),
            TextSpan(text: ' ${l.provModeLater}', style: theme.textTheme.bodySmall),
          ])),
          const SizedBox(height: 8),
          Row(children: [
            for (final m in const [AiMode.saver, AiMode.live]) ...[
              if (m != AiMode.saver) const SizedBox(width: 10),
              Expanded(
                child: _ChoiceTile(
                  title: l.aiModeName(m),
                  subtitle: l.aiShortSub(_provider, m),
                  selected: m == _mode,
                  height: 64,
                  onTap: () => setState(() => _mode = m),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(l.provMore(other.displayName),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              children: [
                _keyField(other, l, helper: l.provMoreOtherHint(other.displayName)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tg,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '${l.provTelegramToken} ${l.provOptional}',
                    helperText: l.provTelegramTokenHint,
                    suffixIcon: TextButton(onPressed: () => _paste(_tg), child: Text(l.provPaste)),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty || ProvisioningInput.telegramTokenPattern.hasMatch(v.trim())
                          ? null
                          : l.provTelegramTokenInvalid,
                ),
              ],
            ),
          ),
          ListGroup(children: [
            SwitchRow(
              title: l.provRemember,
              subtitle: l.provRememberHint,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
            ),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            maxLength: 32,
            decoration: InputDecoration(labelText: l.provPhoneName, counterText: ''),
          ),
        ],
      ),
    );
  }
}

/// Card for picking one of two (AI, conversation mode)
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : null,
                    )),
                if (subtitle != null)
                  Text(subtitle!,
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 2. Find speaker ──────────────────────────────────────

class _ScanStep extends StatelessWidget {
  const _ScanStep({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ProvisioningCubit>();
    return _StepScaffold(
      title: l.provScanTitle,
      footer: OutlinedButton(
        // Can't be tapped while searching (restarting hits Android's scan count limit)
        onPressed: state.searching ? null : cubit.scan,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(l.provScanAgain),
      ),
      children: [
        NoticeBox(child: Text(l.provScanHint)),
        const SizedBox(height: 16),
        Row(children: [
          if (state.searching)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5))
          else
            Icon(Icons.bluetooth_searching, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(state.speakers.isEmpty ? l.provScanNone : l.provScanFound(state.speakers.length),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        for (final s in state.speakers) ...[
          _SpeakerTile(speaker: s, onTap: () => cubit.selectSpeaker(s)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SpeakerTile extends StatelessWidget {
  const _SpeakerTile({required this.speaker, required this.onTap});

  final DiscoveredSpeaker speaker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final near = speaker.rssi >= -70;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: near ? scheme.primary : scheme.outline, width: near ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.speaker_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(speaker.name, style: Theme.of(context).textTheme.titleMedium),
                Text(near ? l.provSignalNear : l.provSignalFar, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            Icon(near ? Icons.signal_cellular_alt_rounded : Icons.signal_cellular_alt_1_bar_rounded, color: scheme.primary),
          ]),
        ),
      ),
    );
  }
}

// ── 3. Wi-Fi ───────────────────────────────────────────

class _WifiChoiceStep extends StatelessWidget {
  const _WifiChoiceStep();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ProvisioningCubit>();
    return _StepScaffold(
      title: l.provWifiChoiceTitle,
      body: l.provWifiChoiceBody,
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(onPressed: cubit.keepWifi, child: Text(l.provWifiKeep)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: cubit.loadWifi,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: Text(l.provWifiChange),
        ),
      ]),
      children: const [],
    );
  }
}

class _WifiStep extends StatelessWidget {
  const _WifiStep({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ProvisioningCubit>();
    return _StepScaffold(
      title: l.provWifiTitle,
      footer: OutlinedButton(
        onPressed: cubit.loadWifi,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(l.provWifiRescan),
      ),
      children: [
        if (state.wifiErrorKey != null) ...[
          NoticeBox(warning: true, child: Text(l.errorKeyText(state.wifiErrorKey!))),
          const SizedBox(height: 12),
        ],
        ListGroup(children: [
          for (final n in state.networks)
            ListRow(
              title: n.ssid,
              selected: n.ssid == state.lastSsid,
              leading: Icon(_wifiIcon(n.bars), color: Theme.of(context).colorScheme.primary),
              trailing: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: n.security.needsPassword
                    ? Icon(Icons.lock_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)
                    : Text(l.provWifiOpen, style: Theme.of(context).textTheme.bodySmall),
              ),
              onTap: () => n.security.needsPassword
                  ? _askPassword(context, n.ssid)
                  : cubit.connectWifi(n.ssid, ''),
            ),
          ListRow(
            title: l.provWifiManual,
            leading: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: () => _askPassword(context, null),
          ),
        ]),
        const SizedBox(height: 10),
        Text(l.provWifiNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static IconData _wifiIcon(int bars) => switch (bars) {
        >= 3 => Icons.wifi_rounded,
        2 => Icons.wifi_2_bar_rounded,
        _ => Icons.wifi_1_bar_rounded,
      };

  Future<void> _askPassword(BuildContext context, String? ssid) async {
    final cubit = context.read<ProvisioningCubit>();
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WifiPasswordSheet(ssid: ssid),
    );
    if (result != null) await cubit.connectWifi(result.$1, result.$2);
  }
}

class _WifiPasswordSheet extends StatefulWidget {
  const _WifiPasswordSheet({required this.ssid});

  final String? ssid;

  @override
  State<_WifiPasswordSheet> createState() => _WifiPasswordSheetState();
}

class _WifiPasswordSheetState extends State<_WifiPasswordSheet> {
  final _ssid = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _ssid.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.ssid == null ? l.provWifiManual : l.provWifiPasswordTitle(widget.ssid!),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (widget.ssid == null) ...[
            TextField(controller: _ssid, decoration: InputDecoration(labelText: l.provWifiName)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _pw,
            obscureText: !_show,
            autofocus: widget.ssid != null,
            decoration: InputDecoration(
              labelText: l.provWifiPassword,
              suffixIcon: IconButton(
                tooltip: l.provWifiShowPassword,
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final ssid = widget.ssid ?? _ssid.text.trim();
              if (ssid.isEmpty) return;
              Navigator.pop(context, (ssid, _pw.text));
            },
            child: Text(l.provWifiConnect),
          ),
        ],
      ),
    );
  }
}

// ── Phone slots full ────────────────────────────────

class _PhonesFullStep extends StatefulWidget {
  const _PhonesFullStep({required this.state});

  final ProvisioningState state;

  @override
  State<_PhonesFullStep> createState() => _PhonesFullStepState();
}

class _PhonesFullStepState extends State<_PhonesFullStep> {
  String? _pick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _StepScaffold(
      title: l.provPhonesFullTitle,
      body: l.provPhonesFullBody,
      footer: FilledButton(
        onPressed: _pick == null ? null : () => context.read<ProvisioningCubit>().evictAndPair(_pick!),
        child: Text(l.provPhonesFullAction),
      ),
      children: [
        RadioGroup<String>(
          groupValue: _pick,
          onChanged: (v) => setState(() => _pick = v),
          child: ListGroup(children: [
            for (final p in widget.state.phones)
              RadioListTile<String>(value: p.phoneId, title: Text(p.name.isEmpty ? p.phoneId.substring(0, 8) : p.name)),
          ]),
        ),
      ],
    );
  }
}

// ── 4. Done ────────────────────────────────────────────

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final host = state.device?.host;
    final items = [
      if (state.wifiChanged) l.provDoneWifi,
      if (state.done.contains('key')) l.provDoneKey,
      l.provDonePair,
      if (host != null) l.provDoneFound(host),
    ];
    return _StepScaffold(
      title: l.provDoneTitle,
      body: l.provDoneBody,
      footer: FilledButton(
        onPressed: () {
          context.read<DevicesCubit>().load();
          Navigator.popUntil(context, (r) => r.isFirst);
        },
        child: Text(l.provGoHome),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CircleAvatar(radius: 36, backgroundColor: scheme.primary, child: const Icon(Icons.check_rounded, size: 36, color: Colors.white)),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  const Icon(Icons.check_rounded, color: Color(0xFF1F6B3A)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t)),
                ]),
              ),
          ]),
        ),
        if (host == null) ...[
          const SizedBox(height: 12),
          NoticeBox(warning: true, child: Text(l.provDoneNotFound)),
        ],
      ],
    );
  }
}

class _FailedStep extends StatelessWidget {
  const _FailedStep({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<ProvisioningCubit>();
    return _StepScaffold(
      title: l.provFailedTitle,
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(onPressed: cubit.retry, child: Text(l.commonRetry)),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: Text(l.provCancel),
        ),
      ]),
      children: [
        if (state.failure != null) NoticeBox(warning: true, child: Text(l.errorText(state.failure!))),
      ],
    );
  }
}
