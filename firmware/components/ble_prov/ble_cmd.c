/*
 * Settings command protocol (design document, Section 2.13, 0xFF81 / 0xFF82).
 * Chunk: [seq:1B][flags:1B][payload…], flags bit0 = last, bit1 = first chunk.
 * Reassembly up to 4,096 bytes, 3 s limit, 1 request at a time per connection.
 * Responses go out only on the encrypted link that sent the request. Secrets never go into responses or logs.
 */
#include <stdlib.h>
#include <string.h>
#include "app_config.h"
#include "app_events.h"
#include "ble_internal.h"
#include "cJSON.h"
#include "device_api.h"
#include "media_spotify.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "host/ble_hs.h"
#include "esp_timer.h"
#include "secret_store.h"

static const char *TAG = "BLE_CMD";

#define FLAG_LAST  0x01
#define FLAG_FIRST 0x02

/* Reassembly (used only from the GATT callback) */
static char *s_buf;
static size_t s_used;
static int s_next_seq = -1;             /* -1 = no message in progress */
static esp_timer_handle_t s_timeout;
static volatile bool s_busy;            /* handling one request */
static volatile bool s_close_requested;
/* Reassembly state is touched by both the NimBLE host task (chunks) and the esp_timer task (timeout) */
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;

typedef enum {
    FRAME_ERR_TIMEOUT,
    FRAME_ERR_TOO_LARGE,
    FRAME_ERR_INVALID,
} frame_err_t;

static void on_timeout(void *arg)
{
    bool expired = false;
    portENTER_CRITICAL(&s_lock);
    if (s_next_seq >= 0) {
        s_next_seq = -1;
        memset(s_buf, 0, s_used);
        s_used = 0;
        expired = true;
    }
    portEXIT_CRITICAL(&s_lock);
    if (expired) {
        ble_post_job(JOB_COMMAND_ERROR, FRAME_ERR_TIMEOUT, NULL, 0);
    }
}

void ble_cmd_reset(void)
{
    if (s_timeout) {
        esp_timer_stop(s_timeout);
    }
    portENTER_CRITICAL(&s_lock);
    s_next_seq = -1;
    if (s_buf) {
        memset(s_buf, 0, s_used);
    }
    s_used = 0;
    portEXIT_CRITICAL(&s_lock);
    s_busy = false;
    s_close_requested = false;
}

bool ble_cmd_take_close_request(void)
{
    bool r = s_close_requested;
    s_close_requested = false;
    return r;
}

static int request_id(const char *json)
{
    cJSON *root = cJSON_Parse(json);
    const cJSON *id = cJSON_GetObjectItem(root, "id");
    int v = cJSON_IsNumber(id) ? id->valueint : -1;
    cJSON_Delete(root);
    return v;
}

