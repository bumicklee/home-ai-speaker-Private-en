/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * Development console. Until BLE provisioning (Phase 2), enter Wi-Fi and API keys over USB and test conversations.
 *
 * The primary console is UART0 and USB-Serial-JTAG is a secondary console for log output, so the IDF REPL can't be used.
 * So, like the original firmware, read one line at a time directly with the USB-Serial-JTAG driver and pass it to esp_console_run().
 *
 * Secrets are only stored, never printed back. What you type stays on the terminal screen,
 * so don't share screen recordings.
 */
#include "dev_console.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "app_config.h"
#include "assistant.h"
#include "audio_core.h"
#include "delegation.h"
#include "driver/usb_serial_jtag.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "hangup_phrase.h"
#include "live_voice.h"
#include "mic_control.h"
#include "net.h"
#include "notes.h"
#include "notes_logic.h"
#include "secret_store.h"
#include "settings.h"
#include "wake.h"

#if CONFIG_APP_DEV_CONSOLE

static const char *TAG = "CONSOLE";

#define CONSOLE_LINE_MAX 640

static void reply(const char *fmt, ...)
{
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf) - 2, fmt, ap);
    va_end(ap);
    if (n < 0) {
        return;
    }
    if (n > (int)sizeof(buf) - 3) {
        n = sizeof(buf) - 3;
    }
    buf[n++] = '\r';
    buf[n++] = '\n';
    usb_serial_jtag_write_bytes(buf, n, pdMS_TO_TICKS(100));
}

static int cmd_wifi(int argc, char **argv)
{
    if (argc < 2 || argc > 3) {
        reply("usage: wifi <ssid> [password]");
        return 1;
    }
    esp_err_t err = settings_set_wifi(argv[1], argc == 3 ? argv[2] : "");
    if (argc == 3) {
        memset(argv[2], 0, strlen(argv[2]));
    }
    reply("wifi: %s (reboot or 'provision' to use it)", esp_err_to_name(err));
    return err != ESP_OK;
}

static int cmd_key(int argc, char **argv)
{
    if (argc != 2) {
        reply("usage: key <openai_api_key> | key clear");
        return 1;
    }
    esp_err_t err = !strcmp(argv[1], "clear") ? secret_erase(SECRET_OPENAI_KEY)
                                              : secret_set(SECRET_OPENAI_KEY, argv[1], strlen(argv[1]));
    memset(argv[1], 0, strlen(argv[1]));
    reply("key: %s", esp_err_to_name(err));
    return err != ESP_OK;
}

static int cmd_provision(int argc, char **argv)
{
    if (!settings_has_wifi()) {
        reply("set Wi-Fi first: wifi <ssid> [password]");
        return 1;
    }
    esp_err_t err = settings_set_provisioned(true);
    reply("provision: %s, rebooting", esp_err_to_name(err));
    vTaskDelay(pdMS_TO_TICKS(APP_PROV_REBOOT_DELAY_MS));
    esp_restart();
    return 0;
}

