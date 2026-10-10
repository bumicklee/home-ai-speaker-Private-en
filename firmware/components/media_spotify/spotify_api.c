/*
 * Spotify Web API client (design document Section 2.10). See media_spotify.h for details.
 *
 * Tokens:
 *   - The app logs in with PKCE and hands the refresh token over BLE (spotify.link). There is no client secret (public client).
 *   - The access token (1 hour) stays only in RAM and is refreshed 60 seconds before expiry or on a 401.
 *   - If the refresh response carries a new refresh token, it is swapped in and saved immediately (token rotation).
 *   - When the refresh token expires (6 months after the first authorization): 400 → RELOGIN_REQUIRED, and the app prompts a new login.
 * All Web API calls run one at a time (mutex). Called from the tool worker, the BLE work task, and LAN handlers.
 */
#include "media_spotify.h"

#include <ctype.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "app_config.h"
#include "app_events.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "secret_store.h"

static const char *TAG = "SPOTIFY";

#define ACCOUNTS_TOKEN  "https://accounts.spotify.com/api/token"
#define API_BASE        "https://api.spotify.com/v1"
#define RESPONSE_MAX    (32 * 1024)
#define TOKEN_MAX       512
#define REFRESH_MARGIN  (60LL * 1000 * 1000)
#define HTTP_TIMEOUT_MS 10000

static SemaphoreHandle_t s_lock;
static char s_access[TOKEN_MAX];
static int64_t s_access_expires_us;
static atomic_int s_state = SPOTIFY_OFF;
static char s_account[64];
static char s_device[64];
static char s_last_error[64];
static atomic_bool s_recently_playing;
/* Display strings and the now cache use a short lock of their own, separate from the long HTTPS lock (s_lock), so LAN handlers do not wait */
static portMUX_TYPE s_info_mux = portMUX_INITIALIZER_UNLOCKED;
static SemaphoreHandle_t s_cache_lock;
static cJSON *s_now_cache;

static void info_set(char *dst, size_t len, const char *value)
{
    portENTER_CRITICAL(&s_info_mux);
    strlcpy(dst, value ? value : "", len);
    portEXIT_CRITICAL(&s_info_mux);
}

static void info_get(char *out, size_t len, const char *src)
{
    portENTER_CRITICAL(&s_info_mux);
    strlcpy(out, src, len);
    portEXIT_CRITICAL(&s_info_mux);
}

/* ── Common ───────────────────────────────────────────────── */

const char *spotify_state_name(spotify_state_t state)
{
    static const char *const names[] = {"off", "ok", "relogin_required", "premium_required", "error"};
    return (unsigned)state < 5 ? names[state] : "off";
}

spotify_state_t spotify_state(void)
{
    return atomic_load(&s_state);
}

bool spotify_linked(void)
{
    return secret_exists(SECRET_SP_REFRESH) && secret_exists(SECRET_SP_CLIENT_ID);
}

bool spotify_recently_playing(void)
{
    return atomic_load(&s_recently_playing);
}

static void set_error(spotify_state_t state, const char *error)
{
    atomic_store(&s_state, state);
    info_set(s_last_error, sizeof(s_last_error), error);
}

static void url_encode(const char *in, char *out, size_t out_len)
{
    static const char hex[] = "0123456789ABCDEF";
    size_t o = 0;
    for (; *in && o + 4 < out_len; in++) {
        unsigned char c = (unsigned char)*in;
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out[o++] = (char)c;
        } else {
            out[o++] = '%';
            out[o++] = hex[c >> 4];
            out[o++] = hex[c & 15];
        }
    }
    out[o] = '\0';
}

typedef struct {
    char *buf;
    size_t used;
} body_t;

static esp_err_t on_http(esp_http_client_event_t *evt)
{
    body_t *b = evt->user_data;
    if (evt->event_id == HTTP_EVENT_ON_DATA && b && b->used + evt->data_len < RESPONSE_MAX) {
        memcpy(b->buf + b->used, evt->data, evt->data_len);
        b->used += evt->data_len;
    }
    return ESP_OK;
}

