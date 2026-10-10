---
name: flutter-app
description: Working rules for AI-PA, the speaker setup app (Flutter, Android), and the book's step-by-step prompts. Use when dealing with Dart code, screens, the BLE and LAN communication layers, string files (ARB), tests, or the release APK under flutter/.
when_to_use: Flutter, Dart, app screen, Cubit, BLoC, first-time setup, BLE scan, mDNS discovery, LAN API call, WebSocket event, flutter test, APK
paths: flutter/**
argument-hint: "[chapter number, e.g. 12]"
---

# App Working Rules (for the home AI speaker book built with Claude Code)

When a chapter number comes as the argument (`/flutter-app 12`), find that chapter's prompts in [prompts.md](prompts.md) and proceed in order. Do one step at a time, and at the end of each step run the "Verification sequence" below.

## Rules to Follow

- **This book's app is Android only.** iOS builds and code signing are not covered. Leave any iOS settings in the code as they are; don't delete them.
- **It isn't released to a store.** The release APK stays signed with the debug key and is installed with `adb install` or by copying the file.
- **Feature folders are split into three layers: `data`, `domain`, `presentation`.** Screens don't know about BLE or LAN directly. They call only through repositories.
- **State is handled with Cubit**, and state objects are created anew with `copyWith`.
- **Repositories don't throw exceptions.** Wrap calls in `guard()` and return `Either<Failure, T>`. Error messages go from `errorKey` → ARB.
- **BLE constants live only in one file, `lib/core/constants/ble_protocol.dart`.** Their values must match the firmware's `app_config.h` one to one.
- **Strings go in per-feature files** (`lib/l10n/parts/<feature>_<language>.arb`) and are merged with `python3 tool/merge_arb.py && flutter gen-l10n`.
- **Secrets are sent to the speaker only over BLE.** On the phone, they're remembered only in secure storage (KeyVault).
- Commits are made only when the user asks.

## Verification Sequence (at the end of every step)

```bash
cd flutter
flutter analyze            # 0 issues
flutter test               # all pass
../scripts/run-flutter.sh android    # run on the phone (same Wi-Fi as the speaker)
# If the script doesn't exist yet (Chapter 12, Section 12.4), instead: flutter run
```

Check that chapter's "pass criteria" one by one. For items that can only be checked on real hardware (permission dialogs, BLE connection, mDNS discovery), ask the user to confirm.

## See Also

- Prompts by chapter: [prompts.md](prompts.md)
- Firmware-side specifications and rules are in the `esp32-firmware` skill; plan, design, and failure report formats are in the `speaker-method` skill