int ble_cmd_on_fragment(const uint8_t *data, size_t len)
{
    if (!s_buf) {
        s_buf = heap_caps_malloc(APP_BLE_CMD_MAX_BYTES + 1, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        const esp_timer_create_args_t args = {.callback = on_timeout, .name = "ble_frame"};
        if (!s_buf || esp_timer_create(&args, &s_timeout) != ESP_OK) {
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
    }
    if (len < 2) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    uint8_t seq = data[0], flags = data[1];
    if (flags & FLAG_FIRST) {
        esp_timer_stop(s_timeout);
    }

    /* state changes inside the lock; posting jobs, timers and malloc outside it */
    enum { R_MORE, R_ERROR, R_TOO_LARGE, R_DONE } result;
    size_t total = 0;
    portENTER_CRITICAL(&s_lock);
    if (flags & FLAG_FIRST) {
        memset(s_buf, 0, s_used);
        s_used = 0;
        s_next_seq = 0;
    }
    if (s_next_seq < 0 || seq != s_next_seq) {
        s_next_seq = -1;
        result = R_ERROR;
    } else if (s_used + (len - 2) > APP_BLE_CMD_MAX_BYTES) {
        s_next_seq = -1;
        result = R_TOO_LARGE;
    } else {
        memcpy(s_buf + s_used, data + 2, len - 2);
        s_used += len - 2;
        if (flags & FLAG_LAST) {
            s_next_seq = -1;        /* close it first so the timeout callback can't touch this message */
            s_buf[s_used] = '\0';
            total = s_used;
            result = R_DONE;
        } else {
            s_next_seq = seq == 255 ? -1 : seq + 1;     /* no more than 255 */
            result = R_MORE;
        }
    }
    portEXIT_CRITICAL(&s_lock);

    if (result == R_MORE) {
        if (flags & FLAG_FIRST) {
            esp_timer_start_once(s_timeout, APP_BLE_CMD_REASSEMBLY_MS * 1000);
        }
        return 0;
    }
    esp_timer_stop(s_timeout);
    if (result != R_DONE) {
        portENTER_CRITICAL(&s_lock);
        memset(s_buf, 0, s_used);
        s_used = 0;
        portEXIT_CRITICAL(&s_lock);
        ble_post_job(JOB_COMMAND_ERROR, result == R_TOO_LARGE ? FRAME_ERR_TOO_LARGE : FRAME_ERR_INVALID, NULL, 0);
        return 0;
    }

    /* complete message: copy it, then wipe the buffer right away (so no secret is left behind, even on BUSY) */
    char *copy = malloc(total + 1);
    portENTER_CRITICAL(&s_lock);
    if (copy) {
        memcpy(copy, s_buf, total + 1);
    }
    memset(s_buf, 0, total);
    s_used = 0;
    portEXIT_CRITICAL(&s_lock);
    if (!copy) {
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (s_busy) {
        int id = request_id(copy);
        memset(copy, 0, total);
        free(copy);
        ble_post_job(JOB_COMMAND_BUSY, id, NULL, 0);
        return 0;
    }
    s_busy = true;
    if (!ble_post_job(JOB_COMMAND, 0, copy, total)) {
        memset(copy, 0, total);
        free(copy);
        s_busy = false;
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    return 0;
}

/* ── Sending responses (worker task) ────────────────────────────── */

static void send_response(cJSON *resp)
{
    char *text = cJSON_PrintUnformatted(resp);
    cJSON_Delete(resp);
    if (!text) {
        return;
    }
    size_t len = strlen(text);
    size_t chunk = ble_mtu() - 5;       /* 3-byte ATT header + 2-byte chunk header */
    uint8_t frame[520];
    if (chunk > sizeof(frame) - 2) {
        chunk = sizeof(frame) - 2;
    }
    uint8_t seq = 0;
    size_t off = 0;
    do {
        size_t n = len - off > chunk ? chunk : len - off;
        frame[0] = seq++;
        frame[1] = (off == 0 ? FLAG_FIRST : 0) | (off + n >= len ? FLAG_LAST : 0);
        memcpy(frame + 2, text + off, n);
        if (ble_notify(g_ble.cmd_tx_handle, frame, n + 2) != ESP_OK) {
            ESP_LOGW(TAG, "response notify failed");
            break;
        }
        off += n;
    } while (off < len);
    free(text);
}

static cJSON *new_response(int id, bool ok)
{
    cJSON *r = cJSON_CreateObject();
    if (id >= 0) {
        cJSON_AddNumberToObject(r, "id", id);
    } else {
        cJSON_AddNullToObject(r, "id");
    }
    cJSON_AddBoolToObject(r, "ok", ok);
    return r;
}

void ble_cmd_reply_error(int id, const char *code)
{
    cJSON *r = new_response(id, false);
    cJSON_AddStringToObject(r, "error", code);
    send_response(r);
}

static const char *err_code(esp_err_t err)
{
    switch (err) {
    case ESP_ERR_INVALID_ARG:
    case ESP_ERR_NOT_FOUND:
        return "INVALID_ARG";
    case ESP_ERR_NOT_ALLOWED:
        /* settings.set group assistant: ai_provider set to a provider with no key (docs/design-voice-saver-mode.md 11.1) */
        return "NO_API_KEY";
    default:
        return "STORAGE_FAIL";
    }
}

static const char *string_field(const cJSON *req, const char *key)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(req, key);
    return cJSON_IsString(v) ? v->valuestring : NULL;
}

static void secrets_changed(void)
{
    const app_setting_t key = APP_SETTING_SECRETS;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
}

/* ── Command handling ────────────────────────────────────────────── */

static cJSON *handle(int id, const char *op, cJSON *req)
{
    if (!strcmp(op, "device.info")) {
        cJSON *r = device_info();
        cJSON_AddNumberToObject(r, "id", id);
        cJSON_AddBoolToObject(r, "ok", true);
        return r;
    }

    if (!strcmp(op, "secret.set") || !strcmp(op, "secret.erase")) {
        bool erase = !strcmp(op, "secret.erase");
        const char *key = string_field(req, "key");
        cJSON *value = cJSON_GetObjectItemCaseSensitive(req, "value");
        secret_id_t sid;
        if (!device_secret_from_name(key, &sid) ||
            (!erase && (!cJSON_IsString(value) || !value->valuestring[0] || strlen(value->valuestring) > 512))) {
            return NULL;    /* INVALID_ARG */
        }
        esp_err_t err = erase ? secret_erase(sid) : secret_set(sid, value->valuestring, strlen(value->valuestring));
        if (!erase) {
            memset(value->valuestring, 0, strlen(value->valuestring));
        }
        if (err != ESP_OK) {
            cJSON *r = new_response(id, false);
            cJSON_AddStringToObject(r, "error", "STORAGE_FAIL");
            return r;
        }
        secrets_changed();
        return new_response(id, true);
    }

    if (!strcmp(op, "settings.get")) {
        cJSON *value = device_settings_get(string_field(req, "group"));
        if (!value) {
            return NULL;
        }
        cJSON *r = new_response(id, true);
        cJSON_AddItemToObject(r, "value", value);
        return r;
    }

    if (!strcmp(op, "settings.set")) {
        esp_err_t err = device_settings_set(string_field(req, "group"), cJSON_GetObjectItemCaseSensitive(req, "value"));
        if (err != ESP_OK) {
            cJSON *r = new_response(id, false);
            cJSON_AddStringToObject(r, "error", err_code(err));
            return r;
        }
        return new_response(id, true);
    }

    if (!strcmp(op, "api.pair")) {
        const char *phone_id = string_field(req, "phone_id");
        const char *name = string_field(req, "phone_name");
        char token[PHONE_TOKEN_LEN + 1];
        esp_err_t err = phones_pair(phone_id, name ? name : "", string_field(req, "evict"), token);
        if (err == ESP_ERR_INVALID_SIZE) {
            /* full: return the list; the app picks a phone to remove and retries with evict */
            cJSON *r = new_response(id, false);
            cJSON_AddStringToObject(r, "error", "PHONES_FULL");
            cJSON_AddItemToObject(r, "phones", phones_list(NULL));
            return r;
        }
        if (err != ESP_OK) {
            cJSON *r = new_response(id, false);
            cJSON_AddStringToObject(r, "error", err_code(err));
            return r;
        }
        cJSON *r = new_response(id, true);
        cJSON_AddStringToObject(r, "token", token);
        cJSON_AddStringToObject(r, "phone_id", phone_id);
        memset(token, 0, sizeof(token));
        return r;
    }

    if (!strcmp(op, "spotify.logout")) {
        bool ok = spotify_logout() == ESP_OK;
        cJSON *r = new_response(id, ok);
        if (!ok) {
            cJSON_AddStringToObject(r, "error", "STORAGE_FAIL");
        }
        return r;
    }

    if (!strcmp(op, "spotify.link")) {
        /* save both values at once. Verify with a token refresh before saving (Section 2.13) */
        cJSON *rt = cJSON_GetObjectItemCaseSensitive(req, "refresh_token");
        esp_err_t err = spotify_link(string_field(req, "client_id"), cJSON_IsString(rt) ? rt->valuestring : NULL);
        if (cJSON_IsString(rt)) {
            memset(rt->valuestring, 0, strlen(rt->valuestring));
        }
        cJSON *r = new_response(id, err == ESP_OK);
        if (err != ESP_OK) {
            cJSON_AddStringToObject(r, "error", err == ESP_ERR_INVALID_ARG    ? "INVALID_ARG"
                                                : err == ESP_ERR_NOT_SUPPORTED ? "UNKNOWN_OP"    /* build with Spotify turned off */
                                                                               : "STORAGE_FAIL");
        }
        return r;
    }

    if (!strcmp(op, "prov.close")) {
        s_close_requested = true;   /* the worker task closes the window after sending the response */
        return new_response(id, true);
    }

    cJSON *r = new_response(id, false);
    cJSON_AddStringToObject(r, "error", "UNKNOWN_OP");
    return r;
}

void ble_cmd_handle(char *json, size_t len)
{
    cJSON *req = cJSON_Parse(json);
    memset(json, 0, len);
    free(json);

    const cJSON *id = cJSON_GetObjectItem(req, "id");
    const cJSON *op = cJSON_GetObjectItem(req, "op");
    int rid = cJSON_IsNumber(id) ? id->valueint : -1;
    cJSON *resp;
    if (!cJSON_IsObject(req) || rid < 0 || !cJSON_IsString(op)) {
        resp = new_response(rid, false);
        cJSON_AddStringToObject(resp, "error", "INVALID_ARG");
    } else {
        ESP_LOGI(TAG, "op %s", op->valuestring);    /* content is never logged */
        resp = handle(rid, op->valuestring, req);
        if (!resp) {
            resp = new_response(rid, false);
            cJSON_AddStringToObject(resp, "error", "INVALID_ARG");
        }
    }
    cJSON_Delete(req);
    send_response(resp);
    s_busy = false;
}

/* From the worker task: reassembly failure response */
void ble_cmd_frame_error(int kind)
{
    ble_cmd_reply_error(-1, kind == FRAME_ERR_TIMEOUT ? "FRAME_TIMEOUT"
                          : kind == FRAME_ERR_TOO_LARGE ? "TOO_LARGE" : "INVALID_ARG");
}
