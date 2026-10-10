/*
 * LAN REST API (endpoint table in design document Section 2.14). Phase 2 scope:
 *   status, settings/{group}, voices, memories, keys/{key} delete, spotify logout,
 *   voice/{start|stop}, audio/test-tone, wake/test, system/reboot, system/phones, events(WebSocket)
 * Phase 3: radio/presets, media/play, media/{pause|resume|stop|next|previous}, media/now
 * Phase 4: telegram/chats, telegram/chats/{id}, telegram/pair, telegram/options
 * Phase 5: GET/DELETE spotify; media control and now go to Spotify when the radio is off
 * Later: ota(6)
 *
 * Factory reset is not done over LAN. Writing secrets is not accepted over LAN either (D6, BLE only).
 */
#include "local_api.h"

#include <stdlib.h>
#include <string.h>
#include "api_internal.h"
#include "app_config.h"
#include "app_events.h"
#include "assistant.h"
#include "audio_core.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "live_voice.h"
#include "media_radio.h"
#include "messenger_telegram.h"
#include "lesson.h"
#include "media_spotify.h"
#include "notes.h"
#include "lwip/sockets.h"
#include "net.h"
#include "secret_store.h"
#include "wake.h"

static const char *TAG = "API";

#define BODY_MAX 8192     /* 20 presets */
#define PREFIX   "/api/v1/"

static httpd_handle_t s_server;

/* "/api/v1/settings/audio" → "audio" (query string excluded). NULL if empty */
static const char *path_tail(httpd_req_t *req, const char *base, char *out, size_t out_len)
{
    size_t n = strlen(base);
    if (strncmp(req->uri, base, n) != 0) {
        return NULL;
    }
    const char *tail = req->uri + n;
    size_t len = strcspn(tail, "?");
    if (len == 0 || len >= out_len) {
        return NULL;
    }
    memcpy(out, tail, len);
    out[len] = '\0';
    return out;
}

static cJSON *read_json(httpd_req_t *req)
{
    if (req->content_len == 0 || req->content_len > BODY_MAX) {
        return NULL;
    }
    char *buf = malloc(req->content_len + 1);
    if (!buf) {
        return NULL;
    }
    size_t got = 0;
    while (got < req->content_len) {
        int r = httpd_req_recv(req, buf + got, req->content_len - got);
        if (r <= 0) {
            free(buf);
            return NULL;
        }
        got += r;
    }
    buf[got] = '\0';
    cJSON *j = cJSON_Parse(buf);
    free(buf);
    return j;
}

/* ── English Tutor ─────────────────────────────────────────── */

static esp_err_t get_lesson(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", lesson_json());
}

/* POST /lesson/start {course, explain, speed, minutes} · /lesson/stop · /lesson/topic */
static esp_err_t post_lesson(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char action[8];
    const char *a = path_tail(req, PREFIX "lesson/", action, sizeof(action));
    if (a && !strcmp(a, "stop")) {
        lesson_stop();
        return api_send_ok(req);
    }
    if (a && !strcmp(a, "topic")) {
        return lesson_change_topic() ? api_send_ok(req) : api_send_error(req, "409 Conflict", "NOT_ACTIVE");
    }
    if (!a || strcmp(a, "start")) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (!secret_exists(SECRET_OPENAI_KEY)) {
        return api_send_error(req, "409 Conflict", "NO_API_KEY");
    }
    if (!net_is_connected()) {
        return api_send_error(req, "409 Conflict", "NO_WIFI");
    }
    cJSON *body = req->content_len ? read_json(req) : NULL;
    if (req->content_len && !body) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    lesson_cfg_t cfg;
    bool ok = lesson_parse_cfg(body, &cfg);
    cJSON_Delete(body);
    if (!ok) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    if (live_voice_active()) {
        return api_send_error(req, "409 Conflict", "VOICE_ACTIVE");
    }
    if (lesson_start(&cfg) != ESP_OK) {
        return api_send_error(req, "409 Conflict", "BUSY");
    }
    return api_send_json(req, "200 OK", lesson_json());
}

/* ── Status and settings ──────────────────────────────────── */

static esp_err_t get_status(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", device_status());
}

