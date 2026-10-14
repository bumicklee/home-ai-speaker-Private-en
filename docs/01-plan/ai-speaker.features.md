# AI Speaker Detailed Feature Specification

- Written: 2026-10-02
- Parent documents: plan document (not included in this repository) · [design document](../design.md)
- Feature ID rule: `AREA-number` (example: `VOI-03`). Use this ID in code comments, commits, and test names.

## How to Read This

| Column | Meaning |
|:--|:--|
| Priority | **P0** the product does not work without it · **P1** included in the first release · **P2** added later |
| Phase | The implementation phase from Section 7 of the plan document (1 foundation · 2 app connection · 3 radio · 4 Telegram · 5 Spotify · 6 wrap-up) |
| FW / APP | The firmware component / app feature folder responsible (design document Sections 2.1 and 3.2) |
| Completion criterion | When this condition is confirmed, the feature counts as implemented |

## Feature Areas

133 in all. "Buttons" means the board's Key1/Key2/Key3 (TCA9555 EXIO 9/10/11). Key2 is the system button (design document Section 2.15).

| Code | Area | Feature count |
|:--|:--|:--|
| SYS | System and hardware | 15 |
| PRV | Provisioning and connectivity | 15 |
| VOI | Voice conversation | 21 |
| AST | Assistant settings and memory | 11 |
| INF | Information lookup | 7 |
| AUD | Audio settings | 7 |
| RAD | Internet radio | 12 |
| SPT | Spotify | 13 |
| TLG | Telegram | 14 |
| APP | App common | 12 |
| OTA | Firmware update | 6 |

---

## 1. System and Hardware (SYS)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| SYS-01 | Boot initialization | Initialize in the order settings → board (I2C, TCA9555, codec, LED, buttons, RTC) → audio → network. Even if a sub-feature fails (LED, wake word model, and so on), the rest works | main, board | P0 | 1 | Each step's success/failure is logged, and conversation works even if the LED fails |
| SYS-02 | Startup sound | After initialization finishes, play `startup.mp3` (16kHz, 3.5 seconds). Follows the volume setting; skipped if volume is 0 | audio_core | P1 | 1 | Plays within 5 seconds of power-on |
| SYS-03 | Restoring RTC time | At boot, set the system time from the PCF85063. When SNTP sync succeeds, update the RTC | board(rtc), net | P1 | 1 | TLS connection succeeds right after a reboot, even before SNTP |
| SYS-04 | Status LED ring | 7 WS2812B LEDs on GPIO38 (design document Section 2.0). Show states per the color table in design document Section 2.15. When states overlap, follow the priority table in design document Section 2.15 (factory reset > OTA > error > BLE window > Wi-Fi connecting > wake word detected > conversation > music > Telegram notification > standby) | board(led_ring) | P0 | 1 | Create each state by hand and check the color and pattern |
| SYS-05 | LED brightness | Adjust LED brightness 0–100% in the app. At 0, everything is off except error indications | led_ring / audio | P2 | 6 | Setting persists after reboot |
| SYS-06 | Key2 short press | Pressed and released in under 3 seconds: ends the conversation if one is running, otherwise starts one (starts a conversation even while music plays; the music ducks — Q5 decision 2026-10-03) | buttons | P0 | 1 | 20ms polling, 40ms debounce, no misbehavior on repeated presses |
| SYS-07 | Key2 3 seconds | At 3 seconds the ring turns sky blue; releasing between 3 and 7 seconds opens the BLE window (5 minutes with no connection, extended while connected, 15 minutes max) | buttons, ble_prov | P0 | 2 | Conversation, music, and LAN keep working while the window is open |
| SYS-08 | Key2 10 seconds | From 7 seconds the red ring fills up as a warning (releasing now cancels); at 10 seconds immediately erase `nvs` and `secrets` + restore preset defaults, then reboot | buttons, settings | P0 | 2 | Boots into provisioning mode after the reset |
| SYS-09 | Remote reboot | Reboot request from the app. Refused during a conversation (409) | local_api / system | P1 | 2 | Reboots within 2 seconds of the response |
| SYS-10 | Task watchdog | Task WDT 10 seconds. If something hangs, reboot automatically and save the reboot reason | main | P0 | 1 | After forcibly stalling a task, the reason is visible after reboot |
| SYS-11 | Diagnostics | Uptime, reboot reason, internal RAM/PSRAM free and minimum, Wi-Fi RSSI, task stack headroom, last 5 failures | local_api / system | P1 | 2 | Shown on the app's System screen |
| SYS-12 | Serial log | Per-module logs on the USB console. Secrets, Wi-Fi passwords, message bodies, and conversation transcripts are never printed | all | P0 | 1 | Zero secrets found in a full search of the logs |
| SYS-13 | Time sync | SNTP after Wi-Fi connects (`pool.ntp.org`, Korean time zone KST for display). On failure, retry every minute | net | P0 | 1 | Sync result logged |
| SYS-14 | Low-power standby | Wi-Fi power save (modem sleep) when there's no conversation or music. Power save off at conversation start (as in the existing code) | net, live_voice | P2 | 6 | Standby current measurement recorded |
| SYS-15 | Volume buttons | Key1 volume down, Key3 volume up (steps of 5, holding repeats every 0.3 seconds, 0–80) | buttons, audio_core | P0 | 1 | Changed value saved to NVS, reflected in the app via WS `volume` |

