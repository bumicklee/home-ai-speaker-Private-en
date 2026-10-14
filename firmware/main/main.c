/**
 * @file main.c
 * @brief Boot flow and system state machine (design document Sections 2.4, 2.5, 2.15)
 *
 * Receives events (app_events), updates the LED display, and starts conversations on buttons and the wake word.
 * Lower modules don't know about main. Only main knows every module.
 */
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include "app_config.h"
#include "app_events.h"
#include "assistant.h"
#include "audio_core.h"
#include "ble_prov.h"
#include "device_api.h"
#include "board.h"
#include "dev_console.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "live_voice.h"
#include "local_api.h"
#include "media_radio.h"
#include "media_spotify.h"
#include "messenger_telegram.h"
#include "net.h"
#include "notes.h"
#include "secret_store.h"
#include "settings.h"
#include "wake.h"

static const char *TAG = "MAIN";

typedef enum {
    SYS_MODE_NORMAL,
    SYS_MODE_PROVISIONING,
    SYS_MODE_OTA,
    SYS_MODE_FACTORY_RESET,
} sys_mode_t;

static sys_mode_t s_mode = SYS_MODE_NORMAL;
static bool s_app_marked_valid;
/* Ready announcement (once per boot): wake word listening + Wi-Fi + OpenAI key → "AI 스피커가 준비되었습니다" (The AI speaker is ready) */
static bool s_wifi_ready, s_wake_ready, s_ready_announced;

/*
 * Free internal RAM when the BLE window opens (Chapter 8, Bug 1): end the conversation and suspend AEC (about 91KB).
 * While the window is open, a conversation can't start (live_voice_start refuses). The radio keeps playing.
 */
