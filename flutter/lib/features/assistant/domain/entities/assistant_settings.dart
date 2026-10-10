import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../../core/ai/ai_choice.dart';

/// Same values as the validation in firmware `assistant.c` (settings_valid, TIMEZONES)
class AssistantLimits {
  AssistantLimits._();

  /// UTF-8 byte count (not character count; one Hangul character = 3 bytes)
  static const nameBytes = 32;
  static const purposeBytes = 600;
  static const locationBytes = 96;

  /// Maximum number of memories (MEMORY_LIMIT)
  static const memories = 12;

  /// Spoken language (assistant.c: ko | en)
  static const languages = ['ko', 'en'];

  /// Units (metric = °C·km, imperial = °F·mi)
  static const units = ['metric', 'imperial'];

  /// Only the time zones on the chip (assistant.c `TIMEZONES`). Any other name gives INVALID_ARG
  static const timezones = [
    'Asia/Seoul',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Asia/Singapore',
    'UTC',
    'Europe/London',
    'Europe/Berlin',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Australia/Sydney',
  ];
}

int utf8Bytes(String s) => utf8.encode(s).length;

/// An item that failed the pre-save check
enum AssistantFieldError { nameEmpty, nameTooLong, purposeTooLong, locationTooLong }

/// `/api/v1/settings/assistant` (13 keys: the old 10 + ai_provider, mode_openai, mode_gemini)
class AssistantSettings extends Equatable {
  const AssistantSettings({
    required this.name,
    required this.purpose,
    required this.language,
    required this.voice,
    required this.location,
    required this.units,
    required this.webSearch,
    required this.deviceControls,
    required this.autoMemory,
    required this.timezone,
    this.aiProvider = AiProvider.openai,
    this.modeOpenai = AiMode.live,
    this.modeGemini = AiMode.saver,
  });

  final String name;
  final String purpose;
  final String language;

  /// Takes effect from the next conversation
  final String voice;

  /// Neighborhood name only (coordinates are not sent; design document Section 3.0)
  final String location;
  final String units;
  final bool webSearch;

  /// When off, device tools such as volume, radio and memory are not given to the assistant
  final bool deviceControls;
  final bool autoMemory;
  final String timezone;

  /// The AI used for conversation (switching to an AI without a key makes the device return 409 NO_API_KEY)
  final AiProvider aiProvider;

  /// The mode last chosen for each provider (switching provider switches to that provider's mode)
  final AiMode modeOpenai;
  final AiMode modeGemini;

  AiMode modeOf(AiProvider p) => p == AiProvider.openai ? modeOpenai : modeGemini;

  /// The mode in use now
  AiMode get aiMode => modeOf(aiProvider);

  /// Finds values the device would reject, ahead of time. Empty list if none
  List<AssistantFieldError> validate() => [
        if (name.trim().isEmpty) AssistantFieldError.nameEmpty,
        if (utf8Bytes(name) > AssistantLimits.nameBytes) AssistantFieldError.nameTooLong,
        if (utf8Bytes(purpose) > AssistantLimits.purposeBytes) AssistantFieldError.purposeTooLong,
        if (utf8Bytes(location) > AssistantLimits.locationBytes) AssistantFieldError.locationTooLong,
      ];

  AssistantSettings copyWith({
    String? name,
    String? purpose,
    String? language,
    String? voice,
    String? location,
    String? units,
    bool? webSearch,
    bool? deviceControls,
    bool? autoMemory,
    String? timezone,
    AiProvider? aiProvider,
    AiMode? modeOpenai,
    AiMode? modeGemini,
  }) =>
      AssistantSettings(
        name: name ?? this.name,
        purpose: purpose ?? this.purpose,
        language: language ?? this.language,
        voice: voice ?? this.voice,
        location: location ?? this.location,
        units: units ?? this.units,
        webSearch: webSearch ?? this.webSearch,
        deviceControls: deviceControls ?? this.deviceControls,
        autoMemory: autoMemory ?? this.autoMemory,
        timezone: timezone ?? this.timezone,
        aiProvider: aiProvider ?? this.aiProvider,
        modeOpenai: modeOpenai ?? this.modeOpenai,
        modeGemini: modeGemini ?? this.modeGemini,
      );

  @override
  List<Object?> get props => [
        name,
        purpose,
        language,
        voice,
        location,
        units,
        webSearch,
        deviceControls,
        autoMemory,
        timezone,
        aiProvider,
        modeOpenai,
        modeGemini,
      ];
}

/// One assistant memory (key: lowercase, digits, _ 1–32 chars; value: 1–160 bytes)
class AssistantMemory extends Equatable {
  const AssistantMemory({required this.key, required this.value});

  final String key;
  final String value;

  @override
  List<Object?> get props => [key, value];
}