## 2. Provisioning and Connectivity (PRV)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| PRV-01 | First-boot provisioning | If there's no provisioning record or no Wi-Fi info, start BLE advertising automatically (no time limit) | ble_prov | P0 | 2 | A new board appears in the app's search list |
| PRV-02 | BLE advertising | Name `JARVIS_` + last 6 digits of the MAC, includes service UUID `0xFF50` | ble_prov | P0 | 2 | The app filters by name prefix and UUID |
| PRV-03 | BLE connection and bonding | LE Secure Connections Just Works bonding. Write characteristics are allowed only on an encrypted link | ble_prov / provisioning | P0 | 2 | Write attempts before encryption are refused |
| PRV-04 | Wi-Fi list | When the app writes to 0xFF54, the device scans in a worker task and sends up to 20 entries, one notification per AP (SSID, RSSI, security type). For a repeated SSID, only the strongest. On failure, count `0xFF`. 2.4GHz only. Both iOS and Android use this method (no phone Wi-Fi scan) | ble_prov, net / provisioning | P0 | 2 | BLE connection stays up during the scan |
| PRV-05 | Wi-Fi setup | Subscribe to notifications → SSID (0xFF51, UTF-8) → password (0xFF52, UTF-8, length 0 for open networks) → connection attempt → result notification (0xFF53). Exactly one final status per password (success / SSID not found / auth failed / timeout 20 seconds). Supports typing a hidden SSID | ble_prov, net / provisioning | P0 | 2 | A wrong password shows "auth failed"; connecting to a Korean-named SSID succeeds |
| PRV-06 | OpenAI key entry | Settings command `secret.set openai_key`. Saved after a format check (length 20–512, printable ASCII). The app shows only whether it's saved | ble_prov, settings / keys | P0 | 2 | Conversation works after reboot |
| PRV-07 | Phone registration | Settings command `api.pair` (per-install `phone_id`, phone name). The device creates a LAN token and returns it. The same `phone_id` replaces the existing registration. Up to 5 phones; when full, `PHONES_FULL` + the list → in the app, pick a phone to remove and retry with `evict` | ble_prov, local_api / provisioning | P0 | 2 | A LAN API call with the received token succeeds |
| PRV-08 | Provisioning done | `0x01` to 0xFF88 → only if Wi-Fi succeeded (status 2) in this connection, save Wi-Fi + reboot after 2 seconds. With no Wi-Fi change, just close the window without rebooting. Secrets, settings, and phone registrations are saved as soon as they're requested | ble_prov | P0 | 2 | Enters normal mode after reboot. Changing only a key and finishing keeps the saved Wi-Fi |
| PRV-09 | Re-provisioning | Opening the window with Key2 3 seconds (SYS-07) allows changing Wi-Fi, replacing keys, adding phones, and registering Telegram and Spotify while keeping existing settings. If Wi-Fi isn't changed, finish with `prov.close`, no reboot | ble_prov / provisioning | P0 | 2 | Existing assistant settings kept after a Wi-Fi change |
| PRV-10 | Wi-Fi auto-reconnect | When disconnected, keep retrying starting at 1 second, doubling up to a 30-second interval. If connected but no IP arrives within 45 seconds, disconnect and retry (DHCP watchdog) | net(wifi_manager) | P0 | 1 | Recovers automatically after a router reboot |
| PRV-11 | Strongest AP selection | At boot, choose the strongest AP among those with the same SSID (as in the existing code) | net | P1 | 1 | Checked on a mesh router setup |
| PRV-12 | mDNS advertising | `_aispeaker._tcp`, TXT `id`, `fw`, `name`. Host name `jarvis-XXXXXX.local` | net(mdns) | P0 | 2 | The app finds it without knowing the IP |
| PRV-13 | LAN authentication | `Authorization: Bearer` on every LAN API and WebSocket. Wrong → 401 (revoked token). 5 consecutive failures from the same IP → 429 for 30 seconds | local_api | P0 | 2 | A call without a token gets 401 |
| PRV-14 | Phone revocation | View and revoke registered phones in the app. The list marks your own phone (`self`); revoking yourself shows a warning | local_api / system | P1 | 2 | A call with a revoked token gets 401 |
| PRV-15 | BLE shutdown | On 0xFF88, `prov.close`, or timeout (button window: 5 minutes with no connection, 15 minutes max), shut NimBLE down completely and return the memory. An unprovisioned first boot has no time limit | ble_prov | P0 | 2 | Internal RAM free increases after shutdown |