static esp_err_t get_settings(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char group[16];
    cJSON *value = device_settings_get(path_tail(req, PREFIX "settings/", group, sizeof(group)));
    return value ? api_send_json(req, "200 OK", value) : api_send_error(req, "404 Not Found", "NOT_FOUND");
}

static esp_err_t put_settings(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char group[16];
    const char *g = path_tail(req, PREFIX "settings/", group, sizeof(group));
    cJSON *body = read_json(req);
    esp_err_t err = body ? device_settings_set(g, body) : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err == ESP_ERR_NOT_FOUND) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (err == ESP_ERR_INVALID_ARG) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    if (err == ESP_ERR_NOT_ALLOWED) {
        /* assistant group: trying to switch ai_provider to a provider with no key (docs/design-voice-saver-mode.md 11.1) */
        return api_send_error(req, "409 Conflict", "NO_API_KEY");
    }
    if (err != ESP_OK) {
        return api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
    }
    return api_send_json(req, "200 OK", device_settings_get(g));
}

static esp_err_t get_voices(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *j = cJSON_CreateObject();
    cJSON_AddItemToObject(j, "voices", assistant_voice_list());
    return api_send_json(req, "200 OK", j);
}

/* ── Memories ─────────────────────────────────────────────── */

static esp_err_t get_memories(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", assistant_memories());
}

static esp_err_t delete_memory(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char key[40];
    const char *k = path_tail(req, PREFIX "memories/", key, sizeof(key));
    esp_err_t err = k ? assistant_forget(k) : ESP_ERR_INVALID_ARG;
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "400 Bad Request", "INVALID_ARG");
}

/* ── Deleting secrets (writes over BLE only) ──────────────── */

static void secrets_changed(void)
{
    const app_setting_t key = APP_SETTING_SECRETS;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
}

static esp_err_t delete_key(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char name[24];
    secret_id_t id;
    if (!device_secret_from_name(path_tail(req, PREFIX "keys/", name, sizeof(name)), &id)) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    if (secret_erase(id) != ESP_OK) {
        return api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
    }
    secrets_changed();
    return api_send_ok(req);
}

static esp_err_t delete_spotify(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    /* Logout reveals no secret, so it is allowed over LAN too (D6). Login is only via BLE spotify.link */
    return spotify_logout() == ESP_OK ? api_send_ok(req) : api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
}

static esp_err_t get_spotify(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", spotify_status_json());
}

/* ── Actions ──────────────────────────────────────────────── */

static esp_err_t post_voice(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char action[8];
    const char *a = path_tail(req, PREFIX "voice/", action, sizeof(action));
    if (a && !strcmp(a, "stop")) {
        live_voice_stop();
        return api_send_ok(req);
    }
    if (!a || strcmp(a, "start")) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (!secret_exists(SECRET_OPENAI_KEY)) {
        return api_send_error(req, "409 Conflict", "NO_API_KEY");
    }
    if (!net_is_connected()) {
        return api_send_error(req, "409 Conflict", "NO_WIFI");
    }
    return live_voice_start() == ESP_OK ? api_send_ok(req) : api_send_error(req, "409 Conflict", "BUSY");
}

static esp_err_t post_test_tone(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    audio_core_tone();
    return api_send_ok(req);
}

static esp_err_t post_wake_test(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    if (live_voice_active()) {
        return api_send_error(req, "409 Conflict", "VOICE_ACTIVE");
    }
    wake_test(true);
    return api_send_ok(req);
}

static void reboot_cb(void *arg)
{
    esp_restart();
}

static esp_err_t post_reboot(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    if (live_voice_active()) {
        return api_send_error(req, "409 Conflict", "VOICE_ACTIVE");
    }
    /* Reboot after sending the response */
    const esp_timer_create_args_t args = {.callback = reboot_cb, .name = "reboot"};
    esp_timer_handle_t t;
    if (esp_timer_create(&args, &t) == ESP_OK) {
        esp_timer_start_once(t, 500 * 1000);
    }
    return api_send_ok(req);
}

/* ── Radio and music (Phase 3) ────────────────────────────── */

static esp_err_t get_presets_body(httpd_req_t *req)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddItemToObject(j, "presets", radio_presets_get());
    return api_send_json(req, "200 OK", j);
}