/* One HTTP request. Returns the status code (-1 on network error). Response JSON in out (NULL if none) */
static int http_request(esp_http_client_method_t method, const char *url, const char *auth, const char *content_type,
                        const char *body, cJSON **out)
{
    *out = NULL;
    body_t resp = {.buf = heap_caps_malloc(RESPONSE_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)};
    if (!resp.buf) {
        return -1;
    }
    const esp_http_client_config_t cfg = {
        .url = url,
        .method = method,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = HTTP_TIMEOUT_MS,
        .event_handler = on_http,
        .user_data = &resp,
        .buffer_size = 2048,
        .buffer_size_tx = 2048,     /* the Authorization header is long */
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    int status = -1;
    if (client) {
        if (auth) {
            esp_http_client_set_header(client, "Authorization", auth);
        }
        if (content_type) {
            esp_http_client_set_header(client, "Content-Type", content_type);
        }
        if (body) {     /* not called without a body (calling it adds Content-Type) */
            esp_http_client_set_post_field(client, body, strlen(body));
        }
        if (esp_http_client_perform(client) == ESP_OK) {
            status = esp_http_client_get_status_code(client);
        }
        esp_http_client_cleanup(client);
    }
    if (status > 0 && resp.used) {
        resp.buf[resp.used] = '\0';
        *out = cJSON_Parse(resp.buf);
    }
    memset(resp.buf, 0, resp.used);     /* it may be a token response */
    free(resp.buf);
    return status;
}

/* ── Tokens ───────────────────────────────────────────────── */

/* Gets an access token with client_id and the refresh token. If a new refresh token comes back, it goes in rotated */
static esp_err_t token_request(const char *client_id, const char *refresh, char *rotated, size_t rotated_len)
{
    const size_t enc_cap = TOKEN_MAX * 3;
    char *enc_refresh = malloc(enc_cap), enc_id[100];
    size_t form_len = enc_cap + sizeof(enc_id) + 64;
    char *form = malloc(form_len);
    if (!form || !enc_refresh) {
        free(form);
        free(enc_refresh);
        return ESP_ERR_NO_MEM;
    }
    url_encode(refresh, enc_refresh, enc_cap);
    url_encode(client_id, enc_id, sizeof(enc_id));
    snprintf(form, form_len, "grant_type=refresh_token&refresh_token=%s&client_id=%s", enc_refresh, enc_id);
    memset(enc_refresh, 0, enc_cap);
    free(enc_refresh);
    cJSON *resp = NULL;
    int status = http_request(HTTP_METHOD_POST, ACCOUNTS_TOKEN, NULL, "application/x-www-form-urlencoded", form, &resp);
    memset(form, 0, form_len);
    free(form);

    esp_err_t err;
    const cJSON *access = cJSON_GetObjectItem(resp, "access_token");
    const cJSON *expires = cJSON_GetObjectItem(resp, "expires_in");
    const cJSON *next = cJSON_GetObjectItem(resp, "refresh_token");
    if (status == 200 && cJSON_IsString(access) && strlen(access->valuestring) < TOKEN_MAX) {
        strlcpy(s_access, access->valuestring, sizeof(s_access));
        s_access_expires_us = esp_timer_get_time() + (int64_t)(cJSON_IsNumber(expires) ? expires->valueint : 3600) * 1000000;
        if (rotated) {
            rotated[0] = '\0';
            if (cJSON_IsString(next) && strlen(next->valuestring) < rotated_len) {
                strlcpy(rotated, next->valuestring, rotated_len);
            }
        }
        err = ESP_OK;
    } else if (status == 400 || status == 401) {
        err = ESP_ERR_INVALID_ARG;      /* invalid_grant: expired, revoked, or a wrong value */
    } else {
        err = ESP_FAIL;
    }
    if (resp) {
        if (cJSON_IsString(access)) {
            memset(access->valuestring, 0, strlen(access->valuestring));
        }
        if (cJSON_IsString(next)) {
            memset(next->valuestring, 0, strlen(next->valuestring));
        }
        cJSON_Delete(resp);
    }
    ESP_LOGI(TAG, "token refresh: HTTP %d", status);
    return err;
}

/* Refresh with the saved values (with the lock held) */
static esp_err_t refresh_locked(void)
{
    char client_id[64], refresh[TOKEN_MAX], rotated[TOKEN_MAX];
    size_t id_len = sizeof(client_id) - 1, rf_len = sizeof(refresh) - 1;
    if (secret_get(SECRET_SP_CLIENT_ID, client_id, &id_len) != ESP_OK ||
        secret_get(SECRET_SP_REFRESH, refresh, &rf_len) != ESP_OK) {
        set_error(SPOTIFY_OFF, "");
        return ESP_ERR_INVALID_STATE;
    }
    client_id[id_len] = '\0';
    refresh[rf_len] = '\0';
    esp_err_t err = token_request(client_id, refresh, rotated, sizeof(rotated));
    if (err == ESP_OK && rotated[0] && strcmp(rotated, refresh)) {
        secret_set(SECRET_SP_REFRESH, rotated, strlen(rotated));   /* token rotation */
    }
    memset(refresh, 0, sizeof(refresh));
    memset(rotated, 0, sizeof(rotated));
    if (err == ESP_ERR_INVALID_ARG) {
        set_error(SPOTIFY_RELOGIN_REQUIRED, "refresh token expired or revoked");
    } else if (err != ESP_OK) {
        set_error(SPOTIFY_ERROR, "token request failed");
    }
    return err;
}

/* Web API call. Refreshes if there is no token or it is about to expire; on a 401, refreshes once more and retries */
static int api_locked(esp_http_client_method_t method, const char *path, const char *json, cJSON **out)
{
    *out = NULL;
    if ((!s_access[0] || esp_timer_get_time() > s_access_expires_us - REFRESH_MARGIN) && refresh_locked() != ESP_OK) {
        return 0;
    }
    char url[512];
    snprintf(url, sizeof(url), API_BASE "%s", path);
    char auth[TOKEN_MAX + 8];
    int status = 0;
    /* Send an empty object so bodyless POST and PUT (next, pause, etc.) still get a Content-Length */
    if (!json && method != HTTP_METHOD_GET) {
        json = "{}";
    }
    for (int attempt = 0; attempt < 2; attempt++) {
        snprintf(auth, sizeof(auth), "Bearer %s", s_access);
        status = http_request(method, url, auth, json ? "application/json" : NULL, json, out);
        if (status != 401 || attempt == 1) {
            break;
        }
        cJSON_Delete(*out);
        *out = NULL;
        if (refresh_locked() != ESP_OK) {
            break;
        }
    }
    memset(auth, 0, sizeof(auth));
    return status;
}

static const char *error_reason(const cJSON *resp)
{
    const cJSON *reason = cJSON_GetObjectItem(cJSON_GetObjectItem(resp, "error"), "reason");
    return cJSON_IsString(reason) ? reason->valuestring : "";
}

/* Result status of a playback command → esp_err. This is the only place Premium status shows up (GET /me has no product) */
static esp_err_t player_result(int status, const cJSON *resp)
{
    if (status >= 200 && status < 300) {
        atomic_store(&s_state, SPOTIFY_OK);
        info_set(s_last_error, sizeof(s_last_error), "");
        return ESP_OK;
    }
    if (status == 403 && !strcmp(error_reason(resp), "PREMIUM_REQUIRED")) {
        set_error(SPOTIFY_PREMIUM_REQUIRED, "premium required");
        return ESP_ERR_NOT_ALLOWED;
    }
    if (status == 404) {
        set_error(SPOTIFY_OK, "no active device");
        return ESP_ERR_INVALID_STATE;
    }
    if (status == 0) {
        return ESP_ERR_INVALID_STATE;   /* not linked / login needed again */
    }
    set_error(SPOTIFY_ERROR, "player command failed");
    return ESP_FAIL;
}

/* ── Linking ──────────────────────────────────────────────── */

static bool client_id_valid(const char *id)
{
    if (!id || strlen(id) != 32) {
        return false;
    }
    for (const char *p = id; *p; p++) {
        if (!isxdigit((unsigned char)*p)) {
            return false;
        }
    }
    return true;
}

static void fetch_account_locked(void)
{
    cJSON *me = NULL;
    if (api_locked(HTTP_METHOD_GET, "/me", NULL, &me) == 200) {
        const cJSON *name = cJSON_GetObjectItem(me, "display_name");
        info_set(s_account, sizeof(s_account), cJSON_IsString(name) ? name->valuestring : "");
    }
    cJSON_Delete(me);
}

static void secrets_changed(void)
{
    const app_setting_t key = APP_SETTING_SECRETS;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
}

esp_err_t spotify_link(const char *client_id, const char *refresh_token)
{
    if (!client_id_valid(client_id) || !refresh_token || !refresh_token[0] || strlen(refresh_token) >= TOKEN_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    /* Before saving, confirm that a refresh actually works (design document Section 2.13 spotify.link) */
    char rotated[TOKEN_MAX];
    esp_err_t err = token_request(client_id, refresh_token, rotated, sizeof(rotated));
    if (err == ESP_OK) {
        const char *keep = rotated[0] ? rotated : refresh_token;
        err = secret_set(SECRET_SP_CLIENT_ID, client_id, strlen(client_id));
        if (err == ESP_OK) {
            err = secret_set(SECRET_SP_REFRESH, keep, strlen(keep));
        }
        if (err == ESP_OK) {
            atomic_store(&s_state, SPOTIFY_OK);
            info_set(s_last_error, sizeof(s_last_error), "");
            fetch_account_locked();
        }
    } else {
        s_access[0] = '\0';
        if (err == ESP_ERR_INVALID_ARG) {
            ESP_LOGW(TAG, "link rejected by Spotify");
        }
    }
    memset(rotated, 0, sizeof(rotated));
    xSemaphoreGive(s_lock);
    if (err == ESP_OK) {
        secrets_changed();
    }
    return err;
}

esp_err_t spotify_logout(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    esp_err_t a = secret_erase(SECRET_SP_CLIENT_ID);
    esp_err_t b = secret_erase(SECRET_SP_REFRESH);
    esp_err_t c = secret_erase(SECRET_SP_CONNECT_BLOB);
    memset(s_access, 0, sizeof(s_access));
    info_set(s_account, sizeof(s_account), "");
    info_set(s_device, sizeof(s_device), "");
    set_error(SPOTIFY_OFF, "");
    atomic_store(&s_recently_playing, false);
    xSemaphoreGive(s_lock);
    secrets_changed();
    return a != ESP_OK ? a : (b != ESP_OK ? b : c);
}

/* ── Playback ─────────────────────────────────────────────── */

/*
 * Device to play on: this speaker's Connect receiver (name starts with APP_SPOTIFY_DEVICE_NAME) → the currently active device
 * → the first unrestricted device. Until the receiver is attached (Q2), a device on the same account, such as a phone, gets picked.
 */
static bool pick_device_locked(char *id, size_t id_len)
{
    cJSON *resp = NULL;
    int status = api_locked(HTTP_METHOD_GET, "/me/player/devices", NULL, &resp);
    const cJSON *chosen = NULL, *active = NULL, *first = NULL, *d;
    cJSON_ArrayForEach(d, cJSON_GetObjectItem(resp, "devices")) {
        const cJSON *name = cJSON_GetObjectItem(d, "name");
        if (cJSON_IsTrue(cJSON_GetObjectItem(d, "is_restricted")) || !cJSON_IsString(cJSON_GetObjectItem(d, "id"))) {
            continue;
        }
        if (cJSON_IsString(name) && !strncasecmp(name->valuestring, APP_SPOTIFY_DEVICE_NAME, strlen(APP_SPOTIFY_DEVICE_NAME))) {
            chosen = d;
            break;
        }
        if (!active && cJSON_IsTrue(cJSON_GetObjectItem(d, "is_active"))) {
            active = d;
        }
        if (!first) {
            first = d;
        }
    }
    if (!chosen) {
        chosen = active ? active : first;
    }
    bool ok = status == 200 && chosen;
    if (ok) {
        strlcpy(id, cJSON_GetObjectItem(chosen, "id")->valuestring, id_len);
        const cJSON *name = cJSON_GetObjectItem(chosen, "name");
        info_set(s_device, sizeof(s_device), cJSON_IsString(name) ? name->valuestring : "");
    }
    cJSON_Delete(resp);
    return ok;
}

static const char *first_artist(const cJSON *item)
{
    const cJSON *a = cJSON_GetObjectItem(cJSON_GetArrayItem(cJSON_GetObjectItem(item, "artists"), 0), "name");
    return cJSON_IsString(a) ? a->valuestring : "";
}

esp_err_t spotify_play(const char *query, const char *type, char *desc, size_t desc_len)
{
    static const char *const types[] = {"track", "artist", "album", "playlist"};
    bool type_ok = false;
    for (int i = 0; i < 4 && type; i++) {
        type_ok |= !strcmp(type, types[i]);
    }
    if (!query || !query[0] || strlen(query) > 100 || !type_ok) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!spotify_linked()) {
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    char enc[320], path[400];
    url_encode(query, enc, sizeof(enc));
    /* The Development Mode search limit is 10. Take just one */
    snprintf(path, sizeof(path), "/search?q=%s&type=%s&limit=1&market=from_token", enc, type);
    cJSON *resp = NULL;
    int status = api_locked(HTTP_METHOD_GET, path, NULL, &resp);
    char key[16];
    snprintf(key, sizeof(key), "%ss", type);    /* tracks, artists, albums, playlists */
    /* playlist results may contain null items */
    const cJSON *item = NULL, *it;
    cJSON_ArrayForEach(it, cJSON_GetObjectItem(cJSON_GetObjectItem(resp, key), "items")) {
        if (cJSON_IsObject(it)) {
            item = it;
            break;
        }
    }
    const cJSON *uri = cJSON_GetObjectItem(item, "uri"), *name = cJSON_GetObjectItem(item, "name");
    esp_err_t err;
    if (status != 200) {
        err = player_result(status, resp);
    } else if (!cJSON_IsString(uri)) {
        err = ESP_ERR_NOT_FOUND;
    } else {
        const char *n = cJSON_IsString(name) ? name->valuestring : query;
        if (!strcmp(type, "track") || !strcmp(type, "album")) {
            snprintf(desc, desc_len, "%s - %s", n, first_artist(item));
        } else {
            strlcpy(desc, n, desc_len);
        }
        char device[64];
        if (!pick_device_locked(device, sizeof(device))) {
            err = ESP_ERR_INVALID_STATE;    /* no Spotify device is on */
        } else {
            /* tracks use uris; artists, albums and playlists use context_uri (the artist top-tracks API was removed in 2026) */
            cJSON *body = cJSON_CreateObject();
            if (!strcmp(type, "track")) {
                cJSON *uris = cJSON_AddArrayToObject(body, "uris");
                cJSON_AddItemToArray(uris, cJSON_CreateString(uri->valuestring));
            } else {
                cJSON_AddStringToObject(body, "context_uri", uri->valuestring);
            }
            char *json = cJSON_PrintUnformatted(body);
            cJSON_Delete(body);
            snprintf(path, sizeof(path), "/me/player/play?device_id=%s", device);
            cJSON *play_resp = NULL;
            int play_status = json ? api_locked(HTTP_METHOD_PUT, path, json, &play_resp) : -1;
            free(json);
            err = player_result(play_status, play_resp);
            cJSON_Delete(play_resp);
        }
    }
    cJSON_Delete(resp);
    if (err == ESP_OK) {
        atomic_store(&s_recently_playing, true);
    }
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "play %s: %s", type, esp_err_to_name(err));   /* the search query is not logged */
    return err;
}

esp_err_t spotify_control(const char *action)
{
    if (!spotify_linked()) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_http_client_method_t method;
    const char *path;
    if (!strcmp(action, "pause") || !strcmp(action, "stop")) {
        method = HTTP_METHOD_PUT;
        path = "/me/player/pause";
    } else if (!strcmp(action, "resume")) {
        method = HTTP_METHOD_PUT;
        path = "/me/player/play";
    } else if (!strcmp(action, "next")) {
        method = HTTP_METHOD_POST;
        path = "/me/player/next";
    } else if (!strcmp(action, "previous")) {
        method = HTTP_METHOD_POST;
        path = "/me/player/previous";
    } else {
        return ESP_ERR_INVALID_ARG;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *resp = NULL;
    int status = api_locked(method, path, NULL, &resp);
    esp_err_t err = player_result(status, resp);
    cJSON_Delete(resp);
    if (err == ESP_OK) {
        atomic_store(&s_recently_playing, strcmp(action, "pause") && strcmp(action, "stop"));
    }
    xSemaphoreGive(s_lock);
    return err;
}

cJSON *spotify_now_json(void)
{
    cJSON *j = cJSON_CreateObject();
    if (!spotify_linked()) {
        cJSON_AddStringToObject(j, "source", "none");
        return j;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *resp = NULL;
    int status = api_locked(HTTP_METHOD_GET, "/me/player", NULL, &resp);
    xSemaphoreGive(s_lock);
    const cJSON *item = cJSON_GetObjectItem(resp, "item");
    bool playing = status == 200 && cJSON_IsTrue(cJSON_GetObjectItem(resp, "is_playing"));
    atomic_store(&s_recently_playing, playing);
    if (status != 200 || !cJSON_IsObject(item)) {     /* 204 = nothing playing */
        cJSON_AddStringToObject(j, "source", "none");
        cJSON_AddStringToObject(j, "state", "stopped");
    } else {
        const cJSON *name = cJSON_GetObjectItem(item, "name");
        const cJSON *album = cJSON_GetObjectItem(cJSON_GetObjectItem(item, "album"), "name");
        const cJSON *device = cJSON_GetObjectItem(cJSON_GetObjectItem(resp, "device"), "name");
        cJSON_AddStringToObject(j, "source", "spotify");
        cJSON_AddStringToObject(j, "state", playing ? "playing" : "paused");
        cJSON_AddStringToObject(j, "title", cJSON_IsString(name) ? name->valuestring : "");
        cJSON_AddStringToObject(j, "artist", first_artist(item));
        cJSON_AddStringToObject(j, "album", cJSON_IsString(album) ? album->valuestring : "");
        cJSON_AddStringToObject(j, "device", cJSON_IsString(device) ? device->valuestring : "");
    }
    cJSON_Delete(resp);
    /* Cache it so LAN handlers can use it without waiting */
    cJSON *copy = cJSON_Duplicate(j, true);
    xSemaphoreTake(s_cache_lock, portMAX_DELAY);
    cJSON_Delete(s_now_cache);
    s_now_cache = copy;
    xSemaphoreGive(s_cache_lock);
    return j;
}

cJSON *spotify_now_cached(void)
{
    xSemaphoreTake(s_cache_lock, portMAX_DELAY);
    cJSON *copy = s_now_cache ? cJSON_Duplicate(s_now_cache, true) : NULL;
    xSemaphoreGive(s_cache_lock);
    if (!copy) {
        copy = cJSON_CreateObject();
        cJSON_AddStringToObject(copy, "source", "none");
        cJSON_AddStringToObject(copy, "state", "stopped");
    }
    return copy;
}

cJSON *spotify_status_json(void)
{
    cJSON *j = cJSON_CreateObject();
    bool linked = spotify_linked();
    cJSON_AddBoolToObject(j, "linked", linked);
    cJSON_AddStringToObject(j, "state", spotify_state_name(linked ? spotify_state() : SPOTIFY_OFF));
    char buf[64];
    info_get(buf, sizeof(buf), s_account);
    cJSON_AddStringToObject(j, "account", buf);
    /* The Connect receiver (playing directly on the speaker) comes after the Q2 decision. For now, the last chosen playback device */
    cJSON_AddBoolToObject(j, "connect_receiver", false);
    info_get(buf, sizeof(buf), s_device);
    cJSON_AddStringToObject(j, "device", buf);
    info_get(buf, sizeof(buf), s_last_error);
    cJSON_AddStringToObject(j, "last_error", buf);
    return j;
}

esp_err_t media_spotify_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    s_cache_lock = xSemaphoreCreateMutex();
    if (!s_lock || !s_cache_lock) {
        return ESP_ERR_NO_MEM;
    }
    atomic_store(&s_state, spotify_linked() ? SPOTIFY_OK : SPOTIFY_OFF);    /* actually checked on the first call */
    ESP_LOGI(TAG, "%s", spotify_linked() ? "linked" : "not linked");
    return ESP_OK;
}
