import 'package:equatable/equatable.dart';

import '../../../../core/ai/ai_choice.dart';

/// Values collected **before** the BLE connection (design document 3.4: so the BLE window doesn't run down while you leave the app to copy a key).
/// Kept in memory only and discarded after sending.
/// ① AI → that AI's key (required, or "this speaker already has the key saved") → ② conversation mode (docs/design-voice-saver-mode.md, Section 11.3)
class ProvisioningInput extends Equatable {
  const ProvisioningInput({
    this.provider = AiProvider.openai,
    this.mode = AiMode.saver,
    this.openAiKey = '',
    this.geminiKey = '',
    this.existingKey = false,
    this.telegramToken = '',
    required this.phoneName,
  });

  final AiProvider provider;
  final AiMode mode;

  /// If empty, use the key already on the speaker ([existingKey] must be on for the chosen AI)
  final String openAiKey;
  final String geminiKey;

  /// "이미 이 AI 키가 저장된 스피커예요" (This speaker already has this AI's key saved) — checked after connecting via `device.info.secrets`
  final bool existingKey;
  final String telegramToken;
  final String phoneName;

  String keyFor(AiProvider p) => p == AiProvider.openai ? openAiKey : geminiKey;

  /// Whether the key for the chosen AI was entered
  bool get hasChosenKey => keyFor(provider).isNotEmpty;

  /// Whether "스피커 찾기" (Find speaker) can be tapped: the chosen AI's key was entered, or the user said the speaker already has it
  bool get canSearch => hasChosenKey || existingKey;

  ProvisioningInput copyWith({
    AiProvider? provider,
    AiMode? mode,
    String? openAiKey,
    String? geminiKey,
    bool? existingKey,
  }) =>
      ProvisioningInput(
        provider: provider ?? this.provider,
        mode: mode ?? this.mode,
        openAiKey: openAiKey ?? this.openAiKey,
        geminiKey: geminiKey ?? this.geminiKey,
        existingKey: existingKey ?? this.existingKey,
        telegramToken: telegramToken,
        phoneName: phoneName,
      );

  static final openAiKeyPattern = RegExp(r'^sk-[A-Za-z0-9_\-]{20,}$');

  /// Google AI Studio key (loose check: AIza + 30 or more characters)
  static final geminiKeyPattern = RegExp(r'^AIza[0-9A-Za-z_\-]{30,}$');
  static final telegramTokenPattern = RegExp(r'^\d{5,}:[A-Za-z0-9_\-]{30,}$');

  static RegExp keyPattern(AiProvider p) => p == AiProvider.openai ? openAiKeyPattern : geminiKeyPattern;

  @override
  List<Object?> get props => [provider, mode, openAiKey, geminiKey, existingKey, telegramToken, phoneName];

  /// Keep secrets out of logs and toString
  @override
  String toString() => 'ProvisioningInput(phoneName: $phoneName, ai: ${aiCombo(provider, mode)}, '
      'openai: ${openAiKey.isNotEmpty}, gemini: ${geminiKey.isNotEmpty}, existing: $existingKey, '
      'tg: ${telegramToken.isNotEmpty})';
}