static int cmd_status(int argc, char **argv)
{
    settings_audio_t a;
    settings_get_audio(&a);
    uint8_t mac[6] = {0};
    net_get_sta_mac(mac);
    reply("fw %s  mac %02X%02X%02X%02X%02X%02X", APP_FW_VERSION, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    reply("provisioned %d  wifi_saved %d  wifi_up %d  time_valid %d", settings_is_provisioned(),
          settings_has_wifi(), net_is_connected(), net_time_valid());
    reply("openai_key %s", secret_exists(SECRET_OPENAI_KEY) ? "saved" : "missing");
    reply("voice state %d  \"%s\"  wake listening %d", live_voice_state(), live_voice_status(), wake_is_listening());
    reply("volume %d  mic_gain %d  auto_gain %d", audio_core_get_volume(), mic_gain(), mic_auto_gain());
    reply("heap internal %u (largest %u)  psram %u",
          (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
          (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
          (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    return 0;
}

static int cmd_talk(int argc, char **argv)
{
    reply("talk: %s", esp_err_to_name(live_voice_start()));
    return 0;
}

static int cmd_stop(int argc, char **argv)
{
    live_voice_stop();
    reply("stop: requested");
    return 0;
}

static int cmd_say(int argc, char **argv)
{
    if (argc < 2) {
        reply("usage: say <text>  (during a conversation)");
        return 1;
    }
    char text[601] = {0};
    for (int i = 1; i < argc; i++) {
        strlcat(text, argv[i], sizeof(text));
        if (i + 1 < argc) {
            strlcat(text, " ", sizeof(text));
        }
    }
    reply("say: %s", esp_err_to_name(live_voice_text(text)));
    return 0;
}

static int cmd_volume(int argc, char **argv)
{
    if (argc != 2) {
        reply("volume %d", audio_core_get_volume());
        return 0;
    }
    reply("volume: %s", esp_err_to_name(audio_core_set_volume(atoi(argv[1]))));
    return 0;
}

/* Hardware mic gain (ES7210, 0–36 dB, 3dB steps, no 33). Saved */
/*
 * Number argument check. When a log line prints in the middle of typing, two lines can arrive glued into one
 * (real board 2026-10-03: "wake on jarviwake on jarvis 70" → sensitivity 0), so don't accept any text as 0 the way atoi does.
 */
static bool parse_uint(const char *text, int max, int *out)
{
    if (!text || !text[0] || strlen(text) > 3) {
        return false;
    }
    int v = 0;
    for (const char *p = text; *p; p++) {
        if (*p < '0' || *p > '9') {
            return false;
        }
        v = v * 10 + (*p - '0');
    }
    if (v > max) {
        return false;
    }
    *out = v;
    return true;
}

static int cmd_wakegain(int argc, char **argv)
{
    settings_wake_t w;
    wake_get_config(&w);
    if (argc != 2) {
        reply("wake input gain +%d dB  (usage: wakegain <0-24>)", w.gain_db);
        return 0;
    }
    int gain;
    if (!parse_uint(argv[1], 24, &gain)) {
        reply("usage: wakegain <0-24>  (nothing changed)");
        return 1;
    }
    w.gain_db = (uint8_t)gain;
    reply("wakegain: %s (+%d dB)", esp_err_to_name(wake_set_config(&w)), w.gain_db);
    return 0;
}

static int cmd_mic(int argc, char **argv)
{
    if (argc < 2) {
        reply("mic_gain %d dB  auto_gain %d", mic_gain(), mic_auto_gain());
        reply("usage: mic <0|3|...|30|36> [auto|noauto]");
        return 0;
    }
    int gain;
    bool automatic = mic_auto_gain();
    if (argc > 3 || !parse_uint(argv[1], 36, &gain) ||
        (argc == 3 && strcmp(argv[2], "auto") && strcmp(argv[2], "noauto"))) {
        reply("usage: mic <0|3|...|30|36> [auto|noauto]  (nothing changed)");
        return 1;
    }
    if (argc == 3) {
        automatic = !strcmp(argv[2], "auto");
    }
    if (gain < 0 || gain > 36 || gain % 3 || gain == 33) {
        reply("gain must be 0-30 in steps of 3, or 36");
        return 1;
    }
    reply("mic: %s (gain %d dB, auto %d)", esp_err_to_name(mic_set(gain, automatic, true)), gain, automatic);
    return 0;
}

static int cmd_wake(int argc, char **argv)
{
    settings_wake_t w;
    wake_get_config(&w);
    int sensitivity = w.sensitivity;
    bool ok = argc <= 4 && (argc < 2 || !strcmp(argv[1], "on") || !strcmp(argv[1], "off")) &&
              (argc < 3 || !strcmp(argv[2], "alexa") || !strcmp(argv[2], "computer")) &&
              (argc < 4 || parse_uint(argv[3], 100, &sensitivity));
    if (!ok) {
        reply("usage: wake [on|off] [alexa|computer] [0-100]  (nothing changed)");
        return 1;
    }
    if (argc >= 2) {
        w.enabled = !strcmp(argv[1], "on");
    }
    if (argc >= 3) {
        w.phrase = !strcmp(argv[2], "computer") ? 1 : 0;
    }
    w.sensitivity = (uint8_t)sensitivity;
    if (argc >= 2) {
        reply("wake: %s", esp_err_to_name(wake_set_config(&w)));
    }
    reply("wake enabled %d  phrase %s  sensitivity %d  input gain +%d dB", w.enabled, w.phrase ? "computer" : "alexa",
          w.sensitivity, w.gain_db);
    return 0;
}

static int cmd_wakesrc(int argc, char **argv)
{
    static const char *const names[] = {"auto", "aec", "raw"};
    if (argc == 2) {
        for (int i = 0; i < 3; i++) {
            if (!strcmp(argv[1], names[i])) {
                audio_core_set_wake_source((audio_wake_src_t)i);
                break;
            }
        }
    }
    reply("wake input: %s  (usage: wakesrc auto|aec|raw, not saved)", names[audio_core_get_wake_source()]);
    return 0;
}

static int cmd_lang(int argc, char **argv)
{
    if (argc != 2 || (strcmp(argv[1], "ko") && strcmp(argv[1], "en"))) {
        reply("usage: lang ko|en");
        return 1;
    }
    cJSON *s = assistant_settings();
    cJSON_ReplaceItemInObjectCaseSensitive(s, "language", cJSON_CreateString(argv[1]));
    reply("lang: %s (next conversation)", esp_err_to_name(assistant_save(s)));
    cJSON_Delete(s);
    return 0;
}

/* Changes one assistant setting (same validation as the app's PUT settings/assistant) */
static int set_assistant_field(const char *field, const char *value)
{
    cJSON *s = assistant_settings();
    cJSON_ReplaceItemInObjectCaseSensitive(s, field, cJSON_CreateString(value));
    esp_err_t err = assistant_save(s);
    cJSON_Delete(s);
    reply("%s: %s (next conversation)", field, esp_err_to_name(err));
    return err != ESP_OK;
}

static int cmd_location(int argc, char **argv)
{
    if (argc < 2) {
        cJSON *s = assistant_settings();
        reply("location \"%s\"  timezone %s", cJSON_GetObjectItem(s, "location")->valuestring,
              cJSON_GetObjectItem(s, "timezone")->valuestring);
        cJSON_Delete(s);
        reply("usage: location <town, e.g. Seoul Gangnam-gu Yeoksam-dong> | location clear");
        return 0;
    }
    char text[97] = {0};
    if (strcmp(argv[1], "clear")) {
        for (int i = 1; i < argc; i++) {
            strlcat(text, argv[i], sizeof(text));
            if (i + 1 < argc) {
                strlcat(text, " ", sizeof(text));
            }
        }
    }
    return set_assistant_field("location", text);
}

static int cmd_timezone(int argc, char **argv)
{
    if (argc != 2) {
        reply("usage: timezone Asia/Seoul | UTC | America/New_York | Europe/London ...");
        return 1;
    }
    int r = set_assistant_field("timezone", argv[1]);
    if (!r) {
        time_t now = time(NULL);
        struct tm local;
        localtime_r(&now, &local);
        char buf[40];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M %Z", &local);
        reply("local time now: %s", buf);
    }
    return r;
}

static int cmd_selftest(int argc, char **argv)
{
    bool hangup = hangup_phrase_selftest();
    unsigned delegation = delegation_selftest();
    unsigned mic = mic_control_selftest();
    bool notes_logic = notes_selftest();
    bool notes_state = notes_state_selftest();
    bool settings_migration = assistant_settings_migration_selftest();
    unsigned saver = saver_voice_selftest();
    reply("hangup %s  delegation 0x%02x %s  mic 0x%02x %s  notes_logic %s  notes_state %s  "
          "settings_migration %s  saver 0x%02x %s",
          hangup ? "PASS" : "FAIL", delegation, delegation == 0x1F ? "PASS" : "FAIL", mic,
          mic == 0xFF ? "PASS" : "FAIL", notes_logic ? "PASS" : "FAIL", notes_state ? "PASS" : "FAIL",
          settings_migration ? "PASS" : "FAIL", saver, saver == 0x3F ? "PASS" : "FAIL");
    return 0;
}

static int cmd_tone(int argc, char **argv)
{
    audio_core_tone();
    reply("tone: 440 Hz 0.3 s");
    return 0;
}

static int cmd_reboot(int argc, char **argv)
{
    reply("rebooting");
    vTaskDelay(pdMS_TO_TICKS(200));
    esp_restart();
    return 0;
}

static int cmd_factory_reset(int argc, char **argv)
{
    if (argc != 2 || strcmp(argv[1], "yes")) {
        reply("usage: factory_reset yes   (erases Wi-Fi, keys and all settings)");
        return 1;
    }
    live_voice_stop();
    reply("factory_reset: %s, rebooting", esp_err_to_name(settings_factory_reset()));
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
    return 0;
}

static void register_commands(void)
{
    const esp_console_cmd_t cmds[] = {
        {.command = "wifi", .help = "Save Wi-Fi: wifi <ssid> [password]", .func = cmd_wifi},
        {.command = "key", .help = "Save OpenAI API key: key <sk-...> | key clear", .func = cmd_key},
        {.command = "provision", .help = "Mark provisioned and reboot", .func = cmd_provision},
        {.command = "status", .help = "Show device status", .func = cmd_status},
        {.command = "talk", .help = "Start a conversation", .func = cmd_talk},
        {.command = "stop", .help = "End the conversation", .func = cmd_stop},
        {.command = "say", .help = "Send text in a conversation: say <text>", .func = cmd_say},
        {.command = "volume", .help = "Get/set volume: volume [0-80]", .func = cmd_volume},
        {.command = "wake", .help = "wake [on|off] [alexa|computer] [0-100]", .func = cmd_wake},
        {.command = "mic", .help = "Mic gain: mic <0-36> [auto|noauto]", .func = cmd_mic},
        {.command = "wakesrc", .help = "Wake word input: wakesrc auto|aec|raw (test, not saved)", .func = cmd_wakesrc},
        {.command = "wakegain", .help = "Wake word input gain: wakegain <0-24 dB>", .func = cmd_wakegain},
        {.command = "lang", .help = "Assistant language: lang ko|en", .func = cmd_lang},
        {.command = "location", .help = "Home location: location Seoul Gangnam-gu Yeoksam-dong | clear", .func = cmd_location},
        {.command = "timezone", .help = "Time zone (IANA): timezone Asia/Seoul", .func = cmd_timezone},
        {.command = "selftest", .help = "Run pure-logic self tests", .func = cmd_selftest},
        {.command = "tone", .help = "Play test tone", .func = cmd_tone},
        {.command = "reboot", .help = "Restart", .func = cmd_reboot},
        {.command = "factory_reset", .help = "Erase all settings: factory_reset yes", .func = cmd_factory_reset},
    };
    for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) {
        ESP_ERROR_CHECK(esp_console_cmd_register(&cmds[i]));
    }
    esp_console_register_help_command();
}

static void console_task(void *arg)
{
    static char line[CONSOLE_LINE_MAX];
    size_t used = 0;
    reply("AI Speaker dev console. Type 'help'.");
    for (;;) {
        uint8_t c;
        if (usb_serial_jtag_read_bytes(&c, 1, portMAX_DELAY) != 1) {
            continue;
        }
        if (c == '\r' || c == '\n') {
            if (!used) {
                continue;
            }
            line[used] = '\0';
            usb_serial_jtag_write_bytes("\r\n", 2, pdMS_TO_TICKS(50));
            int ret = 0;
            esp_err_t err = esp_console_run(line, &ret);
            if (err == ESP_ERR_NOT_FOUND) {
                reply("unknown command (try 'help')");
            }
            memset(line, 0, sizeof(line));      /* so no secret is left behind */
            used = 0;
        } else if (c == 0x08 || c == 0x7F) {
            if (used) {
                used--;
                usb_serial_jtag_write_bytes("\b \b", 3, pdMS_TO_TICKS(50));
            }
        } else if (used < sizeof(line) - 1 && c >= 0x20) {
            line[used++] = (char)c;
            usb_serial_jtag_write_bytes(&c, 1, pdMS_TO_TICKS(50));
        }
    }
}

esp_err_t dev_console_start(void)
{
    usb_serial_jtag_driver_config_t usb = {.rx_buffer_size = 1024, .tx_buffer_size = 2048};
    esp_err_t err = usb_serial_jtag_driver_install(&usb);
    if (err != ESP_OK) {
        return err;
    }
    esp_console_config_t cfg = ESP_CONSOLE_CONFIG_DEFAULT();
    cfg.max_cmdline_length = CONSOLE_LINE_MAX;
    cfg.max_cmdline_args = 16;
    ESP_ERROR_CHECK(esp_console_init(&cfg));
    register_commands();
    ESP_LOGW(TAG, "developer console enabled (disable CONFIG_APP_DEV_CONSOLE for release)");
    return xTaskCreatePinnedToCoreWithCaps(console_task, "dev_console", 6144, NULL, 2, NULL, 0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) == pdPASS ? ESP_OK
                                                                                               : ESP_ERR_NO_MEM;
}

#else

esp_err_t dev_console_start(void)
{
    return ESP_OK;
}

#endif
