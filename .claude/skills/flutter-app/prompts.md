# App Step-by-Step Prompts

Step-by-step prompts for building AI-PA, the speaker setup app (Flutter, Android). The app prompts from Appendix K of the book, and the prompts used for both firmware and app ("shared" in the table), are copied here word for word in chapter order. Give a chapter number, as in `/flutter-app 12`, and that chapter's prompts run in order, one at a time.

Numbers kept in other files: the firmware prompts such as `P08` and `P09` (BLE and LAN firmware) and `PD-` (debugging) are in the `esp32-firmware` skill's prompts.md and debugging.md; `PR-` (review) and `T-` (general templates) are in the `speaker-method` skill's templates.md.

This book's app is Android only and is not released to a store. The release APK stays signed with the debug key and is installed with `adb install`.

## Chapter → Prompt Numbers

| Chapter | Prompts |
|:--|:--|
| Chapter 1: Development Environment | P01-01 (shared), P01-02 (shared) |
| Chapter 10: The Flutter App Skeleton | P10-01, P10-02 |
| Chapter 11: Design System | P11-01, P11-02, P11-03 |
| Chapter 12: First-Time Setup and Home | P12-01, P12-02, P12-03, P12-04 |
| Chapter 13: Five Screens in Parallel | P13-01, P13-02, P13-03 |
| Chapter 16: Notes, Schedule, Reminders, and Korean Teacher Mode | P16-02, P16-03 (shared) |
| Chapter 17: Saver Mode and Choosing an AI | P17-01 (shared), P17-03 |
| Chapter 20: Handing It to the Family | P20-01 |

## How to Use

- Paste one prompt. When Claude says it's done, run the commands under **How to verify** yourself. Look at the logs printed in your terminal, not Claude's summary of them.
- For a large change (a new component, several files), get a plan first in plan mode and read it.
- If it passes, look at `git status` and `git diff` and say "commit it". Commits happen only when you ask.
- If it fails, paste the log first, before sending the **If you get stuck** request. Don't let it fix by guessing.
- Every prompt contains three things: a **Reference document** (the design document `docs/design.md` is pointed to by topic name, not section number), **Do not change**, and **How to verify**.
- The tag at the end of an entry's title, `· Chapter 6, Section 6.3`, is when to use it. If there are further conditions, they're on the **When** line.

| What to change | Value in this file | How to change it |
|:--|:--|:--|
| Repository | `~/home-ai-speaker` | Paths inside prompts are relative to the repository |
| Port | `/dev/cu.usbmodem*` | Your port, found in Chapter 1. On Windows, the `COM` number |
| AI key | OpenAI or Gemini | Two exceptions: the USB console `key` command in Chapter 6 accepts only an OpenAI key, and Korean teacher mode is OpenAI Live only |
| Model names | `gpt-live-1`, `gemini-3.8-live`, etc. | May change by the time of publication. See Appendix D |
| Phone | Android | If the app code has iOS settings, leave them alone |

## Chapter 1: Development Environment

The shared Chapter 1 prompts (P01-01, P01-02) are also in the firmware skill, with the same text.

### P01-01 Interpreting an install error · Chapter 1, Section 1.4
**When** Whenever an error comes up while installing ESP-IDF or Flutter.
```text
Reference document: ~/home-ai-speaker-final/docs/dev-environment.md (the development environment document) in the finished-source repository (Chapter 0, "Downloading the finished source").
I ran source ~/esp/esp-idf-v5.5/export.sh and got the error below. (paste the full error)
Do not change: the ESP-IDF version (v5.5) and install location (~/esp/esp-idf-v5.5). Do not suggest installing a different version.
How to verify: after the fix, idf.py --version must print ESP-IDF v5.5.
```
**How to verify** `idf.py --version`, `flutter doctor`. **If you get stuck** If a different ESP-IDF gets activated (Section 1.5, item 3): "Tell me the command to find which export.sh was sourced in the current shell, and find the line in my shell config file that sources another version. Don't fix it, just show me."

### P01-02 Repository and .gitignore · Chapter 1, Section 1.3
```text
Reference document: Section 1.4.9 of this book (signing key).
Create an empty Git repository at ~/home-ai-speaker and write a .gitignore. It must exclude certificates/*.pem, firmware/build/, firmware/sdkconfig, firmware/managed_components/, and flutter/build/.
Do not change: keep the certificates/ folder itself (.gitkeep). Never commit key files under any circumstances.
How to verify: .pem files must not appear in git status. Commits happen only when I ask.
```
**How to verify** `git status`, `git check-ignore -v certificates/ota_signing_key.pem`. **If you get stuck** If `firmware/dependencies.lock` got excluded: "dependencies.lock should be committed. Fix .gitignore so this file is not excluded."

