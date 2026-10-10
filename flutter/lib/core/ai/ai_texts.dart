/// AI and conversation mode text (shared by first-time setup, Assistant > AI & Conversation Mode, Home, and English Tutor)
library;

import '../../l10n/app_localizations.dart';
import 'ai_choice.dart';

extension AiTexts on AppLocalizations {
  String aiModeName(AiMode m) => m == AiMode.saver ? aiModeSaver : aiModeLive;

  /// "OpenAI · Saver mode"
  String aiChoiceLabel(AiProvider p, AiMode m) => aiLabel(p.displayName, aiModeName(m));

  /// One line on the first-time setup card: "about ₩15,000 a month · answers 1–2 seconds slower"
  String aiShortSub(AiProvider p, AiMode m) {
    final price = switch ((p, m)) {
      (AiProvider.openai, AiMode.saver) => aiPriceShortOpenAiSaver,
      (AiProvider.openai, AiMode.live) => aiPriceShortOpenAiLive,
      (AiProvider.gemini, AiMode.saver) => aiPriceShortGeminiSaver,
      (AiProvider.gemini, AiMode.live) => aiPriceShortGeminiLive,
    };
    return '$price · ${m == AiMode.saver ? aiShortSaverNote : aiShortLiveNote}';
  }

  /// Monthly estimate (1 hour a day)
  String aiPrice(AiProvider p, AiMode m) => switch ((p, m)) {
        (AiProvider.openai, AiMode.saver) => aiPriceOpenAiSaver,
        (AiProvider.openai, AiMode.live) => aiPriceOpenAiLive,
        (AiProvider.gemini, AiMode.saver) => aiPriceGeminiSaver,
        (AiProvider.gemini, AiMode.live) => aiPriceGeminiLive,
      };

  String aiDescription(AiProvider p, AiMode m) => switch ((p, m)) {
        (AiProvider.openai, AiMode.saver) => aiDescOpenAiSaver,
        (AiProvider.openai, AiMode.live) => aiDescOpenAiLive,
        (AiProvider.gemini, AiMode.saver) => aiDescGeminiSaver,
        (AiProvider.gemini, AiMode.live) => aiDescGeminiLive,
      };

  List<String> aiTags(AiProvider p, AiMode m) => m == AiMode.live
      ? [aiTagInstant, aiTagBargeIn]
      : [p == AiProvider.openai ? aiTagOneEighth : aiTagCheapest, aiTagNoBargeIn];
}
