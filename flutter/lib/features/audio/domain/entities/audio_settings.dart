import 'package:equatable/equatable.dart';

/// `/settings/audio` (firmware `device_settings.c` audio_get/audio_set).
/// `spotify_pause_on_voice` is not handled: Spotify is turned off in this build
class AudioSettings extends Equatable {
  const AudioSettings({required this.volume, required this.micGain, required this.autoGain, required this.duckDb});

  /// 0–[maxVolume]
  final int volume;

  /// Hardware microphone gain in dB (one of [micGainSteps])
  final int micGain;
  final bool autoGain;

  /// How much to lower the music during a conversation, 0–[maxDuckDb]
  final int duckDb;

  static const maxVolume = 80; // APP_VOLUME_MAX
  static const maxDuckDb = 40;

  /// Values you can pick for the microphone gain. The codec works in 3 dB steps and has no 33 dB (console `mic`, mic_control.c)
  static const micGainSteps = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 36];

  AudioSettings copyWith({int? volume, int? micGain, bool? autoGain, int? duckDb}) => AudioSettings(
        volume: volume ?? this.volume,
        micGain: micGain ?? this.micGain,
        autoGain: autoGain ?? this.autoGain,
        duckDb: duckDb ?? this.duckDb,
      );

  @override
  List<Object?> get props => [volume, micGain, autoGain, duckDb];
}

/// Wake word (firmware values: 0 Alexa — Jarvis before 2026-10-04, 1 Computer)
enum WakePhrase {
  alexa(0),
  computer(1);

  const WakePhrase(this.value);
  final int value;

  static WakePhrase fromValue(int? v) => v == 0 ? alexa : computer;
}

/// `/settings/wake` (firmware `device_settings.c` wake_get/wake_set). Defaults: Computer, sensitivity 80, +12 dB
class WakeSettings extends Equatable {
  const WakeSettings({required this.enabled, required this.phrase, required this.sensitivity, required this.gainDb});

  final bool enabled;
  final WakePhrase phrase;

  /// 0–100. Higher hears the wake word better but gives more false triggers
  final int sensitivity;

  /// Digital gain applied only to the sound going to the wake word detector, 0–[maxGainDb] (applied in 3 dB steps, wake.c)
  final int gainDb;

  static const maxGainDb = 24;

  WakeSettings copyWith({bool? enabled, WakePhrase? phrase, int? sensitivity, int? gainDb}) => WakeSettings(
        enabled: enabled ?? this.enabled,
        phrase: phrase ?? this.phrase,
        sensitivity: sensitivity ?? this.sensitivity,
        gainDb: gainDb ?? this.gainDb,
      );

  @override
  List<Object?> get props => [enabled, phrase, sensitivity, gainDb];
}