## Chapter 10: The Flutter App Skeleton

### P10-01 Flutter app skeleton · Chapter 10, Section 10.3
```text
Create a Flutter app skeleton in the flutter/ folder.
- Reference document: the 'Tech Stack' (package versions), 'Folder Structure', and 'Platform Settings' sections of docs/design.md. Use the major versions in the table as they are; don't upgrade them.
- Do not change: BLE constants live in one file only, lib/core/constants/ble_protocol.dart, and the values must match the firmware's app_config.h and the 'BLE GATT Specification' section of the design document 1:1. Don't write UUIDs in any other file.
- Don't build screens this time. Leave only a splash and a placeholder home that says "No speaker yet".
- How to verify: flutter analyze with 0 issues, flutter build apk --debug succeeds.
```
**How to verify** `cd flutter && flutter analyze && flutter build apk --debug`. **If you get stuck** If it tries to upgrade package versions, refuse: "Compare the versions in pubspec.yaml line by line with the 'Tech Stack' table in the design document and revert the lines that differ."

### P10-02 BLE and LAN layers and the fake speaker test · Chapter 10, Section 10.3
```text
Create core/ble, core/network, and core/services following the 'Folder Structure' of the design document.
- Reference document: the 'BLE GATT Specification' (including the chunk format) and 'LAN API' sections of the design document. Read the chunk rules (sequence number, flags, MTU − 5) in the firmware's ble_cmd.c and match them exactly.
- Do not change: repositories don't throw exceptions; they return Either<Failure, T>. Every Failure fills errorKey. Write the SSID and password as UTF-8.
- How to verify: build a FakeDevice in the tests that receives chunks, reassembles them, and returns the response in chunks like the firmware does, and pass unit tests for chunk splitting and reassembly, Wi-Fi scan parsing, the command channel, guard, and the LAN client. Also test that every error key exists in both app_ko.arb and app_en.arb.
```
**How to verify** `flutter test` all pass. The test names mention chunks, scan, command channel, and guard. **If you get stuck** Tests can pass and still disagree with the firmware: "Compare the FakeDevice chunk rules with firmware/components/ble_prov/ble_cmd.c line by line and show the differences in a table."

## Chapter 11: Design System

### P11-01 Drawing the phone screens (Artifacts) · Chapter 11, Section 11.3
**When** Before any code. Use it in the claude.ai chat window.
```text
Draw the screens of a phone app that sets up our family's AI speaker as an HTML artifact.
- Canvas: one phone = 390×844px. If there are several screens, place them side by side horizontally with a name above each one.
- Reference document: the screen list below and what each screen does. (paste the "screen | what it does" table from the feature table here)
- Colors: the primary color is a darkened version of the speaker's standby-LED teal. Pick a value with at least 4.5:1 contrast against white text and tell me the HEX. For warnings and delete, use a color that goes with teal instead of red. Background very light gray, cards white.
- Font: one open-source font whose Korean and Latin glyphs belong to one family. Body text 15–16px.
- Every tap target at least 44px. Every list row at least 56px.
- Do not change: don't add features that aren't in the screen list. Use example values like "JARVIS_EB1650" and "Volume 12" instead of real data.
- How to verify: when you're done, put a table of color HEX values, contrast ratios, font name, and spacing rules under the artifact. I'll carry that table into code.
```
**How to verify** Re-measure the contrast ratios in the table with a contrast checker. Revise until you like it, then save the HTML into `docs/`. **If you get stuck** When adding a new feature later (such as choosing the AI in Chapter 17), ask for a new row on the same canvas. Approve the picture before the code.

