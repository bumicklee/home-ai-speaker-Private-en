import 'package:equatable/equatable.dart';

import '../../../../core/ai/ai_choice.dart';

/// `/media/now`, WS `media_state`
class MediaNow extends Equatable {
  const MediaNow({this.source = 'none', this.state = 'stopped', this.title = '', this.artist = '', this.station = ''});

  /// none / radio / spotify
  final String source;

  /// stopped / buffering / playing / paused
  final String state;
  final String title;
  final String artist;
  final String station;

  bool get isActive => source != 'none' && state != 'stopped';

  @override
  List<Object?> get props => [source, state, title, artist, station];
}

/// The parts of `/api/v1/status` used on the home screen
class DeviceStatus extends Equatable {
  const DeviceStatus({
    required this.firmware,
    required this.uptime,
    this.wifiRssi,
    required this.voiceState,
    required this.media,
    required this.volume,
    required this.secrets,
    required this.telegramState,
    required this.telegramUnread,
    required this.spotifyState,
    this.ai = AiStatus.legacy,
  });

  final String firmware;
  final Duration uptime;
  final int? wifiRssi;

  /// idle / wake_ack / connecting / live / closing
  final String voiceState;
  final MediaNow media;

  /// 0–80
  final int volume;
  final Map<String, bool> secrets;
  final String telegramState;
  final int telegramUnread;
  final String spotifyState;

  /// The AI and mode in use (shown on the home card as "OpenAI · Saver mode")
  final AiStatus ai;

  bool get hasOpenAiKey => secrets['openai_key'] ?? false;
  bool get isTalking => voiceState != 'idle';

  DeviceStatus copyWith({String? voiceState, MediaNow? media, int? volume, int? telegramUnread, String? telegramState}) =>
      DeviceStatus(
        firmware: firmware,
        uptime: uptime,
        wifiRssi: wifiRssi,
        voiceState: voiceState ?? this.voiceState,
        media: media ?? this.media,
        volume: volume ?? this.volume,
        secrets: secrets,
        telegramState: telegramState ?? this.telegramState,
        telegramUnread: telegramUnread ?? this.telegramUnread,
        spotifyState: spotifyState,
        ai: ai,
      );

  @override
  List<Object?> get props =>
      [firmware, uptime, wifiRssi, voiceState, media, volume, secrets, telegramState, telegramUnread, spotifyState, ai];
}
