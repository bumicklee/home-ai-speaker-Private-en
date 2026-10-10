import '../../domain/entities/audio_settings.dart';

/// JSON from the firmware's `device_settings.c` → entity
class AudioSettingsModel {
  static AudioSettings audioFromJson(Map<String, dynamic> j) => AudioSettings(
        volume: (j['volume'] as num? ?? 0).toInt(),
        micGain: (j['mic_gain'] as num? ?? 36).toInt(),
        autoGain: j['auto_gain'] == true,
        duckDb: (j['duck_db'] as num? ?? 20).toInt(),
      );

  static WakeSettings wakeFromJson(Map<String, dynamic> j) => WakeSettings(
        enabled: j['enabled'] != false,
        phrase: WakePhrase.fromValue((j['phrase'] as num?)?.toInt()),
        sensitivity: (j['sensitivity'] as num? ?? 80).toInt(),
        gainDb: (j['gain_db'] as num? ?? 12).toInt(),
      );

  static int ledFromJson(Map<String, dynamic> j) => (j['brightness'] as num? ?? 60).toInt();
}
