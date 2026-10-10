/**
 * @file app_events.h
 * @brief App event bus built on esp_event (design document Section 2.3)
 *
 * Lower modules don't include upper module headers; they notify through this bus.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

ESP_EVENT_DECLARE_BASE(APP_EVENT);

typedef enum {
    APP_EVT_WIFI_UP,
    APP_EVT_WIFI_DOWN,
    APP_EVT_PROV_START,
    APP_EVT_PROV_DONE,
    APP_EVT_WAKE_DETECTED,
    APP_EVT_VOICE_STATE,        /* data: voice_state_t */
    APP_EVT_MEDIA_STATE,        /* data: media_state_t + now playing */
    APP_EVT_TG_MESSAGE,         /* data: int unread count (0 means all read) */
    APP_EVT_TG_PAIRED,          /* data: int64_t chat_id */
    APP_EVT_OTA,                /* data: stage + progress */
    APP_EVT_WAKE_TEST,          /* data: detection count */
    APP_EVT_BUTTON,             /* data: app_button_event_t */
    APP_EVT_SETTINGS_CHANGED,   /* data: setting key ID */
    APP_EVT_ERROR,              /* data: error code */
    APP_EVT_TG_STATUS,          /* data: tg_state_t (int) */
    APP_EVT_WAKE_READY,         /* wake word model loaded and listening (each time the model is reopened) */
    APP_EVT_LESSON,             /* English lesson state or summary changed (read the content with lesson_json) */
    APP_EVT_NOTES,              /* notes or schedule changed (by voice, app, or reminder). data: uint32_t current rev */
    APP_EVT_NOTES_TICK,         /* every 30 s: check what to announce and what was missed (notes_tick). No data */
    APP_EVT_REMINDER,           /* schedule reminder result. data: app_notes_reminder_t */
} app_event_id_t;

/* ── Event data types (shared by several modules) ───────────────── */

typedef enum {
    VOICE_IDLE,
    VOICE_WAKE_ACK,
    VOICE_CONNECTING,
    VOICE_LIVE,
    VOICE_CLOSING,
} voice_state_t;

typedef enum {
    APP_BUTTON_KEY1,    /* volume down */
    APP_BUTTON_KEY2,    /* system button */
    APP_BUTTON_KEY3,    /* volume up */
} app_button_t;

typedef enum {
    APP_PRESS_SHORT,        /* short press and release (Key2: under 3 s) */
    APP_PRESS_REPEAT,       /* repeats while Key1 or Key3 is held */
    APP_PRESS_HOLD_3S,      /* Key2 reached 3 s (still held) */
    APP_PRESS_HOLD_7S,      /* Key2 reached 7 s (warning) */
    APP_PRESS_BLE_WINDOW,   /* Key2 released between 3 and 7 s */
    APP_PRESS_CANCEL,       /* Key2 released between 7 and 10 s */
    APP_PRESS_FACTORY,      /* Key2 reached 10 s: factory reset right away */
} app_press_t;

typedef struct {
    app_button_t button;
    app_press_t press;
} app_button_event_t;

/* APP_EVT_MEDIA_STATE data */
typedef enum {
    MEDIA_SOURCE_NONE,
    MEDIA_SOURCE_RADIO,
    MEDIA_SOURCE_SPOTIFY,
} media_source_t;

typedef enum {
    MEDIA_STOPPED,
    MEDIA_BUFFERING,
    MEDIA_PLAYING,
    MEDIA_PAUSED,
} media_play_state_t;

typedef struct {
    uint8_t source;     /* media_source_t */
    uint8_t state;      /* media_play_state_t */
} app_media_event_t;

/* APP_EVT_REMINDER data. status: 0 sent, 1 acked, 2 no_answer, 3 missed (same order as alert_status_t in notes.c) */
typedef struct {
    char id[11];        /* "n_" + 8 hex digits + NUL */
    uint8_t status;
} app_notes_reminder_t;

/* APP_EVT_SETTINGS_CHANGED data */
typedef enum {
    APP_SETTING_VOLUME,
    APP_SETTING_AUDIO,
    APP_SETTING_WAKE,
    APP_SETTING_ASSISTANT,
    APP_SETTING_LED,
    APP_SETTING_SECRETS,
    APP_SETTING_PHONES,
    APP_SETTING_TELEGRAM,
} app_setting_t;

/* APP_EVT_ERROR data. Only fixed codes are sent (no external response bodies) */
typedef enum {
    APP_ERR_NONE,
    APP_ERR_NO_API_KEY,
    APP_ERR_WIFI,
    APP_ERR_CLOCK,
    APP_ERR_VOICE_CONNECT,
    APP_ERR_VOICE_REJECTED,
    APP_ERR_VOICE_DROPPED,
    APP_ERR_VOICE_INTERNAL,
    APP_ERR_RADIO_UNAVAILABLE,  /* 5 failed reconnects or an unsupported format */
    APP_ERR_AI_UNAVAILABLE,     /* the selected AI (provider) isn't available yet in this firmware stage (docs/design-voice-saver-mode.md) */
} app_error_t;

/** Creates the dedicated event loop. Call once, before any other module. */
esp_err_t app_events_init(void);

esp_err_t app_events_post(app_event_id_t id, const void *data, size_t len, uint32_t timeout_ms);
esp_err_t app_events_subscribe(app_event_id_t id, esp_event_handler_t handler, void *arg);

/**
 * Signals that driver initialization and applying NVS settings are done (the "init done" bit, Section 2.19).
 * Until this bit is set, the event-handling task does not start working.
 */
void app_events_set_ready(void);
bool app_events_wait_ready(uint32_t timeout_ms);

#ifdef __cplusplus
}
#endif
