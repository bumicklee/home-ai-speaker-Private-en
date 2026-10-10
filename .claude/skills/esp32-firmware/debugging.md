# Firmware Debugging Sequence

There is one principle. **Settle the cause with evidence before fixing anything.** In this book, the cause was always found fastest when diagnostic logs went in first. When you get a log, work through 1–4 below in order. If the cause still isn't clear, use the prompts in 5 (PD-01–PD-04).

## 1. Getting a Log

```bash
source ~/esp/esp-idf-v5.5/export.sh
cd ~/home-ai-speaker/firmware
idf.py monitor                                   # log only
idf.py build flash monitor                       # flash new firmware, then log
idf.py monitor | tee ~/speaker-$(date +%H%M).log # watch and save to a file
```

- `Ctrl+]` quits. To restart the speaker from inside the monitor, press `Ctrl+T` then `Ctrl+R`.
- Starting the monitor reboots the speaker. Logs from before the reboot are gone, so **start it before you test.**
- A file saved with `tee` beats copying from the screen. Pasting often puts the same line in twice.
- When a log line prints in the middle of console input, press Enter once to clear the line, then type the command.

## 2. Reading One Line

```text
I (157094) ASSIST: guard: new user utterance
Level (ms since boot) Tag: Message
```

| Level | Meaning | What to do |
|:--|:--|:--|
| `I` | Info | Normal flow. Just read it |
| `W` | Warning. Something went off plan, but execution continues | Look into it **if it repeats** |
| `E` | Error. Something failed | Read the **5 to 10 lines just before and after it** together |

- This build sets `CONFIG_LOG_MAXIMUM_LEVEL_INFO=y`, so there are no `D` lines.
- The timestamp is **milliseconds since boot**, not wall-clock time. Subtract two timestamps to see how long something took.
- Lines starting with `---` are annotations added by the monitor (address → function name).
- **Errors come in chains.** The topmost (earliest) `E` line is the cause, and the lines below are effects. Words like `errno=Success` are only an effect; don't mistake them for a network problem.

```text
E (157124) esp-aes: Failed to allocate memory                     ← cause
E (157124) esp-tls-mbedtls: write error :-0x0001                  ← effect 1
E (157134) transport_base: esp_tls_conn_write error, errno=Success ← effect 2
W (157144) GLIVE: Voice connection ended (internal free 8967)     ← the symptom the user notices
```

### Tag Map

| Tag | Component | Look here when |
|:--|:--|:--|
| `MAIN` | Startup sequence, memory measurements, state machine | Boot problems, memory |
| `BOARD`, `CODEC`, `ES7210`, `ES8311` | Board init, mic and speaker chips | No sound |
| `AUDIO` | Mic and speaker processing, echo cancellation (AEC) | Volume, noise |
| `WAKE` | Wake word (Computer or Alexa) | No response when called |
| `WIFI`, `wifi:`, `SNTP`, `MDNS` | Internet, time, how the app finds the speaker | Connection drops |
| `LIVE` / `GLIVE` / `SAVER` | OpenAI Live / Gemini Live / Saver mode (both providers) | A conversation won't connect or drops |
| `ASSIST`, `TOOLS` | Tool execution, safeguards (guard) | "Do X for me" doesn't work |
| `RADIO`, `RADIO_SEARCH`, `PRESETS` | Internet radio | Radio drops out |
| `TELEGRAM`, `TG_STORE` | Telegram | Messages not arriving or not sending |
| `NOTES` | Notes and schedule | Notes, reminders |
| `API`, `API_AUTH`, `API_WS`, `BLE_PROV`, `BLE_GATT`, `BLE_CMD`, `PHONES` | Communication with the app | App connection |
| `esp-tls`, `esp-aes`, `websocket_client`, `transport_base` | Encrypted communication (ESP-IDF libraries) | Connection failures |

## 3. Quick Checklist (in this order when you get a log)

1. `rst:` — why did it restart?
2. `App version` — did the fixed firmware really get flashed? `-dirty` means uncommitted changes were included.
3. `heap after boot done` — is internal 12,000 or more?
4. Search for `E (` — the first error line and the 10 lines before it.
5. Search for `session ended` — how did the conversation end?
6. Search for `W (` — repeating warnings.
7. `AUDIO: levels` — any values near 32767 (clipping)?
8. `underruns`, `dropped` — are they 0?

