import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/audio_settings.dart';
import '../bloc/audio_cubit.dart';

/// Audio & Wake Word (design "Audio"): wake word card, sound card, LED brightness
class AudioPage extends StatelessWidget {
  const AudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AudioCubit>()..load(),
      child: const _AudioView(),
    );
  }
}

class _AudioView extends StatelessWidget {
  const _AudioView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.audioTitle)),
      body: BlocConsumer<AudioCubit, AudioState>(
        listenWhen: (a, b) => b.error != null && a.error != b.error,
        listener: (context, s) => showFailure(context, s.error!.failure),
        builder: (context, s) {
          if (!s.loaded) {
            if (s.failure != null) {
              return FailureView(failure: s.failure!, onRetry: () => context.read<AudioCubit>().load());
            }
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _WakeCard(wake: s.wake!, test: s.wakeTest),
              const SizedBox(height: 14),
              _SoundCard(audio: s.audio!),
              const SizedBox(height: 14),
              _LedCard(brightness: s.ledBrightness!),
            ],
          );
        },
      ),
    );
  }
}

class _WakeCard extends StatelessWidget {
  const _WakeCard({required this.wake, required this.test});

  final WakeSettings wake;
  final WakeTest? test;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AudioCubit>();
    return AppCard(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchRow(
            title: l.audioWakeEnabled,
            subtitle: l.audioWakeEnabledHint,
            value: wake.enabled,
            onChanged: cubit.setWakeEnabled,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Semantics(
                  label: l.audioPhrase,
                  container: true,
                  child: Row(children: [
                    Expanded(
                      child: _PhraseButton(
                        label: l.audioPhraseComputer,
                        selected: wake.phrase == WakePhrase.computer,
                        onTap: () => cubit.setPhrase(WakePhrase.computer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PhraseButton(
                        label: l.audioPhraseAlexa,
                        selected: wake.phrase == WakePhrase.alexa,
                        onTap: () => cubit.setPhrase(WakePhrase.alexa),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                SliderRow(
                  label: l.audioSensitivity,
                  value: wake.sensitivity.toDouble(),
                  min: 0,
                  max: 100,
                  valueText: '${wake.sensitivity}',
                  minLabel: l.audioSensitivityLow,
                  maxLabel: l.audioSensitivityHigh,
                  onChanged: (v) => cubit.preview(wake: wake.copyWith(sensitivity: v.round())),
                  onChangeEnd: (v) => cubit.setSensitivity(v.round()),
                ),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(l.audioAdvanced, style: Theme.of(context).textTheme.bodyMedium),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    children: [
                      SliderRow(
                        label: l.audioWakeGain,
                        value: wake.gainDb.toDouble(),
                        min: 0,
                        max: WakeSettings.maxGainDb.toDouble(),
                        divisions: WakeSettings.maxGainDb ~/ 3, // the firmware applies it in 3 dB steps
                        valueText: l.audioWakeGainValue(wake.gainDb),
                        onChanged: (v) => cubit.preview(wake: wake.copyWith(gainDb: v.round())),
                        onChangeEnd: (v) => cubit.setWakeGain(v.round()),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(l.audioWakeGainHint, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
                _WakeTestButton(test: test, phrase: wake.phrase),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wake word choice tile (design: height 56, teal border when selected)
class _PhraseButton extends StatelessWidget {
  const _PhraseButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: selected ? null : onTap,
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: t.bodyLarge?.copyWith(
                      fontSize: selected ? 16 : 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WakeTestButton extends StatelessWidget {
  const _WakeTestButton({required this.test, required this.phrase});

  final WakeTest? test;
  final WakePhrase phrase;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = test;
    final running = t?.running ?? false;
    final name = phrase == WakePhrase.computer ? l.audioPhraseComputer : l.audioPhraseAlexa;
    final String? info = t == null
        ? null
        : running
            ? '${l.audioWakeTestHint(name)}\n${l.audioWakeTestCount(t.detections)}'
            : l.audioWakeTestDone(t.detections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: running ? null : () => context.read<AudioCubit>().startWakeTest(),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(running ? l.audioWakeTestRunning(t!.remaining) : l.audioWakeTest),
        ),
        if (info != null) ...[
          const SizedBox(height: 8),
          Text(info,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14)),
        ],
      ],
    );
  }
}

class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.audio});

  final AudioSettings audio;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AudioCubit>();
    return AppCard(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              SliderRow(
                label: l.audioVolume,
                value: audio.volume.toDouble(),
                min: 0,
                max: AudioSettings.maxVolume.toDouble(),
                valueText: l.audioVolumeValue(audio.volume, AudioSettings.maxVolume),
                onChanged: (v) => cubit.preview(audio: audio.copyWith(volume: v.round())),
                onChangeEnd: (v) => cubit.setVolume(v.round()),
              ),
              const SizedBox(height: 8),
              SliderRow(
                label: l.audioDuck,
                value: audio.duckDb.toDouble(),
                min: 0,
                max: AudioSettings.maxDuckDb.toDouble(),
                valueText: l.audioDb(audio.duckDb),
                onChanged: (v) => cubit.preview(audio: audio.copyWith(duckDb: v.round())),
                onChangeEnd: (v) => cubit.setDuck(v.round()),
              ),
            ]),
          ),
          ListRow(
            title: l.audioMicGain,
            subtitle: l.audioMicGainHint,
            onTap: () => _pickMicGain(context, audio.micGain),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: () => _pickMicGain(context, audio.micGain),
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                child: Text(l.audioDb(audio.micGain)),
              ),
            ),
          ),
          SwitchRow(
            title: l.audioAutoGain,
            subtitle: l.audioAutoGainHint,
            value: audio.autoGain,
            onChanged: cubit.setAutoGain,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: cubit.testTone,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.volume_up_rounded, size: 20),
              label: Text(l.audioTestTone),
            ),
          ),
        ],
      ),
    );
  }

  /// Lets you pick only values the device accepts ([AudioSettings.micGainSteps])
  Future<void> _pickMicGain(BuildContext context, int current) async {
    final cubit = context.read<AudioCubit>();
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final l = AppLocalizations.of(sheet);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle(l.audioMicGain),
                  Flexible(
                    child: SingleChildScrollView(
                      child: ListGroup(children: [
                        for (final db in AudioSettings.micGainSteps.reversed)
                          ListRow(
                            title: l.audioDb(db),
                            selected: db == current,
                            trailing: db == current
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Icon(Icons.check, color: Theme.of(sheet).colorScheme.primary),
                                  )
                                : null,
                            onTap: () => Navigator.pop(sheet, db),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && picked != current) await cubit.setMicGain(picked);
  }
}

class _LedCard extends StatelessWidget {
  const _LedCard({required this.brightness});

  final int brightness;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<AudioCubit>();
    return AppCard(
      child: SliderRow(
        label: l.audioLed,
        value: brightness.toDouble(),
        min: 0,
        max: 100,
        valueText: l.audioPercent(brightness),
        onChanged: (v) => cubit.preview(ledBrightness: v.round()),
        onChangeEnd: (v) => cubit.setLedBrightness(v.round()),
      ),
    );
  }
}
