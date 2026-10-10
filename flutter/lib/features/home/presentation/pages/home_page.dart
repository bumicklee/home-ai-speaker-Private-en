import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/routes.dart';
import '../../../../core/ai/ai_texts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../devices/domain/entities/device_status.dart';
import '../../../devices/presentation/bloc/devices_cubit.dart';
import '../../../devices/presentation/bloc/home_cubit.dart';
import '../../../notes/data/repositories/notes_repository.dart';
import '../../../notes/domain/entities/note.dart';
import '../../../notes/domain/notes_view.dart';
import '../../../notes/presentation/pages/notes_texts.dart';
import '../widgets/device_picker_sheet.dart';

/// Home (design "Home"): status card, now playing, Telegram, feature menu
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<HomeCubit>()..refresh(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<DevicesCubit, DevicesState>(
      builder: (context, devices) {
        if (!devices.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (devices.devices.isEmpty) return const _EmptyHome();
        final name = devices.selected?.name ?? l.homeTitle;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: TextButton(
              onPressed: () => showDevicePicker(context),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more),
              ]),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton.outlined(
                  tooltip: l.homeAddSpeaker,
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.provisioning),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          body: BlocBuilder<HomeCubit, HomeState>(
            builder: (context, home) => RefreshIndicator(
              onRefresh: () => context.read<HomeCubit>().refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (home.unauthorized)
                    const _UnauthorizedCard()
                  else if (home.status == null && home.failure != null)
                    _UnreachableCard(locating: devices.locating)
                  else ...[
                    _VoiceCard(status: home.status, busy: home.busy),
                    const SizedBox(height: 12),
                    _NowPlayingCard(status: home.status),
                    const SizedBox(height: 12),
                    _TelegramRow(status: home.status),
                  ],
                  const SizedBox(height: 12),
                  const _FeatureTiles(),
                  const SizedBox(height: 10),
                  const _MenuGrid(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({required this.status, required this.busy});

  final DeviceStatus? status;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final voice = status?.voiceState ?? 'idle';
    final talking = voice == 'live';
    final connecting = voice == 'connecting' || voice == 'wake_ack';
    final rssi = status?.wifiRssi;
    final ai = status?.ai;
    final wifi = rssi == null
        ? ''
        : rssi >= -60
            ? l.homeWifiGood
            : rssi >= -72
                ? l.homeWifiFair
                : l.homeWifiWeak;
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const StatusDot(color: AppColors.accentOnDark, size: 8),
              const SizedBox(width: 8),
              Expanded(
                child: Text(wifi.isEmpty ? l.homeConnected : '${l.homeConnected} · $wifi',
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
              ),
              if (ai != null) ...[
                const SizedBox(width: 8),
                // The AI and mode in use now (design docs/design-voice-saver-mode.md 11.4)
                Text(l.aiChoiceLabel(ai.provider, ai.mode),
                    style: t.bodySmall?.copyWith(color: const Color(0xFFD6F0EE), fontSize: 12)),
              ],
            ]),
            const SizedBox(height: 16),
            Text(
              talking ? l.homeTalkingTitle : (connecting ? l.homeConnectingTitle : l.homeIdleTitle),
              style: t.headlineSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(talking ? l.homeTalkingBody : l.homeIdleBody,
                style: t.bodyMedium?.copyWith(color: const Color(0xFFD6F0EE))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: status == null || busy ? null : () => context.read<HomeCubit>().toggleVoice(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.accent,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: Icon(talking ? Icons.stop_circle_outlined : Icons.mic_none_rounded),
              label: Text(talking ? l.homeStopTalk : l.homeStartTalk),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = status?.media ?? const MediaNow();
    final cubit = context.read<HomeCubit>();
    final playing = media.state == 'playing';
    final label = switch (media.state) {
      'playing' => l.homeRadioPlaying,
      'paused' => l.homeRadioPaused,
      'buffering' => l.homeRadioBuffering,
      _ => l.homeNothingPlaying,
    };
    final title = media.station.isNotEmpty ? media.station : media.title;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.radio_rounded, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                if (media.isActive) ...[
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (media.title.isNotEmpty && media.title != title)
                    Text(media.title, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ] else
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.radio),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    child: Text(l.homeOpenRadio),
                  ),
              ]),
            ),
          ]),
          if (media.isActive) ...[
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton.filledTonal(
                  tooltip: l.homePrevious, onPressed: () => cubit.media('previous'), icon: const Icon(Icons.skip_previous_rounded)),
              IconButton.filled(
                tooltip: playing ? l.homePause : l.homeResume,
                iconSize: 30,
                style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.onSurface,
                    foregroundColor: theme.colorScheme.surface,
                    minimumSize: const Size(64, 64)),
                onPressed: () => cubit.media(playing ? 'pause' : 'resume'),
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton.filledTonal(
                  tooltip: l.homeNext, onPressed: () => cubit.media('next'), icon: const Icon(Icons.skip_next_rounded)),
              IconButton.filledTonal(
                  tooltip: l.homeStop, onPressed: () => cubit.media('stop'), icon: const Icon(Icons.stop_rounded)),
            ]),
          ],
          const SizedBox(height: 8),
          _VolumeSlider(volume: status?.volume),
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({required this.volume});

  final int? volume;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = _dragging ?? (widget.volume ?? 0).toDouble();
    return Row(children: [
      Icon(Icons.volume_up_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, semanticLabel: l.homeVolume),
      Expanded(
        child: Slider(
          value: v.clamp(0, 80),
          max: 80,
          divisions: 16,
          semanticFormatterCallback: (x) => '${l.homeVolume} ${x.round()}',
          onChanged: widget.volume == null ? null : (x) => setState(() => _dragging = x),
          onChangeEnd: (x) {
            setState(() => _dragging = null);
            context.read<HomeCubit>().setVolume(x.round());
          },
        ),
      ),
      SizedBox(
          width: 32,
          child: Text('${v.round()}',
              textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]);
  }
}