## 3. Voice Conversation (VOI)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| VOI-01 | Wake word detection | WakeNet9 **"Computer" (default)** or "Jarvis" (not used, low detection rate). Detected only on the device from 16kHz microphone audio — the raw microphone when the speaker is quiet, echo-cancelled audio while it's making sound (changed 2026-10-03: Jarvis not used because of its low detection rate on the real board, Chapter 6, Section 6.2 of the book) | wake | P0 | 1 | Meets the detection rate criteria in design document Section 6 |
| VOI-02 | Wake word response | On detection, an immediate green flash + a short confirmation tone. Music ducks | wake, audio_core | P0 | 1 | Reacts within 200ms of detection |
| VOI-03 | Post-detection holdoff | No re-detection for 3 seconds right after a detection (existing code) | wake | P0 | 1 | No repeated false detections |
| VOI-04 | Wake word during music | Wake word detection even while radio or Spotify plays (hardware reference AEC) | audio_core, wake | P1 | 3 | 15 or more out of 20 at volume 50 |
| VOI-05 | Session connection | Check Wi-Fi → check time (RTC first) → connect WSS `gpt-live-1` → `session.start` (instructions, voice, tools). Orange spin while connecting | live_voice, assistant | P0 | 1 | Wake word → ready tone within 3 seconds |
| VOI-06 | Ready tone | When the session is ready (`session.started`), play the ready tone. Then you can speak | live_voice | P0 | 1 | Audio before the ready tone is discarded |
| VOI-07 | Live conversation | Upload microphone PCM in batches of up to 64ms, play the reply audio immediately. Blue level meter while the reply plays | live_voice, audio_core | P0 | 1 | No dropouts in a 10-minute conversation |
| VOI-08 | Barge-in | If the user speaks while the assistant is talking, the assistant stops and listens (handled server-side; the device supports it with echo cancellation) | audio_core | P1 | 1 | Reacts to 8 or more of 10 interruptions during a reply |
| VOI-09 | Hang-up phrase | End when the input transcription contains "goodbye computer" / "bye computer", "goodbye alexa" / "bye alexa", "goodbye jarvis" / "bye jarvis", or "end conversation" / "end the conversation" / "stop conversation" (not after "don't", "not" or "never"). The Korean "잘가 컴퓨터" (goodbye, Computer), "잘가 자비스" (goodbye, Jarvis) and "대화 종료" (end conversation) also work. Wait 600ms after the last word | live_voice(hangup) | P0 | 1 | Doesn't react when it's inside a longer word ("굿바이 자비스온") |
| VOI-10 | Button end | Key2 short press during a conversation → ends immediately | buttons | P0 | 1 | |
| VOI-11 | No-response timeout | End after 60 seconds with no conversation (while reply audio plays counts as conversation) | live_voice | P0 | 1 | |
| VOI-12 | Maximum length | One conversation lasts at most 10 minutes | live_voice | P0 | 1 | |
| VOI-13 | Normal shutdown | Send `session.close` → wait for usage (up to 15 seconds) → return to waiting for the wake word | live_voice | P0 | 1 | Usage (seconds) recorded in diagnostics |
| VOI-14 | Conversation failure handling | On connection, auth, or send failure: red for 3 seconds + error tone, no automatic retry. Save the failure reason in diagnostics | live_voice | P0 | 1 | Key error and internet loss are distinguished as reasons |
| VOI-15 | Async tool execution | Tools that need HTTPS run in `tool_worker`. Microphone upload continues while they run | assistant | P0 | 1 | Upload delay of 100ms or less during tool execution |
| VOI-16 | Conversation language | Default language English. Switch to Korean with the assistant setting `language` | assistant | P0 | 1 | |
| VOI-17 | Start and end conversations from the app | Start/end with the Home screen button; conversation state shown in real time | local_api / devices | P1 | 2 | |
| VOI-18 | Wake word on/off | When off, conversations start only from the button or the app | wake / audio | P0 | 2 | Setting persists |
| VOI-19 | Wake word detection test | For 60 seconds, only detect and play the confirmation tone (no conversation opened, no charge) | wake / audio | P1 | 2 | The app shows the detection count during the test |
| VOI-20 | No conversation records kept | The device doesn't store audio or transcripts | all | P0 | 1 | Flash and log inspection |
| VOI-21 | Wake word choice and sensitivity | Choose "Computer" (default) / "Jarvis", sensitivity 0–100 (default **80**; higher reacts more readily but with more false detections), wake word input boost 0–24 dB (default 12). Set in the app | wake / audio | P0 | 2 | Takes effect immediately, persists after reboot |

