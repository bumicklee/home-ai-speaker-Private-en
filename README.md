# home-ai-speaker

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/bumicklee)


This is the finished source for the book *Building Our Home AI Speaker with Claude Code* (by Bumick Lee, published by uPaper).

It contains the firmware for a family AI speaker built on the [Waveshare ESP32-S3-AUDIO-Board](https://docs.waveshare.com/ESP32-S3-AUDIO-Board), and **AI-PA**, the Android app that sets up the speaker. There is only **one finished version**, as it stands after Chapter 21 of the book. There are no per-chapter intermediate snapshots.


- A voice assistant that answers in Korean when you call "Computer" (or "Alexa")
- Runs on an API key from OpenAI, Google Gemini, or both (Live mode / Saver mode)
- Internet radio, reading family Telegram messages aloud, note and schedule reminders, Korean conversation practice (Korean teacher)
- Works with just your phone and the speaker, no separate server (first-time setup over BLE, everyday control over the LAN on the same Wi-Fi)

## Folders

| Folder | Contents |
|:--|:--|
| `firmware/` | The speaker firmware (ESP-IDF v5.5, C) |
| `flutter/` | The setup app AI-PA (Flutter, Android) |
| `scripts/` | Scripts for running the app (`run-flutter.sh`) and making release builds (`build-flutter-release.sh`) |
| `.claude/` | This book's Claude Code harness: `CLAUDE.md`, three skills (`esp32-firmware`, `flutter-app`, `speaker-method`), and per-chapter verification agents |
| `.claude-plugin/` | Settings for installing the harness as a Claude Code plugin |
| `certificates/` | Where the OTA signing key goes. **The key is not included** |
| `docs/` | The feature table, design documents and app screen drawings used during the build. You write your own documents in Chapter 2 and compare them with these ([docs/README.md](docs/README.md)) |

## What This Repository Does Not Contain

It contains no API keys, Telegram bot tokens, Wi-Fi passwords or OTA signing keys. You create the keys yourself, following Chapter 0 (accounts and keys) and Chapter 1 (signing key) of the book. Secrets go from the app to the speaker over BLE only.

## Downloading

When you follow the book, you build everything yourself in your repository (`~/home-ai-speaker`), which you create in Chapter 1. Clone this finished source into a different folder so it doesn't overlap, and use it for comparison.

```bash
git clone https://github.com/bumicklee/home-ai-speaker-Private-en.git ~/home-ai-speaker-final
```

## Building the Firmware

You need: ESP-IDF v5.5 (`~/esp/esp-idf-v5.5`), a Waveshare ESP32-S3-AUDIO-Board

```bash
source ~/esp/esp-idf-v5.5/export.sh

# 1) Create the signing key (once. Without the key the build fails. Section 1.4.9 of the book)
mkdir -p certificates && chmod 700 certificates
espsecure.py generate_signing_key --version 2 --scheme rsa3072 certificates/ota_signing_key.pem
chmod 600 certificates/ota_signing_key.pem

# 2) Build and flash
cd firmware
idf.py build
idf.py -p <port> flash monitor
```

If you lose the signing key, you can no longer update speakers you have already installed over the air (USB still works). Back it up in a password manager.

## Running the App

You need: Flutter 3.38.5, an Android phone with USB debugging turned on (on the same Wi-Fi as the speaker)

```bash
cd flutter
flutter pub get
flutter analyze && flutter test
../scripts/run-flutter.sh android
```

Make the release APK with `./scripts/build-flutter-release.sh android`; it lands in `releases/`. This book's app does not go to a store. You install it with `adb install` or by copying the file. The iOS settings remain in the code, but the book does not cover iOS.

## Claude Code Harness

When you start Claude Code in this repository, the skills and agents in `.claude/` are registered automatically. To install them as a plugin:

```bash
claude plugin marketplace add bumicklee/home-ai-speaker-Private-en
claude plugin install home-ai-speaker@home-ai-speaker-book
```

The details are in Appendix K.9 of the book.

## Versions

The verified versions of tools, models and packages are in [versions.md](versions.md). For what to do when a model name or library version changes, see Appendix D of the book.

## License

- Code in this repository: [MIT](LICENSE)
- Notices for the projects it is based on and for the sound files: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
