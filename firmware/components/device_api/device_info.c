/*
 * Device info (BLE device.info) and status (LAN /status). For secrets, only whether each one is saved.
 */
#include "device_api.h"

#include <stdio.h>
#include <string.h>
#include "app_config.h"
#include "assistant.h"
#include "audio_core.h"
#include "esp_app_desc.h"
#include "esp_heap_caps.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "live_voice.h"
#include "media_radio.h"
#include "messenger_telegram.h"
#include "media_spotify.h"
#include "net.h"
#include "settings.h"

static const struct {
    const char *name;
    secret_id_t id;
} WRITABLE_SECRETS[] = {
    {"openai_key", SECRET_OPENAI_KEY},
    {"tg_bot_token", SECRET_TG_BOT_TOKEN},
    {"stock_key", SECRET_STOCK_KEY},
    {"gemini_key", SECRET_GEMINI_KEY},   /* docs/design-voice-saver-mode.md 11.2 */
};

bool device_secret_from_name(const char *name, secret_id_t *out)
{
    for (size_t i = 0; name && i < sizeof(WRITABLE_SECRETS) / sizeof(WRITABLE_SECRETS[0]); i++) {
        if (!strcmp(name, WRITABLE_SECRETS[i].name)) {
            *out = WRITABLE_SECRETS[i].id;
            return true;
        }
    }
    return false;
}

void device_mac_string(char out[13])
{
    uint8_t mac[6] = {0};
    net_get_sta_mac(mac);
    snprintf(out, 13, "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

cJSON *device_secrets_state(void)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddBoolToObject(j, "openai_key", secret_exists(SECRET_OPENAI_KEY));
    cJSON_AddBoolToObject(j, "tg_bot_token", secret_exists(SECRET_TG_BOT_TOKEN));
    cJSON_AddBoolToObject(j, "spotify", secret_exists(SECRET_SP_REFRESH));
    cJSON_AddBoolToObject(j, "stock_key", secret_exists(SECRET_STOCK_KEY));
    cJSON_AddBoolToObject(j, "gemini_key", secret_exists(SECRET_GEMINI_KEY));
    return j;
}

/* GET /status.ai and BLE device.info.ai (docs/design-voice-saver-mode.md 11.4 + coordinator request: first-time setup uses BLE only) */
static cJSON *device_ai_state(void)
{
    cJSON *s = assistant_settings();
    const cJSON *provider = cJSON_GetObjectItemCaseSensitive(s, "ai_provider");
    const char *p = cJSON_IsString(provider) && !strcmp(provider->valuestring, "gemini") ? "gemini" : "openai";
    const cJSON *mode = cJSON_GetObjectItemCaseSensitive(s, !strcmp(p, "gemini") ? "mode_gemini" : "mode_openai");
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "provider", p);
    cJSON_AddStringToObject(j, "mode", cJSON_IsString(mode) && !strcmp(mode->valuestring, "saver") ? "saver" : "live");
    /* The combinations this firmware actually implements (stage 3: Gemini Live added, table in Section 11.4) */
    static const char *const AVAILABLE[] = {"openai.live", "openai.saver", "gemini.saver", "gemini.live"};
    cJSON_AddItemToObject(j, "available", cJSON_CreateStringArray(AVAILABLE, 4));
    cJSON_Delete(s);
    return j;
}

cJSON *device_info(void)
{
    char mac[13];
    device_mac_string(mac);
    cJSON *j = cJSON_CreateObject();
    cJSON_AddNumberToObject(j, "protocol_version", APP_PROTOCOL_VERSION);
    cJSON_AddStringToObject(j, "fw", APP_FW_VERSION);
    cJSON_AddStringToObject(j, "mac", mac);
    cJSON_AddBoolToObject(j, "provisioned", settings_is_provisioned());
    cJSON_AddBoolToObject(j, "wifi_connected", net_is_connected());
    cJSON_AddItemToObject(j, "secrets", device_secrets_state());
    /* First-time setup runs before LAN is up (BLE only), so "available" must go here too; that is how the app locks Gemini out at stage 1 */
    cJSON_AddItemToObject(j, "ai", device_ai_state());
    return j;
}

static const char *voice_state_name(voice_state_t s)
{
    switch (s) {
    case VOICE_WAKE_ACK: return "wake_ack";
    case VOICE_CONNECTING: return "connecting";
    case VOICE_LIVE: return "live";
    case VOICE_CLOSING: return "closing";
    default: return "idle";
    }
}

cJSON *device_status(void)
{
    const esp_app_desc_t *app = esp_app_get_description();
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "fw", APP_FW_VERSION);
    char build[32];
    snprintf(build, sizeof(build), "%s %s", app->date, app->time);
    cJSON_AddStringToObject(j, "build_date", build);
    cJSON_AddNumberToObject(j, "protocol_version", APP_PROTOCOL_VERSION);
    cJSON_AddNumberToObject(j, "uptime_s", (double)(esp_timer_get_time() / 1000000));
    cJSON_AddNumberToObject(j, "reset_reason", esp_reset_reason());
    wifi_ap_record_t ap;
    if (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) {
        cJSON_AddNumberToObject(j, "wifi_rssi", ap.rssi);
    } else {
        cJSON_AddNullToObject(j, "wifi_rssi");
    }
    cJSON_AddNumberToObject(j, "heap_internal_free", heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
    cJSON_AddNumberToObject(j, "heap_internal_min", heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
    cJSON_AddNumberToObject(j, "psram_free", heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    cJSON_AddStringToObject(j, "voice_state", voice_state_name(live_voice_state()));
    cJSON_AddItemToObject(j, "media", radio_now_json());   /* Spotify is merged in Phase 5 */
    /* Telegram and Spotify are filled in during Phases 4–5 */
    cJSON_AddNumberToObject(j, "volume", audio_core_get_volume());
    cJSON_AddItemToObject(j, "secrets", device_secrets_state());
    cJSON_AddItemToObject(j, "ai", device_ai_state());
    cJSON *tg = cJSON_AddObjectToObject(j, "telegram");
    cJSON_AddStringToObject(tg, "state", telegram_state_name(telegram_state()));
    cJSON_AddNumberToObject(tg, "unread", telegram_unread());
    cJSON_AddStringToObject(j, "spotify_state", spotify_state_name(spotify_linked() ? spotify_state() : SPOTIFY_OFF));
    /* failures (the last 5 failures) and task_stack_min are added once sys/fail_log is implemented */
    cJSON_AddArrayToObject(j, "failures");
    return j;
}