## 4. Assistant Settings and Memory (AST)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| AST-01 | Name | The assistant's name in conversation (default Jarvis, ≤32B). The wake word (default Computer) doesn't change. From the app, or "From now on your name is Sage" | assistant / assistant | P1 | 2 | Introduces itself with the new name from the next conversation |
| AST-02 | Purpose and tone | Free text ≤600B (example: "Keep your answers short") | assistant | P1 | 2 | |
| AST-03 | Language | ko / en | assistant | P0 | 2 | |
| AST-04 | Voice | 22 voices supported by `gpt-live-1`. Choose in the app, or "Change your voice to Cedar". Applies from the next conversation | assistant | P1 | 2 | Replies in the changed voice |
| AST-05 | Location | City and country ≤96B. Used for weather and local searches. From the app, or "Save my location as Seoul" | assistant | P0 | 2 | |
| AST-06 | Units | metric (default) / imperial | assistant | P1 | 2 | |
| AST-07 | Use web search | When off, it says it can't check the latest information | assistant | P1 | 2 | |
| AST-08 | Allow voice changes to settings | When off, volume, name, memories, and so on can't be changed by voice | assistant | P1 | 2 | |
| AST-09 | Saving memories | "Remember that I'm vegetarian" → up to 12 (key ≤32, value ≤160B). When full, it asks what to delete | assistant | P1 | 1 | Reflected in the next conversation, even after a reboot |
| AST-10 | Automatic memory | When on, automatically saves stable facts the user stated directly. Asks first about health, finances, addresses, or children. Off by default | assistant | P2 | 2 | |
| AST-11 | Viewing and deleting memories | Delete from the app's list, or "Forget that" | assistant / assistant | P1 | 2 | |

## 5. Information Lookup (INF)

All handled by OpenAI's hosted `web_search`. The device only puts location, units, and the current time into the instructions.

| ID | Feature | Example utterance | Detailed behavior | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| INF-01 | Today's and tomorrow's weather | "How's the weather today?", "Will it rain tomorrow?" | Based on the saved location. If there's no location, it asks. Briefly mentions the source and reference time | P0 | 1 | With no location set, it asks instead of making something up |
| INF-02 | Weekly weather | "What's the weather this weekend?" | | P1 | 1 | |
| INF-03 | News | "Tell me today's top news", "Business news" | A summary of about 3 items | P0 | 1 | |
| INF-04 | Stocks | "What's Samsung Electronics' stock price?", "Apple stock" | Current price, change, reference time. Mentions whether the market is closed. No investment advice | P1 | 1 | Never states a number without a reference time |
| INF-05 | General search | "How late is the pharmacy nearby open?" | If the result is uncertain, it says so | P1 | 1 | |
| INF-06 | Time and date | "What time is it?" | Uses the device time (KST) | P0 | 1 | |
| INF-07 | Dedicated stock API | With a key (`stock_key`), look up quotes with the `get_stock_quote` tool. Without a key, the INF-04 method | P2 | 6 | Tool not registered when there's no key |