```bash
grep -nE "^E \(|session ended|could not reserve|internal free" speaker.log
grep -n "App version\|heap after boot done" speaker.log
```

### Reboot Reason (`rst:`)

| rst value | Meaning | Verdict |
|:--|:--|:--|
| `0x1 (POWERON)` | Fresh power-on | Normal |
| `0x15 (USB_UART_CHIP_RESET)` | Reset by USB (monitor or flash) | Normal (when starting the monitor) |
| `0xc (RTC_SW_CPU_RST)` | Software restart (`esp_restart`, factory reset, after a panic) | Check whether a `Guru Meditation` came before it |
| `0x7`, `0x8` (`TG0WDT`, `TG1WDT`) | Watchdog. Some task stalled for too long | A bug. You need the log from before the restart |
| `0xf (RTCWDT_BROWN_OUT)` | Undervoltage | Power supply or cable problem |

- A panic starts with one of `Guru Meditation Error`, `assert failed:`, `ESP_ERROR_CHECK failed:` … `abort() was called`, or `E task_wdt: Aborting.`, and all four are followed by `Backtrace:`. **Search for `Backtrace:`.**
- This build reboots right after a panic (`CONFIG_ESP_SYSTEM_PANIC_PRINT_REBOOT=y`), and core dumps are off. The only record of the cause is the `Backtrace:` line in the log before the reboot.
- `E task_wdt: Task watchdog got triggered` means the IDLE task on one core couldn't run for 10 seconds (`CONFIG_ESP_TASK_WDT_TIMEOUT_S=10`). Some task keeps running without letting go of the CPU. A task asleep while waiting is not the cause.
- If the backtrace has only addresses, open it again with `idf.py monitor`. The monitor turns addresses into function names.

### Reading the Memory Line (the most important part)

Most of the failures I ran into while building were internal RAM shortages. `MAIN` prints the free memory each time it starts a component.

```text
I (1304) MAIN: heap after start        internal 249375 (largest 122880)  psram 6081564
I (1464) MAIN: heap after audio        internal 176167 (largest  69632)  psram 5834280
I (1564) MAIN: heap after net          internal  54271 (largest  24576)  psram 5709224
I (1904) MAIN: heap after local_api    internal  13499 (largest   7680)  psram 2687208
I (1954) MAIN: heap after boot done    internal  13371 (largest   7680)  psram 2686592
```

| Value | Meaning | Verdict |
|:--|:--|:--|
| `internal` | Total free internal RAM (bytes) | 12,000 or more: fine / below 10,000: TLS connections at risk of failing / in the 8,000s: real failures happen |
| `largest` | The largest single block of that free space | A borrow has to be served as one block. Even with plenty in total, a small largest block means failure (fragmentation) |
| `psram` | Free PSRAM | 1MB or more is plenty |

- The numbers above are an example from firmware with everything up to Chapter 18. The numbers differ from firmware to firmware. When you add a new feature, **compare with the same line from the previous firmware** and write it in your work log (PD-04).
- The baseline is **internal 12,000 or more at the end of boot**.
- `MAIN: %s init failed: %s (feature disabled)` is a warning that one optional feature was turned off and boot continued. Write down which feature.

| Other lines that show memory | Meaning |
|:--|:--|
| `AUDIO: AEC uses 90912 B internal RAM` | Echo cancellation uses about 89KB of internal RAM (the biggest consumer) |
| `GLIVE/LIVE: Voice connection ended (internal free N)` | Free memory at the moment the conversation connection dropped. If N is below 10,000, suspect memory |
| `LIVE: could not reserve 12800 B for the voice task (largest internal N)` | Couldn't reserve the conversation task's slot up front. Fragmentation. Common after the radio is turned on |
| `TELEGRAM: bot connected (stack free min N B)` | The minimum free space in the Telegram task stack |
| `MAIN: BLE window: internal free %u (largest %u)` / `AUDIO: AEC suspended (internal free %u)` | Just before opening the BLE window / after AEC was suspended |

### Lines You Can Ignore

| Line | Why |
|:--|:--|
| `E I2S_IF: Mode 1 conflict sample_rate 16000 with 0` | The library prints it when the speaker chip is attached to the same I2S bus as the mic. If the boot sound plays normally, it's not a functional problem |
| `W CONSOLE: developer console enabled (disable CONFIG_APP_DEV_CONSOLE for release)` | Normal during development. Turn it off in the release build |
| `main_task: Returned from app_main()` | The startup sequence is finished. Other tasks carry on the work |
| `MAIN: ready, but no OpenAI key: no announcement` | The current code checks only the OpenAI key and skips the ready announcement. It also appears on a speaker that has only a Gemini key |