class _TelegramRow extends StatelessWidget {
  const _TelegramRow({required this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unread = status?.telegramUnread ?? 0;
    final configured = (status?.telegramState ?? 'off') != 'off';
    return ListGroup(children: [
      ListRow(
        leading: Icon(Icons.send_rounded, color: theme.colorScheme.primary),
        title: l.homeTelegram,
        onTap: () => Navigator.pushNamed(context, AppRoutes.telegram),
        trailing: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: !configured
              ? Text(l.homeTelegramSetup,
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))
              : unread > 0
                  ? DecoratedBox(
                      decoration: BoxDecoration(color: AppColors.warn, borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text(l.homeTelegramUnread(unread),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    )
                  : Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    ]);
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      (Icons.radio_rounded, l.homeMenuRadio, AppRoutes.radio),
      (Icons.chat_bubble_outline_rounded, l.homeMenuAssistant, AppRoutes.assistant),
      (Icons.tune_rounded, l.homeMenuAudio, AppRoutes.audio),
      (Icons.settings_outlined, l.homeMenuSystem, AppRoutes.system),
    ];
    // Four per row: so Home fits on one screen without scrolling even while the radio plays (2026-10-03 user request).
    // All four cells get the same height, and labels stay on one line (if narrow, shrink slightly instead of wrapping)
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pushNamed(context, items[i].$3),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(items[i].$1, color: theme.colorScheme.primary, size: 22),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              items[i].$2,
                              maxLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// English Tutor · Notes & Schedule (design "Home": side by side, half width each, above the menu)
class _FeatureTiles extends StatelessWidget {
  const _FeatureTiles();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: _FeatureTile(
            icon: Icons.menu_book_rounded,
            title: l.engTitle,
            subtitle: l.engHomeSubtitle,
            onTap: () => Navigator.pushNamed(context, AppRoutes.english),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: _NotesTile()),
      ]),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The subtitle comes from the phone's copy ("오늘 2개 · 3시 병원", 2 today · hospital at 3). Synced with the speaker once when Home opens
class _NotesTile extends StatefulWidget {
  const _NotesTile();

  @override
  State<_NotesTile> createState() => _NotesTileState();
}

class _NotesTileState extends State<_NotesTile> {
  List<Note> _items = const [];

  @override
  void initState() {
    super.initState();
    _load(sync: true);
  }

  Future<void> _load({bool sync = false}) async {
    if (!sl.isRegistered<NotesRepository>()) return;
    final repo = sl<NotesRepository>();
    final cached = await repo.cached();
    if (mounted) setState(() => _items = cached.items);
    if (!sync) return;
    final r = await repo.sync();
    r.fold((_) {}, (c) {
      if (mounted) setState(() => _items = c.items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = todaySummary(_items, DateTime.now());
    final next = today.next;
    final subtitle = today.count == 0
        ? l.notesHomeEmpty
        : next == null
            ? l.notesHomeTodayCount(today.count)
            : l.notesHomeToday(today.count, next.isAllDay ? next.title : '${shortClock(l, next.start!.at)} ${next.title}');
    return _FeatureTile(
      icon: Icons.event_note_rounded,
      title: l.notesTitle,
      subtitle: subtitle,
      onTap: () async {
        await Navigator.pushNamed(context, AppRoutes.notes);
        await _load();
      },
    );
  }
}

class _UnreachableCard extends StatelessWidget {
  const _UnreachableCard({required this.locating});

  final bool locating;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NoticeBox(
      warning: true,
      icon: Icons.wifi_off_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.homeUnreachableTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(l.homeUnreachableBody),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: locating
              ? null
              : () async {
                  final home = context.read<HomeCubit>();
                  if (await context.read<DevicesCubit>().locate()) await home.refresh();
                },
          child: Text(l.homeFindAgain),
        ),
      ]),
    );
  }
}

class _UnauthorizedCard extends StatelessWidget {
  const _UnauthorizedCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NoticeBox(
      warning: true,
      icon: Icons.lock_outline_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.homeUnauthorizedTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(l.homeUnauthorizedBody),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.provisioning),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(l.homeRegisterAgain),
        ),
      ]),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.speaker_rounded, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(l.homeEmptyTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l.homeEmptyBody, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.provisioning),
                child: Text(l.homeAddSpeaker),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
