import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/error_localizer.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../devices/presentation/bloc/devices_cubit.dart';
import '../../domain/entities/system_status.dart';
import '../bloc/system_cubit.dart';
import '../system_format.dart';
import 'app_settings_page.dart';
import 'keys_page.dart';

/// System (design "System"): device info, registered phones, keys and app settings, restart, factory reset guide, remove from this phone
class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SystemCubit>()..load(),
      child: const _SystemView(),
    );
  }
}

class _SystemView extends StatelessWidget {
  const _SystemView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sysTitle)),
      body: BlocBuilder<SystemCubit, SystemState>(
        builder: (context, s) => RefreshIndicator(
          onRefresh: () => context.read<SystemCubit>().load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (s.status == null && s.loading)
                const AppCard(child: Center(child: CircularProgressIndicator()))
              else if (s.status == null && s.failure != null)
                NoticeBox(
                  warning: true,
                  icon: Icons.wifi_off_rounded,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.errorText(s.failure!)),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: () => context.read<SystemCubit>().load(), child: Text(l.commonRetry)),
                  ]),
                )
              else if (s.status != null)
                _InfoCard(status: s.status!, host: context.read<SystemCubit>().host),
              const SizedBox(height: 14),
              if (s.status != null || s.phones.isNotEmpty) ...[
                _PhonesSection(state: s),
                const SizedBox(height: 14),
              ],
              ListGroup(children: [
                ListRow(
                  leading: Icon(Icons.key_rounded, color: Theme.of(context).colorScheme.primary),
                  title: l.sysMenuKeys,
                  subtitle: l.sysMenuKeysHint,
                  trailing: const _Chevron(),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const KeysPage())),
                ),
                ListRow(
                  leading: Icon(Icons.phone_iphone_rounded, color: Theme.of(context).colorScheme.primary),
                  title: l.sysMenuApp,
                  subtitle: l.sysMenuAppHint,
                  trailing: const _Chevron(),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AppSettingsPage())),
                ),
              ]),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: s.status == null || s.busy ? null : () => _reboot(context),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(l.sysReboot),
              ),
              const SizedBox(height: 14),
              NoticeBox(
                warning: true,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: l.sysFactoryResetTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: l.sysFactoryResetBody),
                ])),
              ),
              if (s.status != null) ...[
                const SizedBox(height: 14),
                _Diagnostics(status: s.status!),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _forget(context),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l.sysForget),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reboot(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SystemCubit>();
    if (!await confirm(context, title: l.sysRebootTitle, body: l.sysRebootBody, action: l.sysRebootAction)) return;
    final f = await cubit.reboot();
    if (!context.mounted) return;
    // 409 VOICE_ACTIVE → "대화 중에는 할 수 없어요" (Can't do this during a conversation)
    f == null ? showMessage(context, l.sysRebooting) : showFailure(context, f);
  }

  Future<void> _forget(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SystemCubit>();
    final devices = context.read<DevicesCubit>();
    final navigator = Navigator.of(context);
    final id = cubit.deviceId ?? devices.state.selectedId;
    if (id == null) return;
    if (!await confirm(context,
        title: l.sysForgetTitle, body: l.sysForgetBody, action: l.sysForgetAction, destructive: true)) {
      return;
    }
    await cubit.revokeSelf(); // if it can't connect, just move on
    await devices.remove(id);
    navigator.popUntil((r) => r.isFirst);
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Two-column name + value row (the design's dl)
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(value,
                textAlign: TextAlign.right, style: t.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _InfoLines extends StatelessWidget {
  const _InfoLines(this.lines);

  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _InfoLine(lines[i].$1, lines[i].$2),
        ],
      ]);
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.status, required this.host});

  final SystemStatus status;
  final String? host;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _InfoLines([
        (l.sysFirmware, status.firmware),
        (l.sysUptime, formatUptime(l, status.uptime)),
        (l.sysWifi, formatWifi(l, status.wifiRssi)),
        (l.sysIp, host ?? '–'),
      ]),
    );
  }
}

class _PhonesSection extends StatelessWidget {
  const _PhonesSection({required this.state});

  final SystemState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final date = DateFormat.yMd(Localizations.localeOf(context).toLanguageTag());
    if (state.phonesFailure != null && state.phones.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(l.sysPhonesTitle(0, maxPhones)),
        AppCard(child: Text(l.sysPhonesFailed)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(l.sysPhonesTitle(state.phones.length, maxPhones)),
      ListGroup(children: [
        for (final p in state.phones)
          ListRow(
            title: p.name,
            subtitle: p.created == null ? null : l.sysPhoneCreated(date.format(p.created!)),
            trailing: p.self
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: Text(l.sysPhoneSelf,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: state.busy ? null : () => _revoke(context, p),
                    style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error, minimumSize: const Size(44, 44)),
                    child: Text(l.sysPhoneRevoke),
                  ),
          ),
      ]),
    ]);
  }

  Future<void> _revoke(BuildContext context, RegisteredPhone phone) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SystemCubit>();
    if (!await confirm(context,
        title: l.sysPhoneRevokeTitle(phone.name),
        body: l.sysPhoneRevokeBody,
        action: l.sysPhoneRevoke,
        destructive: true)) {
      return;
    }
    final f = await cubit.revoke(phone);
    if (!context.mounted) return;
    f == null ? showMessage(context, l.sysPhoneRevoked) : showFailure(context, f);
  }
}

/// Collapsed "Diagnostics": build, start reason, memory, recent failures
class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.status});

  final SystemStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(l.sysDiagnostics, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              _InfoLines([
                if (status.buildDate.isNotEmpty) (l.sysBuildDate, status.buildDate),
                (l.sysResetReason, formatResetReason(l, status.resetReason)),
                (l.sysHeapFree, formatKb(l, status.heapInternalFree)),
                (l.sysHeapMin, formatKb(l, status.heapInternalMin)),
                if (status.psramFree != null) (l.sysPsramFree, formatKb(l, status.psramFree)),
                (l.sysFailures, status.failures.isEmpty ? l.sysNoFailures : status.failures.join('\n')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
