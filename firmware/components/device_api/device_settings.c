/*
 * Settings group JSON ↔ device settings (design document Section 2.14 /api/v1/settings/{group}, BLE settings.get/set).
 * Partial update: only the keys in the request change. If any one of them is wrong, nothing changes.
 */
#include "device_api.h"

#include <string.h>
#include "app_config.h"
#include "app_events.h"
#include "assistant.h"
#include "audio_core.h"
#include "board.h"
#include "mic_control.h"
#include "secret_store.h"
#include "settings.h"
#include "wake.h"

static void notify(app_setting_t key)
{
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
}

/* If the integer value is present, check its range and put it in out. If absent, leave out as is. Wrong type or range → false */
static bool take_int(const cJSON *obj, const char *key, int min, int max, int *out)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!v) {
        return true;
    }
    if (!cJSON_IsNumber(v) || v->valuedouble != v->valueint || v->valueint < min || v->valueint > max) {
        return false;
    }
    *out = v->valueint;
    return true;
}

static bool take_bool(const cJSON *obj, const char *key, bool *out)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!v) {
        return true;
    }
    if (!cJSON_IsBool(v)) {
        return false;
    }
    *out = cJSON_IsTrue(v);
    return true;
}

/* Whether only allowed keys are present */
static bool only_keys(const cJSON *obj, const char *const *keys, size_t n)
{
    if (!cJSON_IsObject(obj)) {
        return false;
    }
    const cJSON *item;
    cJSON_ArrayForEach(item, obj) {
        bool known = false;
        for (size_t i = 0; i < n && !known; i++) {
            known = !strcmp(item->string, keys[i]);
        }
        if (!known) {
            return false;
        }
    }
    return true;
}

/* ── audio ────────────────────────────────────────────────── */

static const char *const AUDIO_KEYS[] = {"volume", "mic_gain", "auto_gain", "duck_db", "spotify_pause_on_voice"};

static cJSON *audio_get(void)
{
    settings_audio_t a;
    settings_get_audio(&a);
    cJSON *j = cJSON_CreateObject();
    cJSON_AddNumberToObject(j, "volume", audio_core_get_volume());
    cJSON_AddNumberToObject(j, "mic_gain", mic_gain());
    cJSON_AddBoolToObject(j, "auto_gain", mic_auto_gain());
    cJSON_AddNumberToObject(j, "duck_db", a.duck_db);
    cJSON_AddBoolToObject(j, "spotify_pause_on_voice", a.sp_pause_voice);
    return j;
}

static esp_err_t audio_set(const cJSON *v)
{
    settings_audio_t a;
    settings_get_audio(&a);
    int volume = audio_core_get_volume(), gain = mic_gain();
    bool automatic = mic_auto_gain();
    if (!only_keys(v, AUDIO_KEYS, 5) || !take_int(v, "volume", 0, APP_VOLUME_MAX, &volume) ||
        !take_int(v, "mic_gain", 0, 36, &gain) || !take_bool(v, "auto_gain", &automatic) ||
        !take_int(v, "duck_db", 0, 40, &a.duck_db) || !take_bool(v, "spotify_pause_on_voice", &a.sp_pause_voice)) {
        return ESP_ERR_INVALID_ARG;
    }
    /* Save the ducking and Spotify values first; the volume and mic apply functions each save their own */
    a.volume = audio_core_get_volume();
    a.mic_gain = mic_gain();
    a.auto_gain = mic_auto_gain();
    esp_err_t err = settings_set_audio(&a);
    if (err == ESP_OK && volume != audio_core_get_volume()) {
        err = audio_core_set_volume(volume);
    }
    if (err == ESP_OK && (gain != mic_gain() || automatic != mic_auto_gain())) {
        err = mic_set(gain, automatic, true);
    }
    if (err == ESP_OK) {
        notify(APP_SETTING_AUDIO);
    }
    return err;
}

/* ── wake ─────────────────────────────────────────────────── */

static const char *const WAKE_KEYS[] = {"enabled", "phrase", "sensitivity", "gain_db"};

static cJSON *wake_get(void)
{
    settings_wake_t w;
    wake_get_config(&w);
    cJSON *j = cJSON_CreateObject();
    cJSON_AddBoolToObject(j, "enabled", w.enabled);
    cJSON_AddNumberToObject(j, "phrase", w.phrase);     /* 0 Alexa, 1 Computer */
    cJSON_AddNumberToObject(j, "sensitivity", w.sensitivity);
    cJSON_AddNumberToObject(j, "gain_db", w.gain_db);
    return j;
}

