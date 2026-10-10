/*
 * Telegram store: registered chats, options, last update_id (design document Section 2.12, telegram namespace).
 * - chats: JSON string [{chat_id, alias, title, type}], up to 10
 * - last_upd: i64. Saved at most once every 30 s when it changes (flash lifetime). Even after a reboot with a slightly stale value,
 *   messages Telegram has already acknowledged don't come again (design document Section 2.11, item 4)
 * - auto_read, quiet_s, quiet_e: auto-read of new messages and quiet hours (TLG-10)
 */
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include "app_config.h"
#include "app_events.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs.h"
#include "settings.h"
#include "tg_internal.h"

static const char *TAG = "TG_STORE";

#define NS             "telegram"
#define CHATS_MAX_JSON 3072
#define SAVE_EVERY_US  (30LL * 1000 * 1000)

static SemaphoreHandle_t s_lock;
static cJSON *s_chats;
static int64_t s_last_upd, s_saved_upd;
static int64_t s_last_save_us;

static void notify(void)
{
    const app_setting_t key = APP_SETTING_TELEGRAM;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
}

static esp_err_t save_chats(void)
{
    char *text = cJSON_PrintUnformatted(s_chats);
    if (!text) {
        return ESP_ERR_NO_MEM;
    }
    esp_err_t err = settings_set_str(NS, "chats", text);
    free(text);
    notify();
    return err;
}

esp_err_t tg_store_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) {
        return ESP_ERR_NO_MEM;
    }
    char *buf = malloc(CHATS_MAX_JSON);
    size_t len = CHATS_MAX_JSON;
    if (buf && settings_get_str(NS, "chats", buf, &len) == ESP_OK) {
        s_chats = cJSON_Parse(buf);
    }
    free(buf);
    if (!cJSON_IsArray(s_chats)) {
        cJSON_Delete(s_chats);
        s_chats = cJSON_CreateArray();
    }
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) == ESP_OK) {
        nvs_get_i64(h, "last_upd", &s_last_upd);
        nvs_close(h);
    }
    s_saved_upd = s_last_upd;
    ESP_LOGI(TAG, "%d chat(s) registered", cJSON_GetArraySize(s_chats));
    return s_chats ? ESP_OK : ESP_ERR_NO_MEM;
}

/* ── update_id ────────────────────────────────────────────── */

int64_t tg_last_update_id(void)
{
    return s_last_upd;
}

void tg_save_last_update_id(int64_t id, bool force)
{
    s_last_upd = id;
    int64_t now = esp_timer_get_time();
    if (id == s_saved_upd || (!force && now - s_last_save_us < SAVE_EVERY_US)) {
        return;
    }
    nvs_handle_t h;
    if (nvs_open(NS, NVS_READWRITE, &h) == ESP_OK) {
        if (nvs_set_i64(h, "last_upd", id) == ESP_OK && nvs_commit(h) == ESP_OK) {
            s_saved_upd = id;
            s_last_save_us = now;
        }
        nvs_close(h);
    }
}

/* ── Chats ─────────────────────────────────────────────────── */

static cJSON *find_locked(int64_t chat_id)
{
    cJSON *c;
    cJSON_ArrayForEach(c, s_chats) {
        const cJSON *id = cJSON_GetObjectItem(c, "chat_id");
        if (cJSON_IsNumber(id) && (int64_t)id->valuedouble == chat_id) {
            return c;
        }
    }
    return NULL;
}

cJSON *telegram_chats(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *copy = cJSON_Duplicate(s_chats, true);
    xSemaphoreGive(s_lock);
    return copy;
}

bool tg_chat_registered(int64_t chat_id, char alias_out[TG_ALIAS_MAX + 1])
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    const cJSON *c = find_locked(chat_id);
    if (c && alias_out) {
        strlcpy(alias_out, cJSON_GetObjectItem(c, "alias")->valuestring, TG_ALIAS_MAX + 1);
    }
    xSemaphoreGive(s_lock);
    return c != NULL;
}

static bool contains_ci(const char *hay, const char *needle)
{
    size_t n = strlen(needle);
    for (; n && *hay; hay++) {
        if (!strncasecmp(hay, needle, n)) {
            return true;
        }
    }
    return false;
}

bool telegram_find_chat(const char *alias, int64_t *chat_id, char alias_out[TG_ALIAS_MAX + 1])
{
    if (!alias || !alias[0]) {
        return false;
    }
    bool found = false;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    /* exact alias match first, otherwise partial match */
    for (int pass = 0; pass < 2 && !found; pass++) {
        const cJSON *c;
        cJSON_ArrayForEach(c, s_chats) {
            const char *a = cJSON_GetObjectItem(c, "alias")->valuestring;
            if (pass == 0 ? !strcasecmp(a, alias) : contains_ci(a, alias)) {
                *chat_id = (int64_t)cJSON_GetObjectItem(c, "chat_id")->valuedouble;
                if (alias_out) {
                    strlcpy(alias_out, a, TG_ALIAS_MAX + 1);
                }
                found = true;
                break;
            }
        }
    }
    xSemaphoreGive(s_lock);
    return found;
}

