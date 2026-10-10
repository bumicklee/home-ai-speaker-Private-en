---
name: esp32-firmware
description: Working rules for the Waveshare ESP32-S3-AUDIO-Board speaker firmware (ESP-IDF v5.5) and the book's step-by-step prompts. Use when editing C code under firmware/, sdkconfig.defaults, or partitions.csv, or when dealing with builds, flashing, boot logs, memory shortages, the wake word, BLE, the LAN API, radio, Telegram, or voice conversation.
when_to_use: firmware, idf.py, ESP-IDF, boot log, reboot, out of memory, wake word, Computer/Alexa, BLE window, LAN API, radio, Telegram, Saver mode, Gemini Live
paths: firmware/**
argument-hint: "[chapter number, e.g. 6]"
---

# Firmware Working Rules (for the home AI speaker book built with Claude Code)

When a chapter number comes as the argument (`/esp32-firmware 6`), find that chapter's prompts in [prompts.md](prompts.md) and proceed in order. Do one step at a time, and at the end of each step run the "Verification sequence" below and show the user the results.

## Rules to Follow

- **Take pins and I2C addresses only from `components/app_config/include/board_config.h`.** Don't write them as numbers in any other file.
- **Lower modules don't know about upper modules.** Anything a lower module needs to tell an upper one goes out as an `app_events` event. A button only sends "pressed", and `main.c` decides what it means.
- **Secrets (AI keys, bot tokens) are received only over BLE.** Don't accept them over the LAN API, don't print them in logs, and zero out buffers when you're done with them.
- **Configuration options go in `sdkconfig.defaults`.** `sdkconfig` is a file the build generates, so it doesn't go into Git. If it already exists, a change takes effect only if you also change it in `idf.py menuconfig`.
- **Internal RAM is the most precious resource.** Put large buffers and task stacks in PSRAM. When you create a new task or buffer, report how much the `heap after boot done internal …` value in the boot log dropped.
- **A failed init of an optional feature doesn't stop boot.** Use `ESP_ERROR_CHECK` only for initialization that is truly required.
- **The OTA signing key (`certificates/*.pem`) doesn't go into Git.** This holds even if the repository is private.
- Model names live only in `app_config.h` constants. When they change, change only the constants.
- Commits are made only when the user asks.

## Verification Sequence (at the end of every step)

```bash
source ~/esp/esp-idf-v5.5/export.sh
cd firmware && idf.py build                    # aim for 0 warnings
idf.py -p <port> flash monitor                 # Ctrl+] to quit
```

1. Check that the boot log has no `E (` lines and no `Rebooting...`.
2. Compare the `heap after boot done internal … (largest …)` value with the previous one.
3. Run `selftest` on the USB console and check that every item is PASS.
4. Check that chapter's "pass criteria" one by one.

If you get stuck, take the whole log as it is and narrow down the cause with the sequence in [debugging.md](debugging.md). Don't fix by guessing; have the values used for the decision printed in the log first.

## See Also

- Prompts by chapter: [prompts.md](prompts.md)
- Reading logs and the failure analysis sequence: [debugging.md](debugging.md)
- App-side rules are in the `flutter-app` skill; plan, design, and failure report formats are in the `speaker-method` skill
