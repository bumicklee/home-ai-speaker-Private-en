# versions.md — versions verified by this repository

Any commit that changes a version also updates this file in the same commit. The values in the tables are the ones actually built and verified. The full convention is in Appendix D.5 of the book.

## Tools

| Tool | Version | Check command |
|:--|:--|:--|
| ESP-IDF | v5.5 (5.5.0) | `idf.py --version` |
| Python (ESP-IDF venv) | 3.14 | `export.sh` output |
| CMake / Ninja | 4.1.2 / 1.13.1 | `cmake --version` |
| Flutter / Dart | 3.38.5 / 3.10.4 | `flutter --version` |

## Firmware

| Item | Value |
|:--|:--|
| APP_FW_VERSION | 0.1.0 |
| protocol_version | 1 |
| Live model (APP_LIVE_MODEL_DEFAULT) | gpt-live-1 |
| Text model (APP_BACKEND_MODEL_DEFAULT) | gpt-5.6-luna |
| Transcription (SAVER_STT_MODEL) | gpt-transcribe |
| Speech synthesis (SAVER_TTS_MODEL) | gpt-4o-mini-tts |
| Gemini Saver (APP_GEMINI_MODEL_DEFAULT) | gemini-3.1-flash-lite |
| Gemini speech synthesis (APP_GEMINI_TTS_MODEL_DEFAULT) | gemini-3.8-flash-lite-tts |
| Gemini Live (APP_GEMINI_LIVE_MODEL_DEFAULT) | gemini-3.8-live |
| Managed components | see `firmware/dependencies.lock` (esp-sr 2.1.5, esp_codec_dev 1.5.1, …) |

## App

| Item | Value |
|:--|:--|
| version | 1.0.0+1 |
| Packages | see `flutter/pubspec.lock` (flutter_bloc 8.1.6, flutter_blue_plus 1.36.8, …) |
| iOS deployment target | 13.0 (in the code only, outside the scope of the book) |

## Change Log

- First written: the book's finished source. ESP-IDF 5.5.0, Flutter 3.38.5. Passed on real hardware through Chapter 18 (OpenAI and Gemini × Live and Saver, all four combinations).
