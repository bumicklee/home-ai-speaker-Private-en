#include "settings.h"

#include <string.h>
#include "app_config.h"
#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "SETTINGS";

static esp_err_t init_partition(const char *label)
{
    esp_err_t err = nvs_flash_init_partition(label);
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "%s: %s, erasing", label, esp_err_to_name(err));
        ESP_ERROR_CHECK(nvs_flash_erase_partition(label));
        err = nvs_flash_init_partition(label);
    }
    return err;
}

esp_err_t settings_init(void)
{
    esp_err_t err = init_partition(NVS_DEFAULT_PART_NAME);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nvs init failed: %s", esp_err_to_name(err));
        return err;
    }
    err = init_partition(APP_PART_SECRETS);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "secrets init failed: %s", esp_err_to_name(err));
    }
    return err;
}

/* ── Common helpers ───────────────────────────────────────── */

static uint8_t get_u8(const char *ns, const char *key, uint8_t def, uint8_t max)
{
    nvs_handle_t h;
    uint8_t v = def;
    if (nvs_open(ns, NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_u8(h, key, &v) != ESP_OK || v > max) {
            v = def;
        }
        nvs_close(h);
    }
    return v;
}

static esp_err_t set_u8s(const char *ns, const char *const *keys, const uint8_t *values, size_t n)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(ns, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    for (size_t i = 0; i < n && err == ESP_OK; i++) {
        err = nvs_set_u8(h, keys[i], values[i]);
    }
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    return err;
}

/* ── Provisioning ─────────────────────────────────────────── */

bool settings_is_provisioned(void)
{
    return get_u8("prov", "provisioned", 0, 1) == 1;
}

esp_err_t settings_set_provisioned(bool provisioned)
{
    static const char *const keys[] = {"provisioned"};
    const uint8_t values[] = {provisioned ? 1 : 0};
    return set_u8s("prov", keys, values, 1);
}

/* ── Wi-Fi ────────────────────────────────────────────────── */

bool settings_has_wifi(void)
{
    char ssid[33], password[65];
    bool ok = settings_get_wifi(ssid, password) == ESP_OK;
    memset(password, 0, sizeof(password));
    return ok;
}

esp_err_t settings_get_wifi(char ssid[33], char password[65])
{
    nvs_handle_t h;
    esp_err_t err = nvs_open("wifi", NVS_READONLY, &h);
    if (err != ESP_OK) {
        return err;
    }
    size_t len = 33;
    err = nvs_get_str(h, "ssid", ssid, &len);
    if (err == ESP_OK && len <= 1) {
        err = ESP_ERR_NOT_FOUND;
    }
    if (err == ESP_OK) {
        len = 65;
        err = nvs_get_str(h, "password", password, &len);
        if (err == ESP_ERR_NVS_NOT_FOUND) {     /* open network */
            password[0] = '\0';
            err = ESP_OK;
        }
    }
    nvs_close(h);
    return err;
}

esp_err_t settings_set_wifi(const char *ssid, const char *password)
{
    if (!ssid || !ssid[0] || strlen(ssid) > 32 || !password || strlen(password) > 64) {
        return ESP_ERR_INVALID_ARG;
    }
    nvs_handle_t h;
    esp_err_t err = nvs_open("wifi", NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_str(h, "ssid", ssid);
    if (err == ESP_OK) {
        err = nvs_set_str(h, "password", password);
    }
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    /* log only the password length (Section 2.2) */
    ESP_LOGI(TAG, "wifi saved: ssid_len=%u pass_len=%u: %s",
             (unsigned)strlen(ssid), (unsigned)strlen(password), esp_err_to_name(err));
    return err;
}

/* ── Audio ────────────────────────────────────────────────── */

void settings_get_audio(settings_audio_t *out)
{
    out->volume = get_u8("audio", "volume", 40, APP_VOLUME_MAX);
    /* default 30dB: on the real board, 24dB gave speech only 2% of full scale (-34 dBFS) (Chapter 6, Bug 4) */
    out->mic_gain = get_u8("audio", "mic_gain", 36, 36);
    out->auto_gain = get_u8("audio", "auto_gain", 0, 1);
    out->duck_db = get_u8("audio", "duck_db", 20, 40);
    out->sp_pause_voice = get_u8("audio", "sp_pause_voice", 0, 1);
}

esp_err_t settings_set_audio(const settings_audio_t *in)
{
    if (in->volume < 0 || in->volume > APP_VOLUME_MAX || in->mic_gain < 0 || in->mic_gain > 36 ||
        in->duck_db < 0 || in->duck_db > 40) {
        return ESP_ERR_INVALID_ARG;
    }
    static const char *const keys[] = {"volume", "mic_gain", "auto_gain", "duck_db", "sp_pause_voice"};
    const uint8_t values[] = {in->volume, in->mic_gain, in->auto_gain, in->duck_db, in->sp_pause_voice};
    return set_u8s("audio", keys, values, 5);
}

/* ── Wake word ────────────────────────────────────────────── */

void settings_get_wake(settings_wake_t *out)
{
    out->enabled = get_u8("wake", "enabled", 1, 1);
    /* default Computer, sensitivity 80: on the real board, Jarvis was barely detected even at 80 (Chapter 6, Section 6.2) */
    out->phrase = get_u8("wake", "phrase", 1, 1);
    out->sensitivity = get_u8("wake", "sensitivity", 80, 100);
    out->gain_db = get_u8("wake", "gain_db", 12, 24);
}

esp_err_t settings_set_wake(const settings_wake_t *in)
{
    if (in->phrase > 1 || in->sensitivity > 100 || in->gain_db > 24) {
        return ESP_ERR_INVALID_ARG;
    }
    static const char *const keys[] = {"enabled", "phrase", "sensitivity", "gain_db"};
    const uint8_t values[] = {in->enabled, in->phrase, in->sensitivity, in->gain_db};
    return set_u8s("wake", keys, values, 4);
}

/* ── LED ──────────────────────────────────────────────────── */

uint8_t settings_get_led_brightness(void)
{
    return get_u8("led", "brightness", 60, 100);
}

esp_err_t settings_set_led_brightness(uint8_t brightness)
{
    if (brightness > 100) {
        return ESP_ERR_INVALID_ARG;
    }
    static const char *const keys[] = {"brightness"};
    return set_u8s("led", keys, &brightness, 1);
}

/* ── Strings ──────────────────────────────────────────────── */

esp_err_t settings_get_str(const char *ns, const char *key, char *out, size_t *out_len)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(ns, NVS_READONLY, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_get_str(h, key, out, out_len);
    nvs_close(h);
    return err;
}

esp_err_t settings_set_str(const char *ns, const char *key, const char *value)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(ns, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_str(h, key, value);
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    return err;
}

esp_err_t settings_factory_reset(void)
{
    ESP_LOGW(TAG, "factory reset: erasing nvs and secrets");
    esp_err_t err = nvs_flash_erase_partition(NVS_DEFAULT_PART_NAME);
    esp_err_t err2 = nvs_flash_erase_partition(APP_PART_SECRETS);
    return err != ESP_OK ? err : err2;
}
