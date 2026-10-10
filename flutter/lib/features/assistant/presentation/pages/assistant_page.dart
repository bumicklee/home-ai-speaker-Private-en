import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/routes.dart';
import '../../../../core/ai/ai_texts.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/assistant_settings.dart';
import '../bloc/assistant_cubit.dart';
import '../widgets/assistant_editors.dart';
import 'memories_page.dart';

/// Assistant settings (design "비서"): name, language, voice, location, search, memory. Saving after edits sends only the changed keys
class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AssistantCubit>()..load(),
      child: const _AssistantView(),
    );
  }
}

class _AssistantView extends StatelessWidget {
  const _AssistantView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<AssistantCubit, AssistantState>(
      builder: (context, s) {
        final draft = s.draft;
        return PopScope(
          canPop: !s.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await confirm(context,
                title: l.asstDiscardTitle, body: l.asstDiscardBody, action: l.asstDiscard, destructive: true);
            if (leave && context.mounted) {
              context.read<AssistantCubit>().discard();
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: AppBar(title: Text(l.asstTitle)),
            body: draft == null
                ? (s.failure != null && !s.loading
                    ? FailureView(failure: s.failure!, onRetry: () => context.read<AssistantCubit>().load())
                    : const Center(child: CircularProgressIndicator()))
                : _Form(state: s, draft: draft),
            bottomNavigationBar: s.dirty ? _SaveBar(state: s) : null,
          ),
        );
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state, required this.draft});

  final AssistantState state;
  final AssistantSettings draft;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AssistantCubit>();
    final voices = state.voices.contains(draft.voice) ? state.voices : [draft.voice, ...state.voices];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Top: the AI and mode in use now (design docs/design-voice-saver-mode.md 11.8). That screen saves directly
        ListGroup(children: [
          _ValueRow(
            title: l.aiModeTitle,
            value: l.aiChoiceLabel(draft.aiProvider, draft.aiMode),
            onTap: () async {
              await Navigator.pushNamed(context, AppRoutes.aiMode);
              cubit.refreshAi();
            },
          ),
        ]),
        const SizedBox(height: 14),
        ListGroup(children: [
          _ValueRow(
            title: l.asstName,
            value: draft.name,
            onTap: () async {
              final v = await editText(context,
                  title: l.asstName,
                  initial: draft.name,
                  maxBytes: AssistantLimits.nameBytes,
                  helper: l.asstNameHint,
                  required: true);
              if (v != null) cubit.edit((d) => d.copyWith(name: v.trim()));
            },
          ),
          _ValueRow(
            title: l.asstLanguage,
            value: _languageName(l, draft.language),
            onTap: () async {
              final v = await pickOne<String>(context,
                  title: l.asstLanguage,
                  note: l.asstLanguageHint,
                  options: AssistantLimits.languages,
                  selected: draft.language,
                  label: (c) => _languageName(l, c));
              if (v != null) cubit.edit((d) => d.copyWith(language: v));
            },
          ),
          _ValueRow(
            title: l.asstVoice,
            value: draft.voice,
            subtitle: draft.voice != state.original?.voice ? l.asstVoiceNextTime : null,
            onTap: () async {
              final v = await pickOne<String>(context,
                  title: l.asstVoice,
                  note: l.asstVoiceNextTime,
                  options: voices,
                  selected: draft.voice,
                  label: (v) => v);
              if (v != null) cubit.edit((d) => d.copyWith(voice: v));
            },
          ),
          ListRow(
            title: l.asstPurpose,
            subtitle: draft.purpose.isEmpty ? l.asstPurposeHint : draft.purpose,
            trailing: const _Chevron(),
            onTap: () async {
              final v = await editText(context,
                  title: l.asstPurpose,
                  initial: draft.purpose,
                  maxBytes: AssistantLimits.purposeBytes,
                  hint: l.asstPurposeHint,
                  multiline: true);
              if (v != null) cubit.edit((d) => d.copyWith(purpose: v.trim()));
            },
          ),
          _ValueRow(
            title: l.asstUnits,
            value: _unitsName(l, draft.units),
            onTap: () async {
              final v = await pickOne<String>(context,
                  title: l.asstUnits,
                  options: AssistantLimits.units,
                  selected: draft.units,
                  label: (u) => _unitsName(l, u));
              if (v != null) cubit.edit((d) => d.copyWith(units: v));
            },
          ),
        ]),
        const SizedBox(height: 14),
        _PlaceCard(state: state, draft: draft),
        const SizedBox(height: 14),
        ListGroup(children: [
          SwitchRow(
            title: l.asstWebSearch,
            value: draft.webSearch,
            onChanged: (v) => cubit.edit((d) => d.copyWith(webSearch: v)),
          ),
          SwitchRow(
            title: l.asstDeviceControls,
            value: draft.deviceControls,
            onChanged: (v) => cubit.edit((d) => d.copyWith(deviceControls: v)),
          ),
          SwitchRow(
            title: l.asstAutoMemory,
            value: draft.autoMemory,
            onChanged: (v) => cubit.edit((d) => d.copyWith(autoMemory: v)),
          ),
          _ValueRow(
            title: l.asstMemories,
            value: state.memoryCount == null ? '' : l.asstMemoryCount(state.memoryCount!),
            muted: true,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MemoriesPage()));
              cubit.refreshMemoryCount();
            },
          ),
        ]),
      ],
    );
  }
}

