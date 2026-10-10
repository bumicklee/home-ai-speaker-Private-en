# Development Environment Setup

The tools you need to build this project (`firmware/`, `flutter/`) and how to set them up.

- Written: 2026-10-02
- Reference computer: macOS (Apple Silicon), default shell zsh

## 1. Summary

| Tool | Version | Location |
|:--|:--|:--|
| ESP-IDF | **v5.5** | `~/esp/esp-idf-v5.5` |
| ESP-IDF Python virtual environment | Python 3.14 | `~/.espressif/python_env/idf5.5_py3.14_env` |
| Xtensa toolchain (ESP32-S3) | esp-14.2.0_20241119 | `~/.espressif/tools/xtensa-esp-elf/` |
| Python (system) | 3.14.6 (Homebrew) | `/opt/homebrew/bin/python3` |
| CMake / Ninja | 4.1.2 / 1.13.1 | |
| Flutter / Dart | 3.38.5 (stable) / 3.10.4 | `~/flutter` |

## 2. Turning On the ESP-IDF Environment

Run this once every time you open a new terminal.

```bash
source ~/esp/esp-idf-v5.5/export.sh
```

When it works, it ends like this.

```
Checking "python3" ...
Python 3.14.6
...
Activating ESP-IDF 5.5
Setting IDF_PATH to '/Users/<user>/esp/esp-idf-v5.5'.
* Checking python version ... 3.14.6
* Checking python dependencies ... OK
...
Done! You can now compile ESP-IDF projects.
```

Check:

```bash
idf.py --version          # ESP-IDF v5.5
echo $IDF_PATH            # /Users/<user>/esp/esp-idf-v5.5
```

The "Found tools that are not used by active ESP-IDF version" notice means tools from an older version are still around. You can ignore it. To free up disk space, use the `idf_tools.py uninstall` command the notice shows.

### Convenience Alias (Optional)

The existing `get_idf` alias in `~/.zshrc` turns on a **different version** (`~/esp/esp-idf` + the `idf5.4` virtual environment). Don't use it for this project. If you want an alias of your own:

```bash
alias get_idf55='source ~/esp/esp-idf-v5.5/export.sh'
```

## 3. Things to Watch Out For

### 3.1 python3 Must Be 3.14

The ESP-IDF 5.5 virtual environment was created with Python 3.14, so the `python3` that `export.sh` finds must be 3.14.

- In the user's zsh, `python3` → Homebrew 3.14.6, so there is no problem.
- If another shell or an automation tool picks up `python3` as 3.12, you get this error.
  ```
  ERROR: ESP-IDF Python virtual environment ".../idf5.5_py3.12_env/bin/python" not found.
  ```
  In that case, run it in a zsh login shell.
  ```bash
  zsh -lc 'source ~/esp/esp-idf-v5.5/export.sh && cd firmware && idf.py build'
  ```

`~/.zshrc` has pyenv initialization lines. As the comment there says, pyenv gets in the way when you install or upgrade ESP-IDF, so comment those lines out for the time being.

### 3.2 ESP-IDF Version

| Project | Version it was built with |
|:--|:--|
| This project | v5.5 (this computer) |
| `waveshare-ai-speaker-assistant` (reference firmware) | v5.5.2 |
| Official Waveshare examples | v5.5.0 |

The reference firmware was built with v5.5.2. Start with v5.5 for now, and if you need a driver bug fix, move up to the latest v5.5.x. When you do, update this document.

```bash
cd ~/esp/esp-idf-v5.5 && git fetch --tags && git checkout v5.5.2 \
  && git submodule update --init --recursive && ./install.sh esp32s3
```

`~/esp/` also holds `esp-idf` (a different version) and `esp-idf-v5.3.2-…`. To avoid mixing them up, always use `esp-idf-v5.5/export.sh`.

### 3.3 CMake 4.x

The CMake on the PATH is 4.1.2. CMake 4 doesn't support very old policy syntax (below 3.5), so old third-party components (especially the Spotify Connect library) may fail to build. If you hit that error, raise `cmake_minimum_required` in that component or set the environment variable `CMAKE_POLICY_VERSION_MINIMUM=3.5`.

## 4. Building and Uploading the Firmware

```bash
source ~/esp/esp-idf-v5.5/export.sh
cd firmware
idf.py set-target esp32s3        # once, the first time (creates sdkconfig)
idf.py build
idf.py -p <port> flash monitor   # upload + view the log; exit with Ctrl+]
```

### Finding the Board's Port

```bash
ls /dev/cu.usbmodem*
```

When you connect the board with a USB-C data cable, a new `/dev/cu.usbmodemXXXX` appears. Compare the list before and after connecting, and use the one that is new. (As of 2026-10-02 this computer already has a `/dev/cu.usbmodemXXXXXXXXXX`; it still needs checking whether that is the board or another device.)

If you need download mode: hold down BOOT, press and release RESET, then release BOOT.

### Restoring the Board to Its Factory State

```bash
esptool.py --chip esp32s3 -p <port> write_flash 0x0 \
  ../ESP32-S3-AUDIO-Board-Demo/Firmware/ESP32-S3-AUDIO-Board.bin
```

## 5. Flutter

```bash
flutter --version     # Flutter 3.38.5 / Dart 3.10.4
cd flutter
flutter pub get
flutter run           # connected phone or simulator
```

- This meets the same requirements as led-app (Dart ≥3.10.4, Flutter ≥3.38.4).
- iOS builds need Xcode and CocoaPods; Android builds need the Android SDK. Check with `flutter doctor`.
- Even if a `flutter upgrade` notice appears, don't upgrade until the team decides, so the app version stays pinned.

## 6. Managing Secrets

- **OTA signing key**: `certificates/ota_signing_key.pem` (top of the working folder). The firmware is signed with this key at build time, so **the build fails without the key.** **Never put the key in Git** (`certificates/*.pem` in `.gitignore`). A freshly cloned repository having no key is normal; create it yourself as in Chapter 1, Section 1.4.9 of the book. If you lose it, you can no longer update speakers already installed over the air (OTA), so back it up somewhere safe, such as a password manager.

- Secrets such as the OpenAI API key and the Telegram bot token are **entered into the speaker over BLE**. Don't put them in the firmware source, `sdkconfig`, or the Git repository.
- Don't keep API keys in plain text in a shell config file (`~/.zshrc`). If you need to, put them in a separate file with permission 600 and `source` it, or use the macOS Keychain.
