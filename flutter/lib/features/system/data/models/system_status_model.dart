import 'dart:convert';

import '../../../../core/ai/ai_choice.dart';
import '../../domain/entities/system_status.dart';

/// `/status` JSON from firmware `device_info.c` → SystemStatus
class SystemStatusModel {
  SystemStatusModel._();

  static SystemStatus fromJson(Map<String, dynamic> j) => SystemStatus(
        firmware: j['fw'] as String? ?? '',
        buildDate: j['build_date'] as String? ?? '',
        uptime: Duration(seconds: (j['uptime_s'] as num? ?? 0).toInt()),
        wifiRssi: (j['wifi_rssi'] as num?)?.toInt(),
        resetReason: (j['reset_reason'] as num? ?? 0).toInt(),
        heapInternalFree: (j['heap_internal_free'] as num?)?.toInt(),
        heapInternalMin: (j['heap_internal_min'] as num?)?.toInt(),
        psramFree: (j['psram_free'] as num?)?.toInt(),
        voiceState: j['voice_state'] as String? ?? 'idle',
        secrets: {
          for (final e in (j['secrets'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value == true,
        },
        // The format isn't settled yet (sys/fail_log not implemented). Show text as is, otherwise as JSON
        failures: [
          for (final f in j['failures'] as List<dynamic>? ?? const []) f is String ? f : jsonEncode(f),
        ],
        ai: AiStatus.fromJson(j['ai']),
      );
}

/// `GET /system/phones` → `{"phones": [...]}` (`local_api.c` get_phones)
class RegisteredPhoneModel {
  RegisteredPhoneModel._();

  static List<RegisteredPhone> listFromJson(dynamic body) {
    final list = body is Map ? body['phones'] : body;
    return [
      for (final p in list as List<dynamic>? ?? const [])
        if (p is Map<String, dynamic>) fromJson(p),
    ];
  }

  static RegisteredPhone fromJson(Map<String, dynamic> j) {
    final created = (j['created'] as num? ?? 0).toInt();
    return RegisteredPhone(
      phoneId: j['phone_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      // 0 = registered before the speaker's clock was set
      created: created > 0 ? DateTime.fromMillisecondsSinceEpoch(created * 1000) : null,
      self: j['self'] == true,
    );
  }
}