static esp_err_t get_presets(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return get_presets_body(req);
}

static esp_err_t put_presets(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *body = read_json(req);
    esp_err_t err = radio_presets_set(cJSON_GetObjectItemCaseSensitive(body, "presets"));
    cJSON_Delete(body);
    if (err == ESP_ERR_INVALID_ARG) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    return err == ESP_OK ? get_presets_body(req) : api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
}

static esp_err_t post_media_play(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *body = read_json(req);
    const cJSON *preset = cJSON_GetObjectItemCaseSensitive(body, "preset");
    const cJSON *url = cJSON_GetObjectItemCaseSensitive(body, "url");
    const cJSON *title = cJSON_GetObjectItemCaseSensitive(body, "title");
    esp_err_t err = ESP_ERR_INVALID_ARG;
    if (cJSON_IsNumber(preset)) {
        err = radio_play_preset(preset->valueint);
    } else if (cJSON_IsString(url)) {
        err = radio_play_url(url->valuestring, cJSON_IsString(title) ? title->valuestring : NULL);
    }
    cJSON_Delete(body);
    if (err == ESP_ERR_INVALID_ARG || err == ESP_ERR_NOT_FOUND) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "503 Service Unavailable", "BUSY");
}

/* There is only one web server task, so doing Spotify HTTPS (up to tens of seconds) here would stall the whole LAN API.
 * Hand it to the tool worker and return 202 right away. The result arrives as a media_state event */
static void spotify_control_job(void *arg)
{
    char *action = arg;
    spotify_control(action);
    free(action);
    cJSON *now = spotify_now_json();    /* refresh the cache */
    const cJSON *state = cJSON_GetObjectItem(now, "state");
    const char *st = cJSON_IsString(state) ? state->valuestring : "stopped";
    app_media_event_t evt = {
        .source = MEDIA_SOURCE_SPOTIFY,
        .state = !strcmp(st, "playing") ? MEDIA_PLAYING : (!strcmp(st, "paused") ? MEDIA_PAUSED : MEDIA_STOPPED),
    };
    cJSON_Delete(now);
    app_events_post(APP_EVT_MEDIA_STATE, &evt, sizeof(evt), 0);
}

static void spotify_refresh_job(void *arg)
{
    cJSON_Delete(spotify_now_json());
}

static esp_err_t post_media_action(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char action[12];
    const char *a = path_tail(req, PREFIX "media/", action, sizeof(action));
    if (a && !strcmp(a, "play")) {
        return post_media_play(req);
    }
    esp_err_t err;
    if (!a) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (!radio_is_active() && spotify_linked() &&
        (!strcmp(a, "pause") || !strcmp(a, "resume") || !strcmp(a, "stop") || !strcmp(a, "next") || !strcmp(a, "previous"))) {
        char *action = strdup(a);
        if (!action || !assistant_queue_work(spotify_control_job, action)) {
            free(action);
            return api_send_error(req, "503 Service Unavailable", "BUSY");
        }
        cJSON *j = cJSON_CreateObject();
        cJSON_AddBoolToObject(j, "ok", true);
        cJSON_AddBoolToObject(j, "queued", true);
        return api_send_json(req, "202 Accepted", j);
    } else if (!strcmp(a, "pause")) {
        err = radio_pause();
    } else if (!strcmp(a, "resume")) {
        err = radio_resume();
    } else if (!strcmp(a, "stop")) {
        err = radio_is_active() ? radio_stop() : ESP_ERR_INVALID_STATE;
    } else if (!strcmp(a, "next") || !strcmp(a, "previous")) {
        err = radio_is_active() ? radio_step(!strcmp(a, "next") ? 1 : -1) : ESP_ERR_INVALID_STATE;
    } else {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (err == ESP_ERR_INVALID_STATE) {
        return api_send_error(req, "409 Conflict", "NOT_PLAYING");
    }
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "503 Service Unavailable", "BUSY");
}

static esp_err_t get_media_now(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    /* Radio comes first. If it is off, return Spotify's last state right away and fetch the new state in the background */
    if (radio_is_active() || !spotify_linked()) {
        return api_send_json(req, "200 OK", radio_now_json());
    }
    assistant_queue_work(spotify_refresh_job, NULL);
    return api_send_json(req, "200 OK", spotify_now_cached());
}

