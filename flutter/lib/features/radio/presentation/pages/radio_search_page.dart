import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/radio_preset.dart';
import '../../domain/radio_rules.dart';
import '../bloc/radio_cubit.dart';
import '../bloc/radio_search_cubit.dart';
import '../widgets/preset_form_sheet.dart';
import 'radio_page.dart';

/// Station search: search Radio-Browser from the phone → add to presets or play now.
/// Takes the radio screen's RadioCubit as is (BlocProvider.value)
class RadioSearchPage extends StatelessWidget {
  const RadioSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RadioSearchCubit>(),
      child: const RadioSearchView(),
    );
  }
}

class RadioSearchView extends StatefulWidget {
  const RadioSearchView({super.key});

  @override
  State<RadioSearchView> createState() => _RadioSearchViewState();
}

class _RadioSearchViewState extends State<RadioSearchView> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _add(RadioPreset p) async {
    final l = AppLocalizations.of(context);
    if (await context.read<RadioCubit>().addPreset(p) && mounted) showMessage(context, l.radioAdded(p.name));
  }

  Future<void> _addCustom() async {
    final p = await showPresetForm(context, full: true);
    if (p != null && mounted) await _add(p);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final search = context.read<RadioSearchCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.radioSearchTitle),
        actions: [
          IconButton(tooltip: l.radioAddCustom, onPressed: _addCustom, icon: const Icon(Icons.add_link_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: RadioMessages(
        child: BlocBuilder<RadioSearchCubit, RadioSearchState>(
          builder: (context, s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l.radioSearchByName)),
                  ButtonSegment(value: true, label: Text(l.radioSearchByTag)),
                ],
                selected: {s.byTag},
                showSelectedIcon: false,
                onSelectionChanged: (v) => search.setByTag(v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: s.byTag ? l.radioSearchTagHint : l.radioSearchNameHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: l.radioSearch,
                    onPressed: () => search.search(_query.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
                onSubmitted: search.search,
              ),
              const SizedBox(height: 12),
              NoticeBox(child: Text(l.radioSearchHlsNote, style: const TextStyle(fontSize: 13))),
              const SizedBox(height: 12),
              if (s.loading)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (s.failure != null)
                _Hint(text: l.radioSearchFailed, onRetry: () => search.search(s.query))
              else if (s.results == null)
                _Hint(text: l.radioSearchIdle)
              else if (s.results!.isEmpty)
                _Hint(text: l.radioSearchNoResults)
              else
                ListGroup(children: [
                  for (final station in s.results!) _StationRow(station: station, onAdd: _add),
                ]),
              const SizedBox(height: 8),
              Text('radio-browser.info', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l.commonRetry)),
        ],
      ]),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({required this.station, required this.onAdd});

  final RadioStation station;
  final Future<void> Function(RadioPreset) onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preset = presetFromStation(station);
    final (busy, added) = context.select<RadioCubit, (bool, bool)>((c) => (c.state.busy, c.hasUrl(station.url)));
    final info = [
      if (station.country.isNotEmpty) station.country,
      station.codec,
      if (station.bitrate > 0) l.radioKbps(station.bitrate),
      ...preset.displayTags.take(3),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preset.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
          ]),
        ),
        TextButton(
          onPressed: busy ? null : () => context.read<RadioCubit>().playStation(station),
          child: Text(l.radioSearchPlayNow),
        ),
        added
            ? TextButton.icon(onPressed: null, icon: const Icon(Icons.check_rounded, size: 18), label: Text(l.radioSearchAdded))
            : TextButton.icon(
                onPressed: busy ? null : () => onAdd(preset),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l.radioSearchAdd),
              ),
      ]),
    );
  }
}