## 6. Audio Settings (AUD)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| AUD-01 | Speaker volume | 0–80 (upper limit to prevent speaker distortion). App slider, or "Volume to 60", "Turn it down a bit" (reads the current value, then changes it relatively) | audio_core / audio | P0 | 1 | Takes effect immediately, persists after reboot |
| AUD-02 | Microphone gain | 0–36dB (excluding 33, in 3dB steps) | audio_core / audio | P1 | 2 | |
| AUD-03 | Voice microphone calibration | "Calibrate the microphone" → measure quiet → measure speech → verify, then save (existing code) | assistant(mic_control) | P2 | 1 | On verification failure, the previous value is kept |
| AUD-04 | Auto gain | Corrects 0.5–2x to match speech loudness. On/off | audio_core | P2 | 1 | |
| AUD-05 | Ducking amount | Music attenuation during conversation 0–40dB (default 20) | audio_core / audio | P1 | 3 | |
| AUD-06 | Pause Spotify during conversation | When on, pause and resume instead of ducking | media_spotify / audio | P2 | 5 | |
| AUD-07 | Speaker test | Play a test tone from the app | audio_core / audio | P1 | 2 | |

## 7. Internet Radio (RAD)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| RAD-01 | Preset playback | "Play KEXP", "Play the radio" (last station, NVS `last_preset`/`last_url`) | media_radio, assistant | P1 | 3 | Sound within 3 seconds of the command |
| RAD-02 | Genre playback | "Play jazz radio" → a preset with a matching genre → if none, the top result of a Radio-Browser search | media_radio | P1 | 3 | |
| RAD-03 | Stop, pause, resume | Voice "Turn off the radio", app buttons (Key2 short press starts a conversation, Q5 decision) | media_radio | P1 | 3 | |
| RAD-04 | Now playing | Song title from ICY metadata. "What song is this?" / shown in the app | media_radio | P1 | 3 | Station name only if there's no metadata |
| RAD-05 | Format support | MP3, AAC (including HE-AAC), HTTP/HTTPS, `.pls`, `.m3u`, 302 redirects | media_radio | P1 | 3 | All 13 default presets play |
| RAD-06 | Auto-reconnect | If the stream drops, retry starting at 1 second up to a 30-second interval. After 5 failures, stop and play an alert tone | media_radio | P1 | 3 | Recovers after a router reboot |
| RAD-07 | Buffering indication | Slow white LED blink while buffering | media_radio, led_ring | P2 | 3 | |
| RAD-08 | Preset management | Add, delete, reorder, rename in the app. Up to 20 (littlefs `/presets.json`) | local_api / music | P1 | 3 | |
| RAD-09 | Station search | The app searches the Radio-Browser API by name, genre, and country (doesn't go through the device) | music | P1 | 3 | |
| RAD-10 | Preview | Preview the stream in the app itself, then add it as a preset | music | P2 | 3 | |
| RAD-11 | Play from the app | Tap in the preset list to play on the speaker | local_api / music | P1 | 3 | |
| RAD-12 | Default presets | 13: US music stations KEXP Seattle, KCRW Eclectic24, WQXR Classical, WWOZ New Orleans, WFMU Freeform, KJazz 88.1 (direct MP3 streams), then CNN, CNN International, Bloomberg Radio, NPR, WNYC, C-SPAN Radio, BBC World Service. HLS streams can't be played, so they aren't included | media_radio | P1 | 3 | |

## 8. Spotify (SPT)

Preparation: in **each home that uses the speaker, one main account creates a Spotify developer app by hand, once, following the Flutter app's guide**, and enters the `client_id` into the app (SPT-13, option B). SPT-01–03 (playing on the speaker from the phone's Spotify app) work without a developer app; SPT-04–06 and 09 (voice control, Web API) need one. Neither the speaker nor the app can create the developer app automatically (design document Section 2.10).

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| SPT-01 | Connect device listing | Appears under the assistant's name in the Spotify app's "Devices" list on the same Wi-Fi (Zeroconf). Logs in with the main account at boot | media_spotify | P1 | 5 | Each family Premium account can select it |
| SPT-02 | Play from the phone | Choosing the speaker in the Spotify app plays directly on the speaker (continues even if the phone is turned off) | media_spotify | P1 | 5 | |
| SPT-03 | Spotify app controls reflected | Play, pause, next, volume, and seek in the Spotify app are reflected on the speaker | media_spotify | P1 | 5 | |
| SPT-04 | Voice search playback | "Play IU songs", "Play a mellow jazz playlist" → Web API search (up to 10) → play on this device | media_spotify, assistant | P1 | 5 | |
| SPT-05 | Voice control | "Next song", "Previous song", "Stop", "Play again". Only while playing with the main account. If another family account is playing, it says "Another family account is using it" | media_spotify | P1 | 5 | |
| SPT-06 | Now playing | "What song is this?" → song and artist | media_spotify | P1 | 5 | |
| SPT-07 | App login | PKCE login with the `client_id` from SPT-13 → BLE window with Key2 3 seconds → pass `client_id` and the refresh token together with `spotify.link`. After that, the app doesn't refresh the token itself. No Client Secret | spotify | P1 | 5 | |
| SPT-08 | Automatic token refresh | Refresh before expiry. Save a new refresh token immediately when received | media_spotify | P1 | 5 | Voice playback still works after a week untouched |
| SPT-09 | Connection status | The app shows the logged-in account, Connect status, and last error | spotify | P1 | 5 | |
| SPT-10 | Log out | Disconnect in the app (LAN `DELETE /spotify` or BLE `spotify.logout`) → the speaker's `client_id`, tokens, and Connect credentials are deleted. The app remembers `client_id` and prefills it on re-login | spotify | P1 | 5 | |
| SPT-11 | Switching with radio | When Spotify plays, the radio stops, and vice versa | media_* | P1 | 5 | |
| SPT-12 | Error guidance | Not Premium or user not registered (developer mode, 5 users), re-login needed (`invalid_grant`), redirect URI mismatch, developer app limit exceeded → explain the cause and fix by voice and in the app | media_spotify / spotify | P1 | 5 | |
| SPT-13 | Developer app registration guide | The app shows a step-by-step guide screen and opens the Spotify Developer Dashboard in the browser. A copy button for the redirect URI, per-screen explanations, notes on the developer app limit and the Premium requirement. Checks the format of the `client_id` the user pastes (32 hex digits) and verifies the setup right away with a PKCE login | spotify | P1 | 5 | A first-time user finishes registration within 10 minutes from the guide alone. If the redirect URI is wrong, it points out the cause |

