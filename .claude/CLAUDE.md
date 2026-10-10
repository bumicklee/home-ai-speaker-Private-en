# home-ai-speaker

A repository for building along with the home AI speaker book built with Claude Code. It consists of the Waveshare ESP32-S3-AUDIO-Board firmware (`firmware/`, ESP-IDF v5.5) and the setup app AI-PA (`flutter/`, Android).

## Build

- Firmware: `source ~/esp/esp-idf-v5.5/export.sh` → `cd firmware && idf.py build` → `idf.py -p <port> flash monitor`
- App: `cd flutter && flutter pub get && flutter analyze && flutter test` → `../scripts/run-flutter.sh android` (if the script doesn't exist yet, `flutter run`)

## Rules

- Firmware working rules are in the `esp32-firmware` skill, app working rules in the `flutter-app` skill, and plan, design, and failure report formats in the `speaker-method` skill.
- Secrets (AI keys, bot tokens, `certificates/*.pem`) don't go into code, logs, or Git.
- Do one step at a time, run the verification commands, and show the results.
- Commits are made only when the user asks.

## Documents

- `docs/01-plan/`: plan document and feature table (created in Chapter 2)
- `docs/design.md`: design document (created in Chapter 2). Per-feature design documents are `docs/design-<feature>.md`
- In the book's finished-source repository, the documents used during the build are in `docs/`. Read them for comparison
- `docs/HANDOFF.md`: the handoff document the next session reads first
