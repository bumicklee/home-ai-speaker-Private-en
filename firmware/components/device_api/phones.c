/*
 * LAN API token store (design document Section 2.0 server-free design, Section 2.14 authentication).
 * - One token per phone (up to 5). The device stores only the token's SHA-256 in NVS (api/phones).
 * - Verification compares all 5 slots the same way (constant time), so the timing does not leak which slot matched.
 */
#include "device_api.h"

#include <string.h>
#include <time.h>
#include "app_config.h"
#include "app_events.h"
#include "esp_log.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mbedtls/base64.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

static const char *TAG = "PHONES";

#define BLOB_VERSION 1

typedef struct {
    char phone_id[PHONE_ID_MAX + 1];
    char name[PHONE_NAME_MAX + 1];
    uint8_t hash[32];
    uint32_t created;       /* UNIX time (0 if the clock is not set) */
    uint8_t used;
} phone_t;

typedef struct {
    uint8_t version;
    phone_t slots[APP_API_MAX_PHONES];
} phones_blob_t;

static phones_blob_t s_db;
static SemaphoreHandle_t s_lock;

static esp_err_t save(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open("api", NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_blob(h, "phones", &s_db, sizeof(s_db));
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    const app_setting_t key = APP_SETTING_PHONES;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
    return err;
}

esp_err_t phones_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) {
        return ESP_ERR_NO_MEM;
    }
    nvs_handle_t h;
    size_t len = sizeof(s_db);
    if (nvs_open("api", NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_blob(h, "phones", &s_db, &len) != ESP_OK || len != sizeof(s_db) || s_db.version != BLOB_VERSION) {
            memset(&s_db, 0, sizeof(s_db));
        }
        nvs_close(h);
    }
    s_db.version = BLOB_VERSION;
    int n = 0;
    for (int i = 0; i < APP_API_MAX_PHONES; i++) {
        n += s_db.slots[i].used;
    }
    ESP_LOGI(TAG, "%d phone(s) registered", n);
    return ESP_OK;
}

static void hash_token(const char *token, uint8_t out[32])
{
    mbedtls_sha256((const unsigned char *)token, strlen(token), out, 0);
}

static int find(const char *phone_id)
{
    for (int i = 0; i < APP_API_MAX_PHONES; i++) {
        if (s_db.slots[i].used && !strcmp(s_db.slots[i].phone_id, phone_id)) {
            return i;
        }
    }
    return -1;
}

esp_err_t phones_pair(const char *phone_id, const char *name, const char *evict, char token[PHONE_TOKEN_LEN + 1])
{
    if (!phone_id || !phone_id[0] || strlen(phone_id) > PHONE_ID_MAX || !name || strlen(name) > PHONE_NAME_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int slot = find(phone_id);      /* re-registering the same phone replaces it (does not count against the 5-phone limit) */
    if (slot < 0 && evict) {
        int victim = find(evict);
        if (victim >= 0) {
            memset(&s_db.slots[victim], 0, sizeof(phone_t));
        }
    }
    for (int i = 0; slot < 0 && i < APP_API_MAX_PHONES; i++) {
        if (!s_db.slots[i].used) {
            slot = i;
        }
    }
    if (slot < 0) {
        xSemaphoreGive(s_lock);
        return ESP_ERR_INVALID_SIZE;
    }

    uint8_t raw[32];
    size_t olen = 0;
    esp_fill_random(raw, sizeof(raw));
    char b64[48];
    mbedtls_base64_encode((unsigned char *)b64, sizeof(b64), &olen, raw, sizeof(raw));
    memset(raw, 0, sizeof(raw));
    /* base64 → base64url, padding removed */
    size_t n = 0;
    for (size_t i = 0; i < olen && b64[i] != '='; i++) {
        char c = b64[i];
        token[n++] = c == '+' ? '-' : (c == '/' ? '_' : c);
    }
    token[n] = '\0';
    memset(b64, 0, sizeof(b64));

    phone_t *p = &s_db.slots[slot];
    memset(p, 0, sizeof(*p));
    strlcpy(p->phone_id, phone_id, sizeof(p->phone_id));
    strlcpy(p->name, name, sizeof(p->name));
    hash_token(token, p->hash);
    time_t now = time(NULL);
    p->created = now >= APP_TIME_VALID_EPOCH ? (uint32_t)now : 0;
    p->used = 1;
    esp_err_t err = save();
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "paired slot %d: %s", slot, esp_err_to_name(err));
    return err;
}

bool phones_verify(const char *token, char phone_id[PHONE_ID_MAX + 1])
{
    if (!token || strlen(token) != PHONE_TOKEN_LEN) {
        return false;
    }
    uint8_t hash[32];
    hash_token(token, hash);
    int match = -1;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < APP_API_MAX_PHONES; i++) {
        uint8_t diff = s_db.slots[i].used ? 0 : 1;
        for (int b = 0; b < 32; b++) {
            diff |= hash[b] ^ s_db.slots[i].hash[b];
        }
        /* record without branching so every slot takes the same time */
        int hit = (diff == 0);
        match = hit ? i : match;
    }
    if (match >= 0 && phone_id) {
        strlcpy(phone_id, s_db.slots[match].phone_id, PHONE_ID_MAX + 1);
    }
    xSemaphoreGive(s_lock);
    return match >= 0;
}

cJSON *phones_list(const char *self_phone_id)
{
    cJSON *arr = cJSON_CreateArray();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    for (int i = 0; i < APP_API_MAX_PHONES; i++) {
        const phone_t *p = &s_db.slots[i];
        if (!p->used) {
            continue;
        }
        cJSON *o = cJSON_CreateObject();
        cJSON_AddStringToObject(o, "phone_id", p->phone_id);
        cJSON_AddStringToObject(o, "name", p->name);
        cJSON_AddNumberToObject(o, "created", p->created);
        cJSON_AddBoolToObject(o, "self", self_phone_id && !strcmp(self_phone_id, p->phone_id));
        cJSON_AddItemToArray(arr, o);
    }
    xSemaphoreGive(s_lock);
    return arr;
}

esp_err_t phones_revoke(const char *phone_id)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int slot = phone_id ? find(phone_id) : -1;
    esp_err_t err = ESP_ERR_NOT_FOUND;
    if (slot >= 0) {
        memset(&s_db.slots[slot], 0, sizeof(phone_t));
        err = save();
    }
    xSemaphoreGive(s_lock);
    return err;
}

esp_err_t phones_clear(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    memset(s_db.slots, 0, sizeof(s_db.slots));
    esp_err_t err = save();
    xSemaphoreGive(s_lock);
    return err;
}