### Common Error Lines

| Error line | Meaning | What to do |
|:--|:--|:--|
| `ESP_ERROR_CHECK failed: esp_err_t 0x101 (ESP_ERR_NO_MEM)` … `Rebooting...` | Initialization fails for lack of internal RAM, and it keeps rebooting | Use the `heap after` lines to find the stage that runs short. Check the PSRAM options in `sdkconfig.defaults` (`CONFIG_SPIRAM_XIP_FROM_PSRAM=y`, etc.) (P07-01) |
| `E esp-aes: Failed to allocate memory` | The crypto hardware couldn't borrow a temporary buffer in internal RAM | If it starts right after boot, check whether `heap after boot done` is below 10,000 (P18-03). If it happens during a conversation with the radio on, it's fragmentation (P18-05). Check that `sdkconfig` has `# CONFIG_MBEDTLS_HARDWARE_AES is not set` |
| `E esp-tls-mbedtls: mbedtls_ssl_handshake returned -0x7F00` | Out of memory during connection negotiation | Check internal RAM |
| `E esp-tls: couldn't get hostname … getaddrinfo() returns 202` | DNS failure | Check whether it falls back to the backup DNS, and the internet connection itself |
| `E websocket_client: Error create websocket task` | No contiguous block to create the conversation connection task (fragmentation). Not an internet problem | P07-05 |
| `E BLE_INIT: Malloc failed` → `nimble init: ESP_ERR_NO_MEM` | Not enough internal RAM for the BLE controller | Check that `AEC suspended` appears before the window opens (P08-04) |
| `W GLIVE: Voice startup timed out (internal free N)` | No `setup complete` within 20 seconds of connecting | Find the `server closed` line (P18-04) |
| `W GLIVE/LIVE: Speaker backlog (internal free N)` | Playback queue overflow | P18-05 |
| `***ERROR*** A stack overflow in task X` | Task X's stack is too small | Increase that task's stack. If it's `Tmr Svc`, check `CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH=4096` |
| `SAVER: stt http 401` / `SAVER: gemini http 401`, `403` | AI key problem (for Gemini, also suspect the `x-goog-api-key` header) | Check the key |
| `SAVER: gemini http 400` | Request format problem (tool format, etc.) | If you get stuck in P18-01 |
| `TELEGRAM: poll failed (HTTP 409)` → `state conflict` | Another program is using the same bot token | Turn off the other program |
| `RADIO: unsupported playlist (HLS?)` | HLS station | P14-04 |
| `WAKE: wake model failed to load` | The model partition is empty | Flash everything with `idf.py -p <port> flash` |
| `WAKE: … peak` in the hundreds | Mic sound too quiet | P07-04. Console `mic 36`, `wakegain 12` |

## 4. Symptom → Lines to Check First → Prompt

| Symptom | Lines to check first | Prompt (prompts.md) |
|:--|:--|:--|
| Keeps rebooting on first boot | `ESP_ERR_NO_MEM`, `heap after …` | P07-01 → P07-02 → P07-03 |
| `talk` works but the wake word doesn't | `WAKE: listening …`, `AUDIO: levels`, `WAKE: stats` | P07-04 |
| A conversation won't connect after being on for a long time | `Error create websocket task`, `could not reserve` | P07-05 |
| The BLE window won't open on a speaker that's already set up | `BLE_INIT: Malloc failed` | P08-04 |
| The radio plays with dropouts | `RADIO: net … underruns …` | If you get stuck in P14-01, PD-02 |
| Crackling during ducking | `RADIO: … underruns +0` | P14-05 |
| Telegram replies are blocked | `TOOLS: run telegram_send`, `ASSIST: guard: … blocked` | P15-04 |
| A conversation doesn't end even past the idle timeout | `LIVE: limits`, `LIVE: idle …` | P15-05 |
| Adding a note reboots the speaker | `task_wdt`, `Backtrace:` | P16-04 |
| Saver mode can't understand speech | `SAVER: limits`, `SAVER: listen 5 s: …` | P17-04 |
| TLS fails after adding a new engine | `esp-aes: Failed to allocate memory`, `heap after boot done` | P18-03 |
| Gemini drops 20 seconds after connecting | `GLIVE: Voice startup timed out`, `server closed` | P18-04 |
| Conversations drop while the radio is on | `esp-aes …` or `Speaker backlog` | P18-05 |
| A symptom not listed above | The first `E` line and the lines around it | PD-01 → PD-02 |