static esp_err_t wake_set(const cJSON *v)
{
    settings_wake_t w;
    wake_get_config(&w);
    int phrase = w.phrase, sensitivity = w.sensitivity, gain = w.gain_db;
    if (!only_keys(v, WAKE_KEYS, 4) || !take_bool(v, "enabled", &w.enabled) || !take_int(v, "phrase", 0, 1, &phrase) ||
        !take_int(v, "sensitivity", 0, 100, &sensitivity) || !take_int(v, "gain_db", 0, 24, &gain)) {
        return ESP_ERR_INVALID_ARG;
    }
    w.phrase = phrase;
    w.sensitivity = sensitivity;
    w.gain_db = gain;
    esp_err_t err = wake_set_config(&w);
    if (err == ESP_OK) {
        notify(APP_SETTING_WAKE);
    }
    return err;
}

/* ── assistant ────────────────────────────────────────────── */

static esp_err_t assistant_set(const cJSON *v)
{
    if (!cJSON_IsObject(v)) {
        return ESP_ERR_INVALID_ARG;
    }
    /* Overwrite the current settings with the request values, then assistant_save validates the whole set (an unknown key is rejected by the key count) */
    cJSON *merged = assistant_settings();
    if (!merged) {
        return ESP_ERR_NO_MEM;
    }
    const cJSON *item;
    cJSON_ArrayForEach(item, v) {
        cJSON *copy = cJSON_Duplicate(item, true);
        if (!copy) {
            cJSON_Delete(merged);
            return ESP_ERR_NO_MEM;
        }
        if (cJSON_HasObjectItem(merged, item->string)) {
            cJSON_ReplaceItemInObjectCaseSensitive(merged, item->string, copy);
        } else {
            cJSON_AddItemToObject(merged, item->string, copy);
        }
    }
    /*
     * Key check (docs/design-voice-saver-mode.md 11.1): a request that switches ai_provider "in this request" to a provider
     * with no key is refused. The app blocks it on screen, but the speaker blocks it once more. LAN 409 NO_API_KEY, BLE
     * {"ok":false,"error":"NO_API_KEY"} (local_api.c put_settings and ble_cmd.c err_code turn
     * ESP_ERR_NOT_ALLOWED into NO_API_KEY). A request that does not touch ai_provider (renaming, etc.) is not
     * blocked here even if that key was deleted later; that case is blocked when a conversation starts (live_voice_start).
     */
    if (cJSON_HasObjectItem(v, "ai_provider")) {
        const cJSON *provider = cJSON_GetObjectItemCaseSensitive(merged, "ai_provider");
        bool gemini = cJSON_IsString(provider) && !strcmp(provider->valuestring, "gemini");
        if (!secret_exists(gemini ? SECRET_GEMINI_KEY : SECRET_OPENAI_KEY)) {
            cJSON_Delete(merged);
            return ESP_ERR_NOT_ALLOWED;
        }
    }
    esp_err_t err = assistant_save(merged);
    cJSON_Delete(merged);
    if (err == ESP_OK) {
        notify(APP_SETTING_ASSISTANT);
    }
    return err;
}

/* ── led ──────────────────────────────────────────────────── */

static const char *const LED_KEYS[] = {"brightness"};

static cJSON *led_get(void)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddNumberToObject(j, "brightness", settings_get_led_brightness());
    return j;
}

static esp_err_t led_set(const cJSON *v)
{
    int brightness = settings_get_led_brightness();
    if (!only_keys(v, LED_KEYS, 1) || !take_int(v, "brightness", 0, 100, &brightness)) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_err_t err = settings_set_led_brightness(brightness);
    if (err == ESP_OK) {
        led_ring_set_brightness(brightness);
        notify(APP_SETTING_LED);
    }
    return err;
}

/* ── Public API ───────────────────────────────────────────── */

cJSON *device_settings_get(const char *group)
{
    if (!group) {
        return NULL;
    }
    if (!strcmp(group, "audio")) {
        return audio_get();
    }
    if (!strcmp(group, "wake")) {
        return wake_get();
    }
    if (!strcmp(group, "assistant")) {
        return assistant_settings();
    }
    if (!strcmp(group, "led")) {
        return led_get();
    }
    return NULL;
}

esp_err_t device_settings_set(const char *group, const cJSON *value)
{
    if (!group) {
        return ESP_ERR_NOT_FOUND;
    }
    if (!strcmp(group, "audio")) {
        return audio_set(value);
    }
    if (!strcmp(group, "wake")) {
        return wake_set(value);
    }
    if (!strcmp(group, "assistant")) {
        return assistant_set(value);
    }
    if (!strcmp(group, "led")) {
        return led_set(value);
    }
    return ESP_ERR_NOT_FOUND;
}