String _languageName(AppLocalizations l, String code) => switch (code) {
      'ko' => l.asstLanguageKo,
      'en' => l.asstLanguageEn,
      _ => code,
    };

String _unitsName(AppLocalizations l, String units) => switch (units) {
      'metric' => l.asstUnitsMetric,
      'imperial' => l.asstUnitsImperial,
      _ => units,
    };

/// Title … value >
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.title, required this.value, this.subtitle, this.onTap, this.muted = false});

  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListRow(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: muted
                ? theme.textTheme.bodySmall?.copyWith(fontSize: 14)
                : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const _Chevron(),
      ]),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, right: 8),
        child: Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Location: neighborhood field + "Set to current location" + time zone (design document Section 3.0)
class _PlaceCard extends StatefulWidget {
  const _PlaceCard({required this.state, required this.draft});

  final AssistantState state;
  final AssistantSettings draft;

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard> {
  late final _text = TextEditingController(text: widget.draft.location);

  @override
  void didUpdateWidget(covariant _PlaceCard old) {
    super.didUpdateWidget(old);
    // Reflect values changed by "Set to current location", revert or save in the field (leave it if it equals what is being typed)
    if (widget.draft.location != _text.text && widget.draft.location.trim() != _text.text.trim()) {
      _text.text = widget.draft.location;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<AssistantCubit>();
    final s = widget.state;
    final tz = s.timezone;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.asstPlace, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(l.asstPlaceBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            textInputAction: TextInputAction.done,
            inputFormatters: [Utf8LengthLimitingFormatter(AssistantLimits.locationBytes)],
            onChanged: (v) => cubit.edit((d) => d.copyWith(location: v)),
            decoration: InputDecoration(
              labelText: l.asstPlaceField,
              hintText: l.asstPlaceExample,
              errorText: byteError(l, widget.draft.location, AssistantLimits.locationBytes),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: s.locating ? null : () => _locate(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary),
                  minimumSize: const Size(44, 44),
                ),
                icon: s.locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.place_outlined, size: 18),
                label: Text(l.asstUseCurrentLocation),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: l.asstTimezone,
              child: OutlinedButton(
                onPressed: () => _pickTimezone(context),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(widget.draft.timezone),
              ),
            ),
          ]),
          if (tz != null && !tz.supported) ...[
            const SizedBox(height: 12),
            NoticeBox(
              warning: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tz.phone == null ? l.asstTimezoneUnknown : l.asstTimezoneUnsupported(tz.phone!)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in tz.fallbacks)
                    OutlinedButton(
                      onPressed: () => cubit.setTimezone(f),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: Text(f),
                    ),
                  TextButton(onPressed: () => _pickTimezone(context), child: Text(l.asstTimezoneMore)),
                ]),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTimezone(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AssistantCubit>();
    final v = await pickOne<String>(context,
        title: l.asstTimezone,
        options: AssistantLimits.timezones,
        selected: widget.draft.timezone,
        label: (t) => t);
    if (v != null) cubit.setTimezone(v);
  }

  Future<void> _locate(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AssistantCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final r = await cubit.locate();
    if (!context.mounted) return;
    final text = switch (r) {
      LocateResult.filled => l.asstLocationFilled,
      LocateResult.filledTimezoneUnsupported => l.asstLocationFilledOnlyPlace,
      LocateResult.serviceOff => l.asstLocationServiceOff,
      LocateResult.denied => l.asstLocationDenied,
      LocateResult.deniedForever => l.asstLocationDeniedForever,
      LocateResult.unavailable => l.asstLocationUnavailable,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: r == LocateResult.deniedForever || r == LocateResult.serviceOff
            ? SnackBarAction(label: l.asstOpenSettings, onPressed: cubit.openLocationSettings)
            : null,
      ));
  }
}

/// Save button shown only when there are edits
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.state});

  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final errors = state.errors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_errorText(l, errors.first),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: state.saving || errors.isNotEmpty ? null : () => _save(context),
            child: state.saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(l.asstSave),
          ),
        ]),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    final f = await context.read<AssistantCubit>().save();
    if (!context.mounted) return;
    if (f != null) {
      showFailure(context, f);
    } else {
      showMessage(context, l.asstSaved);
    }
  }
}

String _errorText(AppLocalizations l, AssistantFieldError e) => switch (e) {
      AssistantFieldError.nameEmpty => l.asstNameEmpty,
      AssistantFieldError.nameTooLong => l.asstTooLong(AssistantLimits.nameBytes),
      AssistantFieldError.purposeTooLong => l.asstTooLong(AssistantLimits.purposeBytes),
      AssistantFieldError.locationTooLong => l.asstTooLong(AssistantLimits.locationBytes),
    };