## When You Paste a Log

- Include **30 seconds before and after** the moment of the problem. Error lines alone don't reveal the cause.
- If there was a reboot, the **log from before the reboot** (`Guru Meditation`, `Backtrace`) is what matters.
- Write one line about what you were doing. A line like "asked it to send a Telegram message while the radio was on" saves a lot of time.
- The firmware is built not to print keys, tokens, conversation content, message bodies, radio URLs, or Wi-Fi passwords. Still, skim it once before pasting. If the console screen shows a key you typed, delete that line before pasting.

## 5. Debugging and RCA Prompts (Reusable)

### PD-01 Paste the log and set up cause candidates
```text
I'm pasting the log. Timestamps and surrounding lines are intact. (log)
Don't fix anything yet. To do:
1) Separate what this log confirms as normal from the abnormal lines, in a table.
2) Set up three or more cause candidates, and for each write "lines the log must contain / must not contain if this is the cause" and compare with the actual log.
3) If the log alone can't decide, propose one or two diagnostic log lines that would (don't print the contents of values, keys, or URLs).
4) Leave the eliminated candidates in a "What it wasn't" table (suspect | why not | supporting log line). If there's no supporting line, "not yet eliminated".
Reference: the relevant section of the design document and the source file in question. Label conjecture "conjecture".
```
**How to verify** Check that every candidate has a supporting log line attached. Chapter 18, Failure B is an example of using this table to eliminate key, internet, memory, and setup rejection one line at a time.

### PD-02 Add diagnostic logs first
```text
(symptom in one line). Don't guess the cause; make the values used for the decision visible in the log.
Add: the values this feature uses to decide "yes/no" (thresholds, sizes, counts, time remaining), one line of settings at start, and one summary line at a fixed interval.
Do not change: behavior. Only add logs. Don't print contents, keys, URLs, or message bodies. Make the interval long so it doesn't interfere with input.
How to verify: one run of the next log must be able to decide which candidate is right. Write a table in advance of which numbers point to which cause.
```
**How to verify** This book's examples: `LIVE: idle …` (P15-05; the same-shaped `GLIVE: idle …` is in Chapter 18), `SAVER: listen 5 s: …` (Chapter 17), `RADIO: net …` (Chapter 14), `MAIN: heap after …` (Chapter 7).

### PD-03 Write an RCA document
```text
Write a root cause analysis document at docs/rca_<slug>.md. Reference: the RCA format in Chapter 19 of this book (format A for a single problem, format B when several are entangled).
Header: date written, target firmware commit (the output of git rev-parse --short HEAD), one-line status.
Format A: symptom (log as is, 5 lines before and after) | direct cause | root cause | contributing cause | impact | fix | remaining work. Then the timeline, what it wasn't, why it wasn't caught during development, how to verify (expected logs), and a recurrence prevention table.
Do not change: don't write the direct cause and the root cause as the same sentence. Distinguish "build passes" from "✅ verified on hardware" in the status. Leave anything I haven't seen on the real board as "needs hardware check".
How to verify: the recurrence prevention table has at least one line saying "added a log" or "added to the self-test".
```
**How to verify** Start writing it before fixing the code. After the fix, update only the status column.

### PD-04 Memory comparison
```text
I'm pasting the boot logs of the firmware with the new feature and of the previous firmware.
Put the MAIN: heap after … lines side by side in a table by stage (internal, largest, psram), and connect the stage where they differ with the code newly added at that stage.
List the candidates that use internal RAM (static arrays, default queues and semaphores, internal RAM task stacks, library allocations) in a table with sizes.
Do not change: don't fix yet.
How to verify: also note whether internal at the end of boot is above the warning line (12,000) and whether largest is bigger than the block a conversation needs.
```
**How to verify** Keep this table in your work log for every new feature. It's the lesson of Chapters 7 and 18.

The format for wrapping up after the RCA document is updated (T-06) and the review formats (PR-01, PR-02) are in the `speaker-method` skill's templates.md.