static void ble_before_open(void)
{
    if (live_voice_active()) {
        live_voice_stop();
        for (int i = 0; i < 50 && live_voice_active(); i++) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
    }
    if (audio_core_aec_suspend(true, 2000) != ESP_OK) {
        ESP_LOGW(TAG, "AEC suspend timed out");
    }
    ESP_LOGI(TAG, "BLE window: internal free %u (largest %u)",
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
}

static void ble_after_close(void)
{
    if (audio_core_aec_suspend(false, 3000) != ESP_OK) {
        ESP_LOGW(TAG, "AEC resume pending (will retry)");
    }
}

static void announce_ready_if_ready(void)
{
    settings_wake_t w;
    wake_get_config(&w);
    bool wake_ok = s_wake_ready || !w.enabled;      /* if the wake word is off, ready once Key2 can start a conversation */
    if (s_ready_announced || !s_wifi_ready || !wake_ok || s_mode != SYS_MODE_NORMAL || live_voice_active()) {
        return;
    }
    s_ready_announced = true;
    if (!secret_exists(SECRET_OPENAI_KEY)) {
        ESP_LOGI(TAG, "ready, but no OpenAI key: no announcement");
        return;
    }
    ESP_LOGI(TAG, "ready: announcing");
    audio_core_play_ready();    /* TODO(English edition): replace ready.mp3 with an English recording */
}

/* ── Time ──────────────────────────────────────────────────── */

/* Free internal RAM per step (to see where and how much is used) */
static void log_heap(const char *step)
{
    ESP_LOGI(TAG, "heap after %-12s internal %6u (largest %6u)  psram %7u", step,
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
             (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
             (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
}

/* Features conversation works without: on failure, disable just that feature and keep booting (prevents the reboot loop) */
static void optional_init(const char *name, esp_err_t err)
{
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "%s init failed: %s (feature disabled)", name, esp_err_to_name(err));
    }
    log_heap(name);
}

static void restore_time_from_rtc(void)
{
    struct tm utc;
    if (!board_rtc_read(&utc)) {
        ESP_LOGI(TAG, "RTC not set; waiting for SNTP");
        return;
    }
    /* the RTC is UTC. Compute in UTC even if a local time zone (assistant's timezone) is set */
    char *saved = getenv("TZ") ? strdup(getenv("TZ")) : NULL;
    setenv("TZ", "UTC0", 1);
    tzset();
    struct timeval tv = {.tv_sec = mktime(&utc)};
    if (saved) {
        setenv("TZ", saved, 1);
        free(saved);
    } else {
        unsetenv("TZ");
    }
    tzset();
    settimeofday(&tv, NULL);
    ESP_LOGI(TAG, "time restored from RTC");
}

static void on_time_sync(void)
{
    time_t now = time(NULL);
    struct tm utc;
    gmtime_r(&now, &utc);
    board_rtc_write(&utc);
}

/* ── Event handling ────────────────────────────────────────── */

static void change_volume(int delta)
{
    int v = audio_core_get_volume() + delta;
    v = v < 0 ? 0 : (v > APP_VOLUME_MAX ? APP_VOLUME_MAX : v);
    if (v != audio_core_get_volume()) {
        audio_core_set_volume(v);
        ESP_LOGI(TAG, "volume %d", v);
    }
}

static void factory_reset(void)
{
    s_mode = SYS_MODE_FACTORY_RESET;
    ESP_LOGW(TAG, "factory reset");
    live_voice_stop();
    wake_stop();
    radio_stop();
    settings_factory_reset();      /* phone tokens (api/phones) are in nvs too, so they're erased as well */
    radio_presets_reset();         /* reset /presets.json in storage to defaults (SYS-08) */
    vTaskDelay(pdMS_TO_TICKS(1500));    /* show the red blink briefly */
    esp_restart();
}

static void on_button(const app_button_event_t *evt)
{
    if (s_mode == SYS_MODE_FACTORY_RESET) {
        return;
    }
    switch (evt->button) {
    case APP_BUTTON_KEY1:
        change_volume(-APP_VOLUME_STEP);
        break;
    case APP_BUTTON_KEY3:
        change_volume(APP_VOLUME_STEP);
        break;
    case APP_BUTTON_KEY2:
        switch (evt->press) {
        case APP_PRESS_SHORT:
            /* Start a conversation even while music plays; duck the music (Q5, user decision 2026-10-03).
             * In Saver mode while it's speaking, stop only the playback and keep listening (conversation doesn't end; barge-in,
             * docs/design-voice-saver-mode.md 11.5). Otherwise end the conversation as before */
            if (live_voice_active()) {
                live_voice_barge_in();
            } else if (s_mode == SYS_MODE_NORMAL) {
                live_voice_start();
            }
            break;
        case APP_PRESS_HOLD_3S:
            led_ring_set_key2_stage(LED_KEY2_BLE);
            break;
        case APP_PRESS_HOLD_7S:
            led_ring_set_key2_stage(LED_KEY2_WARN);
            break;
        case APP_PRESS_BLE_WINDOW:
            led_ring_set_key2_stage(LED_KEY2_NONE);
            ble_prov_open_window();
            break;
        case APP_PRESS_CANCEL:
            led_ring_set_key2_stage(LED_KEY2_NONE);
            break;
        case APP_PRESS_FACTORY:
            led_ring_set_key2_stage(LED_KEY2_FACTORY);
            factory_reset();
            break;
        default:
            break;
        }
        break;
    }
}

/*
 * Auto-read new Telegram messages (TLG-10). If the app's "새 메시지 바로 읽어 주기" (read new messages right away) is on and it isn't quiet hours,
 * open a short conversation and read them. If a conversation, Korean lesson, or BLE window blocks it, retry every 5 s.
 * Messages during quiet hours are announced only with the chime and purple LED, as before.
 */
static bool s_tg_pending;
static esp_timer_handle_t s_tg_retry;
static const char *s_tg_wait_reason;   /* so the same reason isn't logged every 5 s */

/* when it has to wait, retry after 5 s (timer task → handed to the event loop so it runs on the same task) */
static void tg_retry_cb(void *arg)
{
    int unread = telegram_unread();
    app_events_post(APP_EVT_TG_MESSAGE, &unread, sizeof(unread), 0);
}

static void tg_retry_later(const char *reason)
{
    if (reason != s_tg_wait_reason) {
        s_tg_wait_reason = reason;
        ESP_LOGI(TAG, "telegram: auto-read waiting (%s)", reason);
    }
    if (!s_tg_retry) {
        const esp_timer_create_args_t args = {.callback = tg_retry_cb, .name = "tg_retry"};
        if (esp_timer_create(&args, &s_tg_retry) != ESP_OK) {
            return;
        }
    }
    if (!esp_timer_is_active(s_tg_retry)) {
        esp_timer_start_once(s_tg_retry, 5 * 1000 * 1000);
    }
}

static void auto_read_telegram(void)
{
    if (!s_tg_pending) {
        return;
    }
    int unread = telegram_unread();
    if (unread <= 0 || !telegram_auto_read_now()) {
        s_tg_pending = false;   /* already read, turned off, or quiet hours (reason in the TG_STORE log) */
        return;
    }
    if (!secret_exists(SECRET_OPENAI_KEY)) {
        s_tg_pending = false;
        ESP_LOGW(TAG, "telegram: auto-read needs the OpenAI API key");
        return;
    }
    if (live_voice_active()) {
        tg_retry_later("conversation in progress");
        return;
    }
    if (ble_prov_is_open() || audio_core_aec_suspended()) {
        tg_retry_later("BLE window open");
        return;
    }
    if (wake_is_testing()) {
        tg_retry_later("wake word test");
        return;
    }
    esp_err_t err = assistant_announce_telegram(unread);
    if (err == ESP_OK) {
        s_tg_pending = false;
        s_tg_wait_reason = NULL;
        ESP_LOGI(TAG, "telegram: auto-read %d", unread);
    } else if (err == ESP_ERR_INVALID_STATE) {
        tg_retry_later("busy (Korean lesson or starting)");
    } else {
        s_tg_pending = false;
        ESP_LOGW(TAG, "telegram: auto-read failed: %s", esp_err_to_name(err));
    }
}

/*
 * Schedule reminders (docs/design-notes-schedule.md second edition, Section 5.4): if notes_tick() holds a batch, open a short conversation.
 * If a conversation, Korean lesson, BLE window, or wake word test blocks it, retry every 5 s like Telegram auto-read.
 * If it can't work at all because there's no internet or API key (not temporary), emergency reminder: 3 chimes + orange LED.
 * If Telegram auto-read is also waiting at the same moment, the reminder goes first (guaranteed by the call order in on_app_event).
 */
static bool s_notes_pending;
static esp_timer_handle_t s_notes_retry;
static const char *s_notes_wait_reason;

static void notes_retry_cb(void *arg)
{
    app_events_post(APP_EVT_NOTES_TICK, NULL, 0, 0);
}

static void notes_retry_later(const char *reason)
{
    if (reason != s_notes_wait_reason) {
        s_notes_wait_reason = reason;
        ESP_LOGI(TAG, "reminder: waiting (%s)", reason);
    }
    if (!s_notes_retry) {
        const esp_timer_create_args_t args = {.callback = notes_retry_cb, .name = "notes_retry"};
        if (esp_timer_create(&args, &s_notes_retry) != ESP_OK) {
            return;
        }
    }
    if (!esp_timer_is_active(s_notes_retry)) {
        esp_timer_start_once(s_notes_retry, 5 * 1000 * 1000);
    }
}

static esp_timer_handle_t s_reminder_chime_timer;
static int s_reminder_chime_left;

static void reminder_chime_cb(void *arg)
{
    audio_core_chime();
    if (--s_reminder_chime_left > 0) {
        esp_timer_start_once(s_reminder_chime_timer, 1200 * 1000);
    }
}

/* Can't open a conversation (no internet or API key): 3 chimes (spaced out with esp_timer so they don't overlap) + orange LED.
 * The notes side marks the batch missed and clears it (decision 2026-10-04: keep it simple; even if internet returns within 30 minutes, don't announce it again by voice) */
static void reminder_emergency(void)
{
    led_ring_set_reminder(true);
    if (!s_reminder_chime_timer) {
        const esp_timer_create_args_t args = {.callback = reminder_chime_cb, .name = "rem_chime"};
        esp_timer_create(&args, &s_reminder_chime_timer);
    }
    if (s_reminder_chime_timer) {
        s_reminder_chime_left = 3;
        reminder_chime_cb(NULL);       /* first one right away; the other two follow on their own 1.2 s apart */
    }
    notes_reminder_unreachable();
    ESP_LOGW(TAG, "reminder: no Wi-Fi or API key; chime + LED instead of talking");
}

static void process_reminders(void)
{
    if (!s_notes_pending) {
        return;
    }
    if (!secret_exists(SECRET_OPENAI_KEY) || !net_is_connected()) {
        reminder_emergency();
        s_notes_pending = false;
        s_notes_wait_reason = NULL;
        return;
    }
    if (live_voice_active()) {
        notes_retry_later("conversation in progress");
        return;
    }
    if (ble_prov_is_open() || audio_core_aec_suspended()) {
        notes_retry_later("BLE window open");
        return;
    }
    if (wake_is_testing()) {
        notes_retry_later("wake word test");
        return;
    }
    esp_err_t err = assistant_announce_reminders();
    if (err == ESP_OK) {
        s_notes_pending = false;
        s_notes_wait_reason = NULL;
        ESP_LOGI(TAG, "reminder: announcing");
    } else if (err == ESP_ERR_INVALID_STATE) {
        notes_retry_later("busy (Korean lesson or starting)");
    } else {
        reminder_emergency();      /* treat unexpected failures as an internet or key problem too */
        s_notes_pending = false;
        s_notes_wait_reason = NULL;
    }
}

static void on_app_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    switch ((app_event_id_t)id) {
    case APP_EVT_WIFI_UP:
        led_ring_set_wifi_connecting(false);
        s_wifi_ready = true;
        announce_ready_if_ready();
        /* new firmware from OTA: if audio and Wi-Fi came up, confirm it as valid (Section 2.18) */
        if (!s_app_marked_valid) {
            s_app_marked_valid = true;
            esp_ota_mark_app_valid_cancel_rollback();
        }
        break;
    case APP_EVT_WAKE_READY:
        s_wake_ready = true;
        announce_ready_if_ready();
        break;
    case APP_EVT_WIFI_DOWN:
        led_ring_set_wifi_connecting(true);
        break;
    case APP_EVT_PROV_START:
        led_ring_set_ble_window(true);
        break;
    case APP_EVT_PROV_DONE:
        led_ring_set_ble_window(false);
        break;
    case APP_EVT_WAKE_DETECTED:
        led_ring_flash_wake();
        audio_core_music_duck(true);    /* duck right away so speech is easier to recognize (Section 2.5) */
        if (s_mode == SYS_MODE_NORMAL && !live_voice_active()) {
            live_voice_start();
        }
        break;
    case APP_EVT_VOICE_STATE: {
        voice_state_t v = *(const voice_state_t *)data;
        led_ring_set_voice(v);
        if (v != VOICE_IDLE) {
            led_ring_set_reminder(false);   /* the next conversation started: turn off the emergency reminder display */
        }
        /* duck music during a conversation, restore it afterwards (the Spotify pause option is Phase 5) */
        audio_core_music_duck(v != VOICE_IDLE);
        /* pause Telegram polling during a conversation (TLG-12, saves one TLS connection) */
        telegram_pause(v != VOICE_IDLE);
        if (v == VOICE_IDLE && radio_is_active()) {
            net_set_power_save(false);  /* live_voice turned power save on at the end of the conversation, but music is still playing */
        }
        if (v == VOICE_IDLE) {
            process_reminders();        /* schedule reminders first (retry the one that was waiting) */
            auto_read_telegram();       /* messages that arrived during the conversation and were deferred */
        }
        break;
    }
    case APP_EVT_NOTES_TICK:
        notes_tick();
        if (notes_reminder_pending()) {
            s_notes_pending = true;
        }
        process_reminders();
        break;
    case APP_EVT_TG_MESSAGE: {
        static int last_unread;
        int unread = *(const int *)data;
        led_ring_set_unread(unread > 0);
        /* new message: chime. Skipped during a conversation (TLG-07) */
        if (unread > last_unread && !live_voice_active()) {
            audio_core_chime();
        }
        if (unread > last_unread) {
            s_tg_pending = true;
            s_tg_wait_reason = NULL;
        }
        auto_read_telegram();   /* new message, or retry of one that was waiting (tg_retry_cb) */
        last_unread = unread;
        break;
    }
    case APP_EVT_MEDIA_STATE:
        led_ring_set_media(((const app_media_event_t *)data)->state);
        /* turn off Wi-Fi power save while music plays (Section 2.19) */
        net_set_power_save(((const app_media_event_t *)data)->state == MEDIA_STOPPED ||
                           ((const app_media_event_t *)data)->state == MEDIA_PAUSED);
        break;
    case APP_EVT_BUTTON:
        on_button(data);
        break;
    case APP_EVT_ERROR:
        if (*(const app_error_t *)data != APP_ERR_NONE) {
            led_ring_show_error();
        }
        break;
    default:
        break;
    }
}

/* the wake word standby display follows the wake module state every 0.5 s */
static void wake_led_timer(void *arg)
{
    led_ring_set_wake_armed(wake_is_listening());
}

static void start_led_timer(void)
{
    const esp_timer_create_args_t args = {.callback = wake_led_timer, .name = "wake_led"};
    esp_timer_handle_t timer;
    if (esp_timer_create(&args, &timer) == ESP_OK) {
        esp_timer_start_periodic(timer, 500 * 1000);
    }
}

/* every 30 s, tell the notes module to check what to announce and what was missed (on the event loop, no new task, Section 2.3) */
static void notes_tick_cb(void *arg)
{
    app_events_post(APP_EVT_NOTES_TICK, NULL, 0, 0);
}

static void start_notes_timer(void)
{
    const esp_timer_create_args_t args = {.callback = notes_tick_cb, .name = "notes_tick"};
    esp_timer_handle_t timer;
    if (esp_timer_create(&args, &timer) == ESP_OK) {
        esp_timer_start_periodic(timer, 30 * 1000 * 1000);
    }
}

/* ── Boot ──────────────────────────────────────────────────── */

static void start_services(void)
{
    led_ring_set_wifi_connecting(true);
    if (net_start() != ESP_OK) {
        ESP_LOGW(TAG, "Wi-Fi not started");
    }
    net_mdns_start();
    optional_init("local_api", local_api_start());
    ESP_ERROR_CHECK(wake_start());
    ESP_ERROR_CHECK(telegram_start());      /* Phase 4 */
}

void app_main(void)
{
    ESP_LOGI(TAG, "AI Speaker %s (protocol %d)", APP_FW_VERSION, APP_PROTOCOL_VERSION);

    log_heap("start");
    ESP_ERROR_CHECK(settings_init());       /* nvs_flash_init family only here */
    ESP_ERROR_CHECK(app_events_init());
    ESP_ERROR_CHECK(board_init());          /* the LED boot indication comes on first */
    led_ring_set_brightness(settings_get_led_brightness());
    restore_time_from_rtc();
    ESP_ERROR_CHECK(audio_core_init());     /* I2S → output silence → amp after 50ms */
    log_heap("audio");

    net_set_time_sync_cb(on_time_sync);
    ESP_ERROR_CHECK(net_init());
    log_heap("net");
    ESP_ERROR_CHECK(wake_init());
    log_heap("wake");
    ESP_ERROR_CHECK(live_voice_init());
    log_heap("live_voice");
    ESP_ERROR_CHECK(assistant_init());
    log_heap("assistant");
    optional_init("radio", media_radio_init());
    optional_init("spotify", media_spotify_init());
    optional_init("telegram", telegram_init());
    optional_init("notes", notes_init());   /* media_radio_init() ran first, so /storage is already mounted */
    ESP_ERROR_CHECK(phones_init());
    optional_init("ble", ble_prov_init());
    ble_prov_set_memory_hooks(ble_before_open, ble_after_close);
    ESP_ERROR_CHECK(board_buttons_start());

    /* start event handling only after driver init and applying NVS settings are done (Section 2.19) */
    ESP_ERROR_CHECK(app_events_subscribe(ESP_EVENT_ANY_ID, on_app_event, NULL));
    start_led_timer();
    start_notes_timer();
    if (dev_console_start() != ESP_OK) {
        ESP_LOGW(TAG, "dev console unavailable");
    }
    led_ring_set_booting(false);
    app_events_set_ready();
    audio_core_play_startup();

    /* a Wi-Fi failure alone doesn't enter provisioning mode. Hold Key2 for 3 s to open the BLE window */
    if (!settings_is_provisioned()) {
        s_mode = SYS_MODE_PROVISIONING;
        ESP_LOGI(TAG, "not provisioned: BLE provisioning mode (or use the dev console)");
        ESP_ERROR_CHECK(ble_prov_open_unlimited());
        return;
    }

    start_services();
    log_heap("boot done");
}