## 9. Telegram (TLG)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| TLG-01 | Bot setup guide | The app guides you to create **a bot just for this speaker** with BotFather, invite it to a group, and turn off privacy mode (after turning it off, the bot must be removed from the group and invited again for it to take effect) | telegram | P1 | 4 | |
| TLG-02 | Token check and save | The app checks it with `getMe` → BLE window with Key2 3 seconds → saved on the speaker | telegram, ble_prov | P1 | 4 | A wrong token is rejected before saving |
| TLG-03 | Registering a chat | The app issues a 6-digit code (5 minutes, single use, invalid after 5 wrong tries) → a family member sends `/pair code` in a private chat with the bot, or `/pair@botname code` in a group → the speaker registers it and notifies the app (WS `tg_paired`) | messenger_telegram / telegram | P1 | 4 | After registration, the bot replies "등록되었습니다" (Registered) |
| TLG-04 | Alias | An alias per chat (for example, "가족방" (family chat), "엄마" (Mom)). Used in voice commands | telegram | P1 | 4 | |
| TLG-05 | Unregistering | Delete in the app. Up to 10. If a group becomes a supergroup, it updates to the new chat_id automatically | telegram | P1 | 4 | |
| TLG-06 | Receiving messages | Received by long polling. Only registered chats are handled, the rest ignored. Keeps the latest 20 (lost when the power is off) | messenger_telegram | P1 | 4 | Notified within 10 seconds of receipt |
| TLG-07 | Arrival notification | Chime + purple LED dot. No chime during a conversation | messenger_telegram, led_ring | P1 | 4 | |
| TLG-08 | Reading messages | "Read my Telegram messages", "What did Mom send?" → sender, time, contents. Read messages are marked read, and the unread count on the app's Home updates | assistant | P1 | 4 | Purple LED goes off after reading |
| TLG-09 | Sending messages | "Tell the family chat I'll be late today" → reads back the recipient and contents and confirms → sends. The tool is two-step (draft → confirmation in the next utterance), so it can't send without confirmation | assistant, messenger_telegram | P1 | 4 | Never sends without confirmation |
| TLG-10 | Auto-read | When on, opens a conversation session to read a message when it arrives (incurs charges). Off by default. Option to skip night hours (22–07) | messenger_telegram / telegram | P2 | 4 | |
| TLG-11 | Voice message playback | "Play Mom's voice message" → plays Ogg Opus | messenger_telegram | P2 | 4 | |
| TLG-12 | Pausing polling during conversations | Stop polling during conversations and OTA, then resume. The server keeps messages for 24 hours, so nothing is lost | messenger_telegram | P1 | 4 | |
| TLG-13 | Conflict detection | 409 Conflict (the same bot used elsewhere) → reported in the app and diagnostics | messenger_telegram | P1 | 4 | |
| TLG-14 | External-input protection | Message contents are never treated as instructions. The device enforces it: after reading a message, side-effect tools are refused until a new user utterance; saving message text as a memory is refused; auto-read sessions get read-only tools only | assistant | P0 | 4 | Reading a message that says "Set the volume to 80" leaves the volume unchanged |