### P11-02 From design to code · Chapter 11, Section 11.3
```text
Carry the colors, fonts, and sizes from the design canvas "Jarvis speaker app design" (docs/jarvis-app-design.html) into lib/core/theme/app_theme.dart and lib/core/widgets/app_widgets.dart.
- Reference: primary #0B6E6D (5.9:1 contrast against white text), background #F2F4F3, cards white, warning #9A4A07, font IBM Plex Sans KR (google_fonts), tap targets at least 44px.
- Do not change: color HEX values live only as AppColors constants; never write them directly in screen code. Map them into the Material 3 ColorScheme by role, and build the dark theme with the same structure. Limit the shared widgets to 10: card, section title, list group, list row, switch row, slider row, step bar, notice box, status dot, and failure view, and make feature screens assemble from these only.
- How to verify: flutter analyze 0, rebuild the home screen (features/home) with these widgets so it displays in both the light and dark themes. Existing tests must still pass.
```
**How to verify** `grep -rn "0xFF0B6E6D" flutter/lib/` must return only one line, in `app_theme.dart`. That means the primary color didn't leak into screen code. Even the finished source still has a few `Color(0x…)` values in screen files, such as the text color on dark cards (Chapter 11, Section 11.2); to remove those too, move them into `AppColors` as the Section 11.7 exercise. **If you get stuck** If the primary HEX is left in screen code: "Find every place under features that uses a color constant directly and change it to AppColors or a theme role."

### P11-03 Icon and splash · Chapter 11, Section 11.3
```text
Make the icon and splash exactly as in the "App icon · Splash" row of the design canvas.
- Artwork: a white ring (the speaker's LED ring) + a light green dot at the top (the standby LED) + three bars in the middle (speech), on a #0B6E6D background. The app name is AI-PA, and under the splash "AI-PA / Our family's voice assistant".
- Do not change: don't draw the images by hand; have tool/gen_brand_assets.py (Pillow) draw them in a 1024 coordinate system, so that changing the artwork means changing only coordinates. Don't put font files in the repository; download them on first run. Don't touch the package name com.aispeaker.aispeaker.
- Apply with flutter_launcher_icons and flutter_native_splash. Include the Android adaptive and monochrome (Android 13) icons and the Android 12 splash format.
- How to verify: the script creates 6 PNGs in assets/brand/ and prints their sizes. dart run flutter_launcher_icons and dart run flutter_native_splash:create succeed. The app keeps the splash up until it has finished reading the speaker list.
```
**How to verify** The icon and name on the phone's home screen. **If you get stuck** If the adaptive icon gets cropped: "Calculate with coordinates whether the artwork in icon_foreground.png fits inside the safe zone (the center 66%) and show me."

## Chapter 12: First-Time Setup and Home

### P12-01 First-time setup state machine · Chapter 12, Section 12.3
```text
Create the first-time setup screens in features/provisioning.
- Reference document: the "first-time setup" flowchart and its branches in the 'Main Screen Flows' section of the design document (keep or change for a speaker that already has Wi-Fi, phones full, mDNS rediscovery after reboot up to 45 seconds). For BLE use only the core/ble from Chapter 10; don't handle it directly in screens. The first-time setup screen on the design canvas and the 4-step StepProgress.
- Do not change: the key is entered before the BLE connection. Steps are managed by a single ProvStep enum, and ProvisioningCubit is the state machine. Save the token even if LAN discovery fails. Pages don't hold BLE objects.
- How to verify: with bloc_test and a fake BleSpeakerSession, pass the paths "key → find → connect → keep Wi-Fi → register → done", "wrong password → back to the Wi-Fi list", and "PHONES_FULL → pick a phone to remove".
```
**How to verify** `flutter test test/features/provisioning/`, then the first test on the real board (Chapter 12, Section 12.4). **If you get stuck** If it gets stuck at the first step on real hardware, look at the firmware log too: "Merge the speaker log (the BLE_PROV and BLE_CMD lines) and the app log in time order and show me at which step it stopped."

### P12-02 Remembering keys · Chapter 12, Section 12.3
```text
Create a KeyVault in core/storage that remembers the AI key (OpenAI or Gemini) and the Telegram bot token in the phone's secure storage. It can be turned off with the "Remember keys on this phone" switch in first-time setup (on by default) and cleared under System > Keys. InstallState empties it when the app is uninstalled and reinstalled.
Do not change: keys still go to the speaker only over BLE (the design decision that secrets are not accepted over LAN). Don't leave keys in logs or test output.
Reflect this decision in the 'Main Screen Flows' section of the design document.
How to verify: pass unit tests for save, read, clear, and clear-on-reinstall, and flutter analyze 0.
```
**How to verify** `flutter test`. Uninstall and reinstall the app and check that the key field is empty in first-time setup. **If you get stuck** If code appeared that puts the key into a LAN request, revert it right away: "Find every place under core/network that puts a key or token value into a body or header (excluding the phone token Bearer)."