/* ── Telegram (Phase 4) ───────────────────────────────────── */

static bool parse_chat_id(httpd_req_t *req, int64_t *out)
{
    char id[24];
    const char *t = path_tail(req, PREFIX "telegram/chats/", id, sizeof(id));
    if (!t) {
        return false;
    }
    char *end = NULL;
    long long v = strtoll(t, &end, 10);
    if (!end || *end || v == 0) {
        return false;
    }
    *out = v;
    return true;
}

static esp_err_t get_tg_chats(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *j = cJSON_CreateObject();
    cJSON_AddItemToObject(j, "chats", telegram_chats());
    cJSON_AddStringToObject(j, "state", telegram_state_name(telegram_state()));
    cJSON_AddStringToObject(j, "bot", telegram_bot_username());
    cJSON_AddNumberToObject(j, "unread", telegram_unread());
    return api_send_json(req, "200 OK", j);
}

static esp_err_t put_tg_chat(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    int64_t id;
    cJSON *body = read_json(req);
    const cJSON *alias = cJSON_GetObjectItemCaseSensitive(body, "alias");
    esp_err_t err = parse_chat_id(req, &id) && cJSON_IsString(alias) ? telegram_chat_rename(id, alias->valuestring)
                                                                     : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err == ESP_ERR_NOT_FOUND) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "400 Bad Request", "INVALID_ARG");
}

static esp_err_t delete_tg_chat(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    int64_t id;
    esp_err_t err = parse_chat_id(req, &id) ? telegram_chat_remove(id) : ESP_ERR_NOT_FOUND;
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "404 Not Found", "NOT_FOUND");
}

static esp_err_t post_tg_pair(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char code[7];
    if (telegram_begin_pairing(code) != ESP_OK) {
        return api_send_error(req, "409 Conflict", "NO_TOKEN");
    }
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "code", code);
    cJSON_AddNumberToObject(j, "expires_s", 300);
    cJSON_AddStringToObject(j, "bot", telegram_bot_username());     /* in a group, the code is /pair@botname */
    return api_send_json(req, "200 OK", j);
}

static esp_err_t get_tg_options(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", telegram_options());
}

static esp_err_t put_tg_options(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *body = read_json(req);
    esp_err_t err = body ? telegram_options_set(body) : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err == ESP_ERR_INVALID_ARG) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    return err == ESP_OK ? api_send_json(req, "200 OK", telegram_options())
                         : api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
}

/* ── Notes and schedule (notes, docs/design-notes-schedule.md 2nd edition, Section 6) ─ */

/* GET ?since=<rev>: rev ascending, deleted records included. It can be a large array, so it skips the cJSON tree
 * (notes_api_since_text returns a PSRAM buffer directly, protecting internal RAM) */
static esp_err_t get_notes(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    uint32_t since = 0;
    char qs[32], val[16];
    if (httpd_req_get_url_query_str(req, qs, sizeof(qs)) == ESP_OK &&
        httpd_query_key_value(qs, "since", val, sizeof(val)) == ESP_OK) {
        since = (uint32_t)strtoul(val, NULL, 10);
    }
    char *text = notes_api_since_text(since);
    if (!text) {
        return api_send_error(req, "500 Internal Server Error", "STORAGE_FAIL");
    }
    httpd_resp_set_status(req, "200 OK");
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    esp_err_t err = httpd_resp_sendstr(req, text);
    free(text);
    return err;
}

static esp_err_t post_notes(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *body = read_json(req);
    cJSON *note = NULL;
    esp_err_t err = body ? notes_api_create(body, &note) : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err == ESP_ERR_INVALID_SIZE) {
        return api_send_error(req, "409 Conflict", "FULL");
    }
    return err == ESP_OK ? api_send_json(req, "201 Created", note) : api_send_error(req, "400 Bad Request", "INVALID_ARG");
}