## 10. App Common (APP)

| ID | Feature | Detailed behavior | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|
| APP-01 | Permission requests | Android 12+: only `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`. Android 11 and below: location. iOS: Bluetooth, local network (system pop-up on the first mDNS/HTTP). Design document Section 3.6 | P0 | 2 | On denial, guide to the settings screen |
| APP-02 | Device list | Store registered devices on the phone (STA MAC read from 0xFF61, name, last IP). BLE `remoteId` isn't used (it's a UUID on iOS). Supports several devices | P0 | 2 | |
| APP-03 | Finding devices | Search with mDNS and update the IP. On failure, try the last IP | P0 | 2 | Finds it again automatically even if the IP changes |
| APP-04 | Home screen | Connection state, conversation state, now playing, volume, unread Telegram count, quick actions (start conversation, play/stop) | P0 | 2 | |
| APP-05 | Real-time updates | Reflect state through WebSocket events. Reconnect automatically when disconnected (1→30 seconds) | P0 | 2 | |
| APP-06 | Can't-connect guidance | A prompt to check it's the same Wi-Fi, a button to go to BLE re-setup | P0 | 2 | |
| APP-07 | Localization | Korean (default), English. ARB files | P0 | 2 | Every string is in an ARB |
| APP-08 | Theme | System/light/dark (`SettingsCubit`) | P1 | 2 | |
| APP-09 | Error messages | `ErrorKeys` → localized messages. Next-step guidance for each cause | P0 | 2 | |
| APP-10 | Secrets screen | Shows the OpenAI key only as "saved/none"; replace (BLE), delete (LAN). Telegram and Spotify status belong to their own feature screens; here, only links | P0 | 2 | The raw key appears nowhere on any app screen |
| APP-11 | Offline mode | Shows the saved device list and guidance even when not connected to a device | P1 | 2 | |
| APP-12 | App info | App version, open-source licenses | P2 | 6 | |

## 11. Firmware Update (OTA)

| ID | Feature | Detailed behavior | FW / APP | Priority | Phase | Completion criterion |
|:--|:--|:--|:--|:--|:--|:--|
| OTA-01 | Version display | The app shows the current firmware version and build date and time | local_api / system | P1 | 2 | |
| OTA-02 | Firmware upload | Choose a `.bin` in the app → upload over the LAN → press Key2 on the speaker within 60 seconds to confirm → progress shown | local_api / system | P1 | 6 | |
| OTA-03 | Image checks | **Signature verification** (developer signing key, no eFuse), project name, chip type, image size (≤4MB). Refused if any differ. 409 during a conversation | local_api | P1 | 6 | Unsigned images and images from other projects are refused |
| OTA-04 | Protection during update | Stop conversation, music, and Telegram; LED progress indication | main | P1 | 6 | |
| OTA-05 | Automatic rollback | If the new firmware fails Wi-Fi or audio initialization, roll back to the previous version | main | P1 | 6 | Rollback confirmed with a deliberately broken image |
| OTA-06 | Settings preserved | All settings and secrets kept after an update. Migration if the schema changes | settings | P0 | 6 | |

