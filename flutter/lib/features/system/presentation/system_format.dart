/// System screen values → text (kept outside the screen so they're easy to test)
library;

import '../../../l10n/app_localizations.dart';
import '../domain/entities/system_status.dart';

/// "3 h 12 min"; over a day, "2 d 3 h"
String formatUptime(AppLocalizations l, Duration d) {
  if (d.inDays > 0) return l.sysUptimeDays(d.inDays, d.inHours % 24);
  if (d.inHours > 0) return l.sysUptimeHours(d.inHours, d.inMinutes % 60);
  return l.sysUptimeMinutes(d.inMinutes);
}

/// "Good (-51 dBm)", or "Not connected" if not connected
String formatWifi(AppLocalizations l, int? rssi) {
  if (rssi == null) return l.sysWifiNone;
  return switch (WifiBand.fromRssi(rssi)) {
    WifiBand.good => l.sysWifiGood(rssi),
    WifiBand.fair => l.sysWifiFair(rssi),
    WifiBand.weak => l.sysWifiWeak(rssi),
  };
}

String formatResetReason(AppLocalizations l, int code) => switch (ResetCause.fromCode(code)) {
      ResetCause.powerOn => l.sysResetPowerOn,
      ResetCause.software => l.sysResetSoftware,
      ResetCause.crash => l.sysResetCrash,
      ResetCause.watchdog => l.sysResetWatchdog,
      ResetCause.brownout => l.sysResetBrownout,
      ResetCause.other => l.sysResetOther(code),
    };

String formatKb(AppLocalizations l, int? bytes) => bytes == null ? '–' : l.sysKb(bytes ~/ 1024);