static esp_err_t put_notes_item(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char id[16];
    const char *p = path_tail(req, PREFIX "notes/", id, sizeof(id));
    cJSON *body = read_json(req);
    cJSON *note = NULL, *conflict = NULL;
    esp_err_t err = (p && body) ? notes_api_update(p, body, &note, &conflict) : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err == ESP_ERR_NOT_FOUND) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    if (err == ESP_ERR_INVALID_STATE) {
        /* 409: add the latest item to the same {"error":...} shape as api_send_error */
        cJSON *j = cJSON_CreateObject();
        cJSON_AddStringToObject(j, "error", "CONFLICT");
        cJSON_AddItemToObject(j, "note", conflict);
        return api_send_json(req, "409 Conflict", j);
    }
    return err == ESP_OK ? api_send_json(req, "200 OK", note) : api_send_error(req, "400 Bad Request", "INVALID_ARG");
}

static esp_err_t delete_notes_item(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char id[16];
    const char *p = path_tail(req, PREFIX "notes/", id, sizeof(id));
    cJSON *result = NULL;
    esp_err_t err = p ? notes_api_delete(p, &result) : ESP_ERR_NOT_FOUND;
    return err == ESP_OK ? api_send_json(req, "200 OK", result) : api_send_error(req, "404 Not Found", "NOT_FOUND");
}

/* POST /notes/{id}/restore (there is no other POST notes/{wildcard} handler) */
static esp_err_t post_notes_item(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char tail[32];
    const char *t = path_tail(req, PREFIX "notes/", tail, sizeof(tail));
    static const char SUFFIX[] = "/restore";
    size_t slen = sizeof(SUFFIX) - 1, tlen = t ? strlen(t) : 0;
    if (!t || tlen <= slen || strcmp(t + tlen - slen, SUFFIX) || tlen - slen >= 16) {
        return api_send_error(req, "404 Not Found", "NOT_FOUND");
    }
    char id[16];
    memcpy(id, t, tlen - slen);
    id[tlen - slen] = '\0';
    cJSON *note = NULL;
    esp_err_t err = notes_api_restore(id, &note);
    return err == ESP_OK ? api_send_json(req, "200 OK", note) : api_send_error(req, "404 Not Found", "NOT_FOUND");
}

static esp_err_t get_notes_settings(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    return api_send_json(req, "200 OK", notes_settings_get());
}

static esp_err_t put_notes_settings(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    cJSON *body = read_json(req);
    esp_err_t err = body ? notes_settings_set(body) : ESP_ERR_INVALID_ARG;
    cJSON_Delete(body);
    if (err != ESP_OK) {
        return api_send_error(req, "400 Bad Request", "INVALID_ARG");
    }
    return api_send_json(req, "200 OK", notes_settings_get());
}

/* ── Phones ───────────────────────────────────────────────── */

static esp_err_t get_phones(httpd_req_t *req)
{
    char self[PHONE_ID_MAX + 1] = {0};
    if (!api_authorize(req, self)) {
        return ESP_OK;
    }
    cJSON *j = cJSON_CreateObject();
    cJSON_AddItemToObject(j, "phones", phones_list(self));
    return api_send_json(req, "200 OK", j);
}

static esp_err_t delete_phone(httpd_req_t *req)
{
    if (!api_authorize(req, NULL)) {
        return ESP_OK;
    }
    char id[PHONE_ID_MAX + 1];
    const char *p = path_tail(req, PREFIX "system/phones/", id, sizeof(id));
    esp_err_t err = p ? phones_revoke(p) : ESP_ERR_NOT_FOUND;
    return err == ESP_OK ? api_send_ok(req) : api_send_error(req, "404 Not Found", "NOT_FOUND");
}

/* ── Server ───────────────────────────────────────────────── */

static void on_close(httpd_handle_t hd, int sockfd)
{
    api_events_on_close(sockfd);
    close(sockfd);      /* when close_fn is set, we must close the socket ourselves */
}