---

## 12. Voice Command Examples → Handling

| Example utterance | Handling | Related ID |
|:--|:--|:--|
| "Jarvis" (wake word) | Start a conversation | VOI-01 |
| (Press Key1 / Key3) | Volume down / up | SYS-15 |
| "How's the weather in Seoul today?" | `web_search` | INF-01 |
| "Tell me Samsung Electronics' stock price" | `web_search` | INF-04 |
| "Give me today's news briefing" | `web_search` | INF-03 |
| "Set the volume to 30" / "Turn it up a bit" | `get_device_settings` → `set_volume` | AUD-01 |
| "Play jazz radio" | `radio_play(genre)` | RAD-02 |
| "Play KEXP" | `radio_play(station)` | RAD-01 |
| "What song is playing now?" | `get_now_playing` | RAD-04, SPT-06 |
| "Play IU songs" | `spotify_play(query, artist)` | SPT-04 |
| "Next song" / "Stop" / "Play again" | `music_control` | SPT-05, RAD-03 |
| "Anything on Telegram?" | `telegram_read` | TLG-08 |
| "Tell the family chat I'll eat out and come home after" | A question confirming the contents → `telegram_send` | TLG-09 |
| "Save my location as Busan" | `set_location` | AST-05 |
| "Change your voice. What's available?" | `list_voices` → `set_voice` | AST-04 |
| "Remember that I have a cat" | `remember` | AST-09 |
| "Calibrate the microphone" | `calibrate_microphone` | AUD-03 |
| "Goodbye Jarvis" / "End conversation" (or "잘가 자비스" / "대화 종료") | Ended on the device | VOI-09 |

## 13. Handling Exceptions

| Situation | Device response | App display |
|:--|:--|:--|
| Wi-Fi down | Tries to reconnect, blue LED blink. On wake word, a "Not connected to the internet" notice tone | "The device isn't connected to Wi-Fi" |
| No OpenAI key | On wake word, error tone + red | Guides to the key entry screen |
| OpenAI auth failure or insufficient balance | Red for 3 seconds, reason saved in diagnostics | "Check your OpenAI account or key" |
| Radio station not responding | Stop after 5 retries + alert tone | Error mark on the preset |
| Spotify token expired or revoked | Says voice playback isn't available | Asks to log in again |
| Telegram token revoked | Polling stops, recorded in diagnostics | Asks to enter the token again |
| Out of memory | Pause lower features by priority (conversation > music > Telegram) | Warning in diagnostics |
| Another family member is using Spotify | On voice Spotify control, says "Another family account is using it" | The Spotify screen shows the account currently using it |
| Telegram 409 or token revoked | Polling stops, recorded in diagnostics | "This bot is being used elsewhere" / asks to enter the token again |
| Storage error (NVS) | Refuses the settings change, keeps the existing value | "Couldn't save" |
| App token revoked | 401 response | Guides to registering again over BLE |

## 14. Non-Functional Requirements

| Item | Criterion |
|:--|:--|
| Servers | No server, DB, or push server of our own. App ↔ speaker communicate directly |
| Privacy | Audio in standby never leaves the device. Conversation audio goes only to OpenAI. The device and app don't store audio or transcripts |
| Secrets | Plain-text NVS (at the current stage). The raw value can't be read over BLE or LAN. Writes over BLE only. Never logged. OTA uses signature verification + physical button confirmation |
| Responsiveness | Wake word → ready tone within 3 seconds; app action → reflected within 500ms (LAN) |
| Stability | 0 reboots in 24 hours of continuous operation. Recovers automatically after a router reboot |
| Memory | 40KB or more of internal RAM free: conversation + music (Telegram polling stopped), music + Telegram, BLE window + music |
| Cost | One conversation at most 10 minutes, 60-second no-response timeout, auto-read off by default |
| Maintenance | The app uses Clean Architecture + BLoC + get_it. The design document is the only reference for the BLE and LAN specifications |
| Tests | App BLoC unit tests, firmware host unit tests (pure logic: hang-up phrases, delegation parser, settings validation, and so on) |