### P12-03 Home screen · Chapter 12, Section 12.3
```text
Create the home screen with features/home and features/devices. Read the selected speaker's LAN /status to draw the status card, and update it live with the voice_state, media_state, volume, and tg_message events from DeviceEventService.
The volume slider sends on release, but update the screen first and re-fetch on failure. On 401, show "This phone's registration was revoked → register again"; if unreachable, show a reminder to check that you're on the same Wi-Fi and a button for BLE re-setup.
Do not change: use only the Chapter 11 shared widgets. No color HEX values.
How to verify: HomeCubit tests (normal, 401, unreachable, volume failure rollback) and flutter analyze 0.
```
**How to verify** Change the volume with the buttons and see whether the app slider follows. **If you get stuck** If live updates don't work, first check with P09-03's websocat whether the speaker is sending events.

### P12-04 When the app can't find the speaker · Chapter 12, Section 12.5
**When** When the speaker is advertising but doesn't show up in the app's search.
```text
The speaker log has advertising as JARVIS_… but the speaker doesn't show up even when I press "Search again" in the app. I'm pasting the app log. (if you see status=6 or similar, leave it as is)
Reference: the scan start and stop code in flutter/lib/core/ble/ble_link.dart, the flutter_blue_plus scan API, and Android's limit on how often scanning can be started.
Check: ① whether a scan from a screen that was already closed stops the new screen's scan, ② whether starting scans several times in a short period hits the limit.
Do not change: the advertising name rule (JARVIS_), the service UUID filter.
How to verify: show the cause as code lines, then fix it, and show with a test that only the side that started a scan can stop it.
```
**How to verify** How I fixed it during the build: only the subscription that started the scan stops it, one search lasts 30 seconds, and "Search again" is disabled while searching. **If you get stuck** If it still doesn't show up, see P08-04 on the speaker side.

## Chapter 13: Five Screens in Parallel

### P13-01 Preparing for parallel work · Chapter 13, Section 13.3
**When** In the main session, before splitting the five screens.
```text
I'm going to hand the five screens, radio, Telegram, assistant, audio, and system, to agents in separate git worktrees. Before starting, prepare the shared parts first.
Reference document: the 'Folder Structure' section of the design document, the forbidden file list in Chapter 13 of this book.
To do: ① make per-feature string files lib/l10n/parts/<feature>_ko.arb and _en.arb, which tool/merge_arb.py merges into app_ko.arb and app_en.arb; ② set the feature entry file rule (<feature>_feature.dart exports register<Feature>Feature(GetIt sl) and the screen classes); ③ write the prompts to give the five worktrees using the P13-02 template.
Do not change: the existing screens and tests. Don't build feature screens at this stage.
How to verify: python3 tool/merge_arb.py && flutter gen-l10n succeeds, flutter test still passes.
```
**How to verify** `git worktree list` shows five folders. **If you get stuck** If the generated files (`app_localizations*.dart`) look likely to collide, add them to the forbidden list and regenerate at merge time.

### P13-02 One screen (inside a worktree) · Chapter 13, Section 13.3
**When** One per worktree session. Below is the radio example.
```text
In this worktree, build only the radio screen. It does: now playing, presets by genre, playback controls, preset editing (order, name, delete, add by URL), and Radio-Browser station search.
Scope: build under lib/features/radio/ with the structure from the 'Folder Structure' section of the design document (data/domain/presentation), and have the entry file lib/features/radio/radio_feature.dart export registerRadioFeature(GetIt sl) and the screen class RadioPage. Write strings only in lib/l10n/parts/radio_ko.arb (the reference) and radio_en.arb, with key names starting with radio. Tests go in test/features/radio/.
Forbidden files: don't modify lib/injection_container.dart, lib/app/, lib/core/, lib/l10n/app_*.arb, lib/l10n/app_localizations*.dart, or other features' features/ and parts/. If a shared part you need isn't in core, don't create it; list it under "needed at merge" in your final report.
Spec source: read the 'LAN API' section of the design document first, then confirm the actual JSON field names, status codes, and error codes by reading the firmware code directly (firmware/components/local_api/, firmware/components/media_radio/). Where the design document and the firmware differ, follow the firmware and put the differences in a table in the report.
Design: assemble only from the Chapter 11 shared widgets (lib/core/widgets/app_widgets.dart). No color HEX values. Follow the radio screen on the design canvas.
Done when: flutter analyze 0, python3 tool/merge_arb.py && flutter gen-l10n succeeds, flutter test test/features/radio/ all PASS. When finished, leave one commit, "app: radio screen", and write in the report (1) the files created, (2) the facts confirmed in the firmware (differences from the design document), (3) what's needed at merge (router paths, DI calls, shared error keys).
```
**How to verify** Table (2) in the report. During the build, this is the step where I found that `GET /radio/presets` comes wrapped as `{"presets":[…]}`. **If you get stuck** If a forbidden file was modified, don't merge that commit; have it reverted: "Find the changes to files on the forbidden list with git diff, revert them, and move the reason you needed them into the report."

