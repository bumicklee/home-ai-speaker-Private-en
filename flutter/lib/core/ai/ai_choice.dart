/// AI company × conversation mode (design document docs/design-voice-saver-mode.md Sections 11.1, 11.4). Same names as the firmware's `assistant` settings and `/status.ai`.
library;

import 'package:equatable/equatable.dart';

import '../constants/ble_protocol.dart';

/// Assistant setting `ai_provider`
enum AiProvider {
  openai('openai', SecretKey.openai),
  gemini('gemini', SecretKey.gemini);

  const AiProvider(this.id, this.secretKey);

  final String id;

  /// Key name in the speaker's secure storage (`secret.set`, `/status.secrets`)
  final String secretKey;

  /// Display name (company names are not translated)
  String get displayName => switch (this) {
        openai => 'OpenAI',
        gemini => 'Gemini',
      };

  /// Key in the assistant settings that holds this company's mode (`mode_openai`, `mode_gemini`)
  String get modeSettingKey => 'mode_$id';

  AiProvider get other => this == openai ? gemini : openai;

  static AiProvider? tryParse(Object? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// `mode_openai` / `mode_gemini`: Live / Saver
enum AiMode {
  live('live'),
  saver('saver');

  const AiMode(this.id);

  final String id;

  static AiMode? tryParse(Object? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// A combination name such as `"openai.saver"` (`/status.ai.available`)
String aiCombo(AiProvider p, AiMode m) => '${p.id}.${m.id}';

/// `ai` in `GET /status` — the AI in use now and the combinations this firmware supports
class AiStatus extends Equatable {
  const AiStatus({required this.provider, required this.mode, required this.available, this.reported = true});

  /// Old firmware (no `ai`): OpenAI Live only
  static const legacy = AiStatus(
    provider: AiProvider.openai,
    mode: AiMode.live,
    available: {'openai.live'},
    reported: false,
  );

  /// Missing or unknown values are treated as old firmware
  factory AiStatus.fromJson(Object? json) {
    if (json is! Map) return legacy;
    final list = json['available'];
    final available = <String>{
      if (list is List)
        for (final a in list)
          if (a is String) a,
    };
    return AiStatus(
      provider: AiProvider.tryParse(json['provider']) ?? AiProvider.openai,
      mode: AiMode.tryParse(json['mode']) ?? AiMode.live,
      available: list is List ? available : legacy.available,
    );
  }

  final AiProvider provider;
  final AiMode mode;

  /// Combinations this firmware supports now (`openai.live` …)
  final Set<String> available;

  /// Whether the firmware reported `ai` (false for old firmware)
  final bool reported;

  bool isAvailable(AiProvider p, AiMode m) => available.contains(aiCombo(p, m));

  /// Whether this company supports at least one mode
  bool providerAvailable(AiProvider p) => AiMode.values.any((m) => isAvailable(p, m));

  @override
  List<Object?> get props => [provider, mode, available, reported];
}
