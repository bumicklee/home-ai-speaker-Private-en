import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/radio_rules.dart';
import '../bloc/radio_cubit.dart';
import '../widgets/radio_texts.dart';
import 'preset_edit_page.dart';
import 'radio_search_page.dart';

/// Radio (design "Radio"): now playing (dark card), presets by group, station search and editing
class RadioPage extends StatelessWidget {
  const RadioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RadioCubit>()..load(),
      child: const RadioView(),
    );
  }
}

/// Failures and validation errors as a snackbar (shared by the radio screens)
class RadioMessages extends StatelessWidget {
  const RadioMessages({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<RadioCubit, RadioState>(
      listenWhen: (a, b) => (b.failure != null && a.failure != b.failure) || (b.invalid != null && a.invalid != b.invalid),
      listener: (context, s) {
        final l = AppLocalizations.of(context);
        final text = s.invalid != null ? l.presetErrorText(s.invalid!) : l.radioFailureText(s.failure!);
        showMessage(context, text);
      },
      child: child,
    );
  }
}

class RadioView extends StatelessWidget {
  const RadioView({super.key});

  void _open(BuildContext context, Widget page) {
    final cubit = context.read<RadioCubit>();
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => BlocProvider.value(value: cubit, child: page)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.radioTitle),
        actions: [
          BlocBuilder<RadioCubit, RadioState>(
            buildWhen: (a, b) => a.loaded != b.loaded,
            builder: (context, s) => IconButton(
              tooltip: l.radioEdit,
              onPressed: s.loaded ? () => _open(context, const PresetEditPage()) : null,
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: () => _open(context, const RadioSearchPage()),
              style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text(l.radioSearch, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
      body: RadioMessages(
        child: BlocBuilder<RadioCubit, RadioState>(
          builder: (context, s) {
            final cubit = context.read<RadioCubit>();
            if (!s.loaded && s.loading) return const Center(child: CircularProgressIndicator());
            if (!s.loaded && s.failure != null) return FailureView(failure: s.failure!, onRetry: cubit.load);
            final playing = s.playingIndex;
            return RefreshIndicator(
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  NowPlayingHeader(state: s),
                  const SizedBox(height: 6),
                  if (s.presets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(l.radioEmpty, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  for (final (group, indexes) in groupPresets(s.presets)) ...[
                    const SizedBox(height: 8),
                    SectionTitle(l.presetGroupText(group)),
                    ListGroup(children: [
                      for (final i in indexes)
                        _PresetRow(index: i, playing: i == playing, busy: s.busy),
                    ]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.index, required this.playing, required this.busy});

  final int index;
  final bool playing;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<RadioCubit>();
    final p = cubit.state.presets[index];
    final tags = p.displayTags;
    final play = busy || playing ? null : () => cubit.playPreset(index);
    return ListRow(
      title: p.name,
      subtitle: tags.isEmpty ? null : tags.join(' · '),
      selected: playing,
      onTap: play,
      trailing: playing
          ? SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.graphic_eq_rounded, color: scheme.primary, semanticLabel: l.radioPlaying),
            )
          : IconButton(
              tooltip: l.radioPlay,
              onPressed: play,
              icon: Icon(Icons.play_arrow_rounded, color: scheme.primary),
            ),
    );
  }
}

/// Now playing (dark card). Shown and controllable even when it isn't the radio (Spotify)
class NowPlayingHeader extends StatelessWidget {
  const NowPlayingHeader({super.key, required this.state});

  final RadioState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final cubit = context.read<RadioCubit>();
    final media = state.now.media;
    final active = media.isActive;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = switch (media.state) {
      'playing' => l.radioPlaying,
      'paused' => l.radioPaused,
      'buffering' => l.radioBuffering,
      _ => l.radioNothingPlaying,
    };
    final title = media.station.isNotEmpty ? media.station : media.title;
    final song = [media.artist, media.title].where((x) => x.isNotEmpty).join(' - ');
    final enabled = !state.busy;
    return DecoratedBox(
      decoration: BoxDecoration(color: dark ? AppColors.accentDark : AppColors.ink, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      style: t.bodySmall?.copyWith(color: AppColors.accentOnDark, fontWeight: FontWeight.w600, fontSize: 12)),
                  Text(active ? title : l.radioPickStation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(color: Colors.white, fontSize: active ? 17 : 15)),
                  if (active && song.isNotEmpty && song != title)
                    Text(song,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: const Color(0xFFD6F0EE))),
                ]),
              ),
              if (active) ...[
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: state.now.canPause ? l.radioPause : l.radioResume,
                  onPressed: !enabled ? null : cubit.togglePause,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: Icon(state.now.canPause ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
              ],
            ]),
            if (active) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final (icon, tip, action) in [
                  (Icons.skip_previous_rounded, l.radioPrevious, 'previous'),
                  (Icons.stop_rounded, l.radioStop, 'stop'),
                  (Icons.skip_next_rounded, l.radioNext, 'next'),
                ])
                  IconButton(
                    tooltip: tip,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    onPressed: !enabled ? null : () => cubit.media(action),
                    icon: Icon(icon),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