### P13-03 Merging · Chapter 13, Section 13.3
**When** In the main session, after the five screens are done.
```text
Merge the commits from the five worktrees one at a time. Order: audio → system → assistant → Telegram → radio.
Reference: each worktree report's "needed at merge" and "differences from the design document" tables.
To do, for each merge: ① wire the path into the lib/app/ router, ② add the register<Feature>Feature call to injection_container.dart, ③ add shared error keys (core) if needed, ④ regenerate the generated files with python3 tool/merge_arb.py && flutter gen-l10n.
Do not change: don't modify the code in each feature folder unless it's a merge conflict. Where the design document differs, fix the design document to match the firmware (don't fix the firmware).
How to verify: after every merge, flutter analyze 0 and flutter test all pass. When all five are done, tell me the test count.
```
**How to verify** `flutter test` after every merge. Don't move on to the next merge with a failure. **If you get stuck** If the generated string files conflict, don't resolve them by hand; regenerate with `merge_arb.py` and `gen-l10n`.

## Chapter 16: Notes, Schedule, Reminders, and Korean Teacher Mode

### P16-02 App notes and schedule feature · Chapter 16, Section 16.3
```text
Create flutter/lib/features/notes/ based on the 'App (AI-PA)' section and the 'LAN API (for the app)' section (notes and schedule API spec, Appendix C) of docs/design-notes-schedule.md. Use the same Clean Architecture structure as the Korean teacher feature (features/english/): entities, models, datasources, repository, cubit, pages, registerNotesFeature.
Do not change: store the local copy as {rev, items} in notes_<deviceId>.json in the app documents folder, and add path_provider. Sync when the app opens, when the screen is entered, and on the WS notes event, with GET /notes?since=rev; apply the higher rev per id and remove gone items from the copy. Always show a confirmation dialog before deleting in the app ("It will be deleted from the speaker too and can't be restored."). Put the response body into DeviceApiException so the "note" in a 409 response can be read, keeping existing behavior as is. Add strings for the new error codes FULL and CONFLICT.
How to verify: write model, merge, conflict, reminder chip, and cubit tests; flutter analyze with no issues, flutter test all pass. Localization in notes_ko.arb/notes_en.arb.
```
**How to verify** A schedule item added by voice on the speaker appears in the app, and one deleted in the app disappears from the speaker. **If you get stuck** If conflict (409) handling gets tangled: "Build a test where the same item is edited on the speaker and in the app at the same time, and show me the current behavior."

### P16-03 Korean teacher mode · Chapter 16, Section 16.3
**When** You need an OpenAI key (this feature is OpenAI Live only).
```text
Create firmware/components/assistant/lesson.c and flutter/lib/features/english/ based on the "Korean teacher" screen in the app design: Korean lessons for an English-speaking learner. 5 courses (pron/basic/daily/biz/adv), 3 or 5 minutes, explain "en" (when stuck, explain briefly in English; the default) or "ko" (Korean only); during a lesson, about every 45 seconds send the transcript to the Responses API, extract corrected expressions (Korean in Revised Romanization only, never Hangul, + English meaning), pronunciation, and topics as JSON, send them as a WS lesson event, and when it ends save the full summary to /storage/lesson.json.
Do not change: a lesson must be the same live_voice session as a normal conversation, and don't change live_voice's external functions. The transcript buffer must not exceed 24KB of PSRAM. The assistant tool start_korean_lesson must open the lesson after the current conversation ends.
How to verify: POST /api/v1/lesson/start {"course":"basic","minutes":3} → after 3 minutes, GET /api/v1/lesson must have state:"done" and a corrections array. The tests in flutter/test/features/english/ pass.
```
**How to verify** The two curl commands above. A lesson conversation starts with `LIVE: limits …`. **If you get stuck** If cost worries you, check the lesson length cap first. During the build I reduced 10, 20, and 30 minutes to 3 and 5.

