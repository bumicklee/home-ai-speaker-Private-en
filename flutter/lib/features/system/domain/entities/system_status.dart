import 'package:equatable/equatable.dart';

import '../../../../core/ai/ai_choice.dart';

/// Wi-Fi signal bands (same thresholds as the Home screen)
enum WifiBand {
  good,
  fair,
  weak;

  static WifiBand fromRssi(int rssi) => rssi >= -60
      ? good
      : rssi >= -72
          ? fair
          : weak;
}

/// Why the speaker last started (`esp_reset_reason_t` grouped for display)
enum ResetCause {
  powerOn, // 1 power on
  software, // 3 restart from the app or by voice, OTA
  crash, // 4 error (panic)
  watchdog, // 5–7 not responding
  brownout, // 9 low power
  other;

  static ResetCause fromCode(int code) => switch (code) {
        1 => powerOn,
        3 => software,
        4 => crash,
        5 || 6 || 7 => watchdog,
        9 => brownout,
        _ => other,
      };
}

/// The parts of `/api/v1/status` used by the System screen (firmware `device_info.c` device_status)
class SystemStatus extends Equatable {
  const SystemStatus({
    required this.firmware,
    this.buildDate = '',
    required this.uptime,
    this.wifiRssi,
    this.resetReason = 0,
    this.heapInternalFree,
    this.heapInternalMin,
    this.psramFree,
    this.voiceState = 'idle',
    this.secrets = const {},
    this.failures = const [],
    this.ai = AiStatus.legacy,
  });

  final String firmware;

  /// Build time ("Oct  3 2026 10:12:00", exactly as the compiler formats it)
  final String buildDate;
  final Duration uptime;

  /// null if not on Wi-Fi
  final int? wifiRssi;

  /// `esp_reset_reason()` number
  final int resetReason;

  /// Internal RAM (bytes)
  final int? heapInternalFree;
  final int? heapInternalMin;
  final int? psramFree;
  final String voiceState;

  /// Only whether each is saved (openai_key, gemini_key, tg_bot_token, spotify, stock_key)
  final Map<String, bool> secrets;

  /// Recent failures (the firmware leaves this empty for now)
  final List<String> failures;

  /// The AI in use and the combinations this firmware supports ([AiStatus.legacy] for old firmware)
  final AiStatus ai;

  WifiBand? get wifiBand => wifiRssi == null ? null : WifiBand.fromRssi(wifiRssi!);
  ResetCause get resetCause => ResetCause.fromCode(resetReason);
  bool hasSecret(String key) => secrets[key] ?? false;

  SystemStatus withSecret(String key, bool saved) => SystemStatus(
        firmware: firmware,
        buildDate: buildDate,
        uptime: uptime,
        wifiRssi: wifiRssi,
        resetReason: resetReason,
        heapInternalFree: heapInternalFree,
        heapInternalMin: heapInternalMin,
        psramFree: psramFree,
        voiceState: voiceState,
        secrets: {...secrets, key: saved},
        failures: failures,
        ai: ai,
      );

  @override
  List<Object?> get props => [
        firmware,
        buildDate,
        uptime,
        wifiRssi,
        resetReason,
        heapInternalFree,
        heapInternalMin,
        psramFree,
        voiceState,
        secrets,
        failures,
        ai,
      ];
}

/// Number of phones that can register with one speaker (firmware `APP_API_MAX_PHONES`)
const maxPhones = 5;

/// One row of `GET /system/phones`
class RegisteredPhone extends Equatable {
  const RegisteredPhone({required this.phoneId, required this.name, this.created, this.self = false});

  final String phoneId;
  final String name;

  /// Registration time. null if registered before the speaker's clock was set
  final DateTime? created;

  /// The phone making this request (this phone)
  final bool self;

  @override
  List<Object?> get props => [phoneId, name, created, self];
}