esp_err_t local_api_start(void)
{
    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.server_port = APP_HTTP_PORT;
    cfg.uri_match_fn = httpd_uri_match_wildcard;
    cfg.max_uri_handlers = 36;
    /* Socket budget: httpd 7 + TLS 3 (OpenAI, Telegram, Spotify) + mDNS etc. ≤ LWIP_MAX_SOCKETS(16) */
    cfg.max_open_sockets = 7;
    cfg.lru_purge_enable = true;
    cfg.stack_size = 8192;
    cfg.task_caps = MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT;   /* stack in PSRAM (Chapter 7, Section 7.3) */
    cfg.core_id = 0;
    cfg.close_fn = on_close;

    esp_err_t err = httpd_start(&s_server, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "httpd start: %s", esp_err_to_name(err));
        return err;
    }
    const httpd_uri_t routes[] = {
        {.uri = PREFIX "status", .method = HTTP_GET, .handler = get_status},
        {.uri = PREFIX "settings/*", .method = HTTP_GET, .handler = get_settings},
        {.uri = PREFIX "settings/*", .method = HTTP_PUT, .handler = put_settings},
        {.uri = PREFIX "voices", .method = HTTP_GET, .handler = get_voices},
        {.uri = PREFIX "memories", .method = HTTP_GET, .handler = get_memories},
        {.uri = PREFIX "memories/*", .method = HTTP_DELETE, .handler = delete_memory},
        {.uri = PREFIX "keys/*", .method = HTTP_DELETE, .handler = delete_key},
        {.uri = PREFIX "spotify", .method = HTTP_DELETE, .handler = delete_spotify},
        {.uri = PREFIX "spotify", .method = HTTP_GET, .handler = get_spotify},
        {.uri = PREFIX "voice/*", .method = HTTP_POST, .handler = post_voice},
        {.uri = PREFIX "audio/test-tone", .method = HTTP_POST, .handler = post_test_tone},
        {.uri = PREFIX "wake/test", .method = HTTP_POST, .handler = post_wake_test},
        {.uri = PREFIX "system/reboot", .method = HTTP_POST, .handler = post_reboot},
        {.uri = PREFIX "radio/presets", .method = HTTP_GET, .handler = get_presets},
        {.uri = PREFIX "radio/presets", .method = HTTP_PUT, .handler = put_presets},
        {.uri = PREFIX "media/now", .method = HTTP_GET, .handler = get_media_now},
        {.uri = PREFIX "media/*", .method = HTTP_POST, .handler = post_media_action},
        {.uri = PREFIX "telegram/chats", .method = HTTP_GET, .handler = get_tg_chats},
        {.uri = PREFIX "telegram/chats/*", .method = HTTP_PUT, .handler = put_tg_chat},
        {.uri = PREFIX "telegram/chats/*", .method = HTTP_DELETE, .handler = delete_tg_chat},
        {.uri = PREFIX "telegram/pair", .method = HTTP_POST, .handler = post_tg_pair},
        {.uri = PREFIX "telegram/options", .method = HTTP_GET, .handler = get_tg_options},
        {.uri = PREFIX "telegram/options", .method = HTTP_PUT, .handler = put_tg_options},
        {.uri = PREFIX "lesson", .method = HTTP_GET, .handler = get_lesson},
        {.uri = PREFIX "lesson/*", .method = HTTP_POST, .handler = post_lesson},
        {.uri = PREFIX "system/phones", .method = HTTP_GET, .handler = get_phones},
        {.uri = PREFIX "system/phones/*", .method = HTTP_DELETE, .handler = delete_phone},
        {.uri = PREFIX "notes", .method = HTTP_GET, .handler = get_notes},
        {.uri = PREFIX "notes", .method = HTTP_POST, .handler = post_notes},
        {.uri = PREFIX "notes/settings", .method = HTTP_GET, .handler = get_notes_settings},
        /* Register "notes/settings" first: httpd_find_uri_handler uses the first match in registration order, so
         * this keeps the later wildcard pattern from capturing this route on PUT */
        {.uri = PREFIX "notes/settings", .method = HTTP_PUT, .handler = put_notes_settings},
        {.uri = PREFIX "notes/*", .method = HTTP_PUT, .handler = put_notes_item},
        {.uri = PREFIX "notes/*", .method = HTTP_DELETE, .handler = delete_notes_item},
        {.uri = PREFIX "notes/*", .method = HTTP_POST, .handler = post_notes_item},
    };
    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        ESP_ERROR_CHECK(httpd_register_uri_handler(s_server, &routes[i]));
    }
    ESP_ERROR_CHECK(api_events_register(s_server));
    ESP_LOGI(TAG, "LAN API on port %d", APP_HTTP_PORT);
    return ESP_OK;
}