## Chapter 17: Saver Mode and Choosing an AI

### P17-01 Saver mode design and feasibility review · Chapter 17, Section 17.3
**When** Before any code.
```text
I want the app to let you choose between 'Live (gpt-live-1)' and 'Saver mode' as a setting, and likewise to let you use a Gemini API key. 1 hour a day comes to about $90 a month, which is a burden. Write docs/design-voice-saver-mode.md.
Using the official OpenAI and Gemini price lists, calculate the monthly cost for all four combinations at 1 hour a day (15 minutes of the person speaking, 15 minutes of the speaker speaking, 60 round trips), and write down, item by item, whether Saver mode is technically feasible on the Waveshare ESP32-S3-AUDIO-Board (VAD, boosting audio, Responses API tools, TTS playback, about 18KB of internal RAM), with reasons.
Do not change: the current 28 tools and assistant_execute(), the Telegram protection (tool_guard), and schedule reminders must be used as they are. I make the decisions. Leave the list of questions in a separate 'Open Questions' section.
How to verify: cite the source page for each unit price, and label estimated figures "estimate".
```
**How to verify** Open the price source pages yourself. Answer the 'Open Questions' section yourself. **If you get stuck** If the design document makes decisions for you: "Move the sentences written as decisions into 'Open Questions' and leave only the options with their pros and cons."

### P17-03 Saver mode app (worker 2) · Chapter 17, Section 17.3
```text
Modify the app based on the 'App Changes' part of the same design document's 'Detailed Design' section and the "Choose AI · Live / Saver mode" row of the design canvas. Change step 1 of first-time setup to "① choose the AI → that AI's key (required) or 'This speaker already has this AI's key (adding another phone)' → ② Saver mode / Live (show the monthly cost)". New screen /assistant/ai (AI card + mode card). Gemini key under System > Keys. On the home status card, "OpenAI · Saver". On the Korean teacher screen, "Korean lessons use the real-time API (OpenAI) · about ₩70 a minute".
Do not change: gather the provider and mode lists and their strings in lib/core/ai/ so several screens share them. If ai is missing, as with old firmware, treat it as openai/live, available ["openai.live"]. No key → locked; key present but not in available → "Coming soon". Remember the key in vault_gemini_key.
How to verify: flutter analyze with no issues; write tests for the settings model, ai parsing, BLE gemini_key, the first-time setup lock, the AI screen lock rules, and the Korean lesson key check, and flutter test all pass.
```
**How to verify** `flutter test`. In the app under Assistant > AI · Conversation mode, the locks open and close according to the speaker's `available`. **If you get stuck** If the two workers' JSON shapes differ: "Show me side by side in a table the ai field that the firmware's device_info.c and device_settings.c actually send and the field the app's lib/core/ai/ai_choice.dart reads."

## Chapter 20: Handing It to the Family

### P20-01 Release build script · Chapter 20, Section 20.3
**When** When giving the app to family phones. The user prompt is exactly what I used during the build, as printed in Chapter 20, Section 20.3. That's why it contains the `ios` and `all` arguments and AAB. Don't edit it; send it as is.
```text
Create scripts/build-flutter-release.sh. Arguments android|ios|all, options --no-test and --no-clean.
Reference document: scripts/run-flutter.sh (the same color and step display style), the app name decided in Chapter 11 (AI-PA).
Do not change: version in flutter/pubspec.yaml, the signing config in android/app/build.gradle.kts. Always run python3 tool/merge_arb.py and flutter gen-l10n before the build (because of the Chapter 13 string file split).
How to verify: the outputs are copied to releases/ai-pa-<version>-<date>.{apk,aab,ipa}, and at the end it prints the install command (adb install -r …). If it was signed with the debug key, show a warning. If even one test fails, don't build (set -e).
```
**How to verify** When running it, use only the `android` argument. `./scripts/build-flutter-release.sh android` → `adb install -r releases/ai-pa-….apk`. The script also makes an AAB and prints an `iOS:` notice line, but neither is used. Since nothing goes to the store, no release keystore or upload key is needed, and the debug-key signing warning is normal. The check items in Chapter 20, Section 20.4 ① are based on this script. **If you get stuck** If it stops at `[2/5]`, analysis or a test failed. Don't skip with `--no-test`; paste the failing test output and ask for the cause first.