esp_err_t tg_chat_add(int64_t chat_id, const char *title, const char *type)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *c = find_locked(chat_id);
    esp_err_t err = ESP_OK;
    if (!c) {
        if (cJSON_GetArraySize(s_chats) >= TG_MAX_CHATS) {
            err = ESP_ERR_NO_MEM;
        } else {
            c = cJSON_CreateObject();
            cJSON_AddNumberToObject(c, "chat_id", (double)chat_id);
            char alias[TG_ALIAS_MAX + 1];
            strlcpy(alias, title && title[0] ? title : "Telegram", sizeof(alias));
            cJSON_AddStringToObject(c, "alias", alias);    /* initial alias is the chat title; changed in the app */
            cJSON_AddStringToObject(c, "title", title ? title : "");
            cJSON_AddStringToObject(c, "type", type ? type : "private");
            cJSON_AddItemToArray(s_chats, c);
        }
    } else {
        cJSON_ReplaceItemInObject(c, "title", cJSON_CreateString(title ? title : ""));
    }
    if (err == ESP_OK) {
        err = save_chats();
    }
    xSemaphoreGive(s_lock);
    return err;
}

void tg_chat_migrate(int64_t old_id, int64_t new_id)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *c = find_locked(old_id);
    if (c && !find_locked(new_id)) {
        cJSON_ReplaceItemInObject(c, "chat_id", cJSON_CreateNumber((double)new_id));
        cJSON_ReplaceItemInObject(c, "type", cJSON_CreateString("supergroup"));
        save_chats();
        ESP_LOGI(TAG, "chat migrated to supergroup");
    }
    xSemaphoreGive(s_lock);
}

esp_err_t telegram_chat_rename(int64_t chat_id, const char *alias)
{
    if (!alias || !alias[0] || strlen(alias) > TG_ALIAS_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *c = find_locked(chat_id);
    esp_err_t err = ESP_ERR_NOT_FOUND;
    if (c) {
        cJSON_ReplaceItemInObject(c, "alias", cJSON_CreateString(alias));
        err = save_chats();
    }
    xSemaphoreGive(s_lock);
    return err;
}

esp_err_t telegram_chat_remove(int64_t chat_id)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    esp_err_t err = ESP_ERR_NOT_FOUND;
    int i = 0;
    cJSON *c;
    cJSON_ArrayForEach(c, s_chats) {
        if ((int64_t)cJSON_GetObjectItem(c, "chat_id")->valuedouble == chat_id) {
            cJSON_DeleteItemFromArray(s_chats, i);
            err = save_chats();
            break;
        }
        i++;
    }
    xSemaphoreGive(s_lock);
    return err;
}

/* ── Options ───────────────────────────────────────────────── */

static uint8_t get_u8(const char *key, uint8_t def, uint8_t max)
{
    nvs_handle_t h;
    uint8_t v = def;
    if (nvs_open(NS, NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_u8(h, key, &v) != ESP_OK || v > max) {
            v = def;
        }
        nvs_close(h);
    }
    return v;
}

cJSON *telegram_options(void)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddBoolToObject(j, "auto_read", get_u8("auto_read", 0, 1));
    cJSON_AddNumberToObject(j, "quiet_start", get_u8("quiet_s", 22, 23));
    cJSON_AddNumberToObject(j, "quiet_end", get_u8("quiet_e", 7, 23));
    return j;
}

esp_err_t telegram_options_set(const cJSON *v)
{
    if (!cJSON_IsObject(v)) {
        return ESP_ERR_INVALID_ARG;
    }
    uint8_t vals[3] = {get_u8("auto_read", 0, 1), get_u8("quiet_s", 22, 23), get_u8("quiet_e", 7, 23)};
    static const char *const names[3] = {"auto_read", "quiet_start", "quiet_end"};
    static const char *const keys[3] = {"auto_read", "quiet_s", "quiet_e"};
    const cJSON *item;
    cJSON_ArrayForEach(item, v) {
        int k = -1;
        for (int i = 0; i < 3; i++) {
            if (!strcmp(item->string, names[i])) {
                k = i;
            }
        }
        if (k < 0) {
            return ESP_ERR_INVALID_ARG;
        }
        if (k == 0 ? !cJSON_IsBool(item)
                   : (!cJSON_IsNumber(item) || item->valuedouble != item->valueint || item->valueint < 0 ||
                      item->valueint > 23)) {
            return ESP_ERR_INVALID_ARG;
        }
        vals[k] = k == 0 ? cJSON_IsTrue(item) : (uint8_t)item->valueint;
    }
    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    for (int i = 0; i < 3 && err == ESP_OK; i++) {
        err = nvs_set_u8(h, keys[i], vals[i]);
    }
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    if (err == ESP_OK) {
        notify();
    }
    return err;
}

bool telegram_auto_read_now(void)
{
    if (!get_u8("auto_read", 0, 1)) {
        ESP_LOGI(TAG, "auto-read is off (app: Telegram > read new messages)");
        return false;
    }
    int start = get_u8("quiet_s", 22, 23), end = get_u8("quiet_e", 7, 23);
    time_t now = time(NULL);
    if (start == end || now < APP_TIME_VALID_EPOCH) {
        return true;    /* no quiet hours, or the time is unknown so we can't tell */
    }
    struct tm local;
    localtime_r(&now, &local);
    int h = local.tm_hour;
    bool quiet = start < end ? (h >= start && h < end) : (h >= start || h < end);   /* ranges that cross midnight, like 22–7 */
    if (quiet) {
        ESP_LOGI(TAG, "quiet hours %02d-%02d (now %02d:%02d): chime only", start, end, h, local.tm_min);
    }
    return !quiet;
}
