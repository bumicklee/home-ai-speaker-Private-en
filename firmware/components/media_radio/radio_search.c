/*
 * Station search via Radio-Browser (https://www.radio-browser.info) (RAD-02).
 * "재즈 라디오 틀어 줘" (play jazz radio) → if no preset has jazz, search here with tag=jazz.
 * Picks up to 3 stations, by popularity (clickcount), that look playable by this player (direct MP3/AAC streams).
 * The URL alone doesn't always reveal HLS (a playlist that contains HLS), so if the player fails it moves to the next candidate.
 * The response is external data, so it is not logged (station names only).
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app_config.h"
#include "cJSON.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "media_radio.h"
#include "radio_internal.h"

static const char *TAG = "RADIO_SEARCH";

#define API_HOST     "https://de1.api.radio-browser.info"
#define RESPONSE_MAX (24 * 1024)

typedef struct {
    char *buf;
    size_t used;
} body_t;

static esp_err_t on_http(esp_http_client_event_t *evt)
{
    body_t *b = evt->user_data;
    if (evt->event_id == HTTP_EVENT_ON_DATA && b->used + evt->data_len < RESPONSE_MAX) {
        memcpy(b->buf + b->used, evt->data, evt->data_len);
        b->used += evt->data_len;
    }
    return ESP_OK;
}

static void url_encode(const char *in, char *out, size_t out_len)
{
    static const char hex[] = "0123456789ABCDEF";
    size_t o = 0;
    for (; *in && o + 4 < out_len; in++) {
        unsigned char c = (unsigned char)*in;
        if (isalnum(c) || c == '-' || c == '_' || c == '.') {
            out[o++] = (char)c;
        } else {
            out[o++] = '%';
            out[o++] = hex[c >> 4];
            out[o++] = hex[c & 15];
        }
    }
    out[o] = '\0';
}

static bool playable(const cJSON *s)
{
    const cJSON *codec = cJSON_GetObjectItem(s, "codec");
    const cJSON *url = cJSON_GetObjectItem(s, "url_resolved");
    if (!cJSON_IsString(codec) || !cJSON_IsString(url) || strlen(url->valuestring) > RADIO_URL_MAX) {
        return false;
    }
    const char *u = url->valuestring;
    bool http = !strncmp(u, "http://", 7) || !strncmp(u, "https://", 8);
    /* Also drop what Radio-Browser marks as HLS (some stations are HLS without .m3u8 in the URL, real board 2026-10-03) */
    const cJSON *hls_flag = cJSON_GetObjectItem(s, "hls");
    bool hls = strstr(u, ".m3u8") != NULL || (cJSON_IsNumber(hls_flag) && hls_flag->valueint != 0);
    bool codec_ok = !strcmp(codec->valuestring, "MP3") || !strncmp(codec->valuestring, "AAC", 3);
    return http && !hls && codec_ok;
}

esp_err_t radio_search(const char *query, bool by_tag, radio_station_t *out, int max, int *found)
{
    *found = 0;
    if (!query || !query[0] || strlen(query) > 64 || max < 1) {
        return ESP_ERR_INVALID_ARG;
    }
    char encoded[200], request[320];
    url_encode(query, encoded, sizeof(encoded));
    snprintf(request, sizeof(request),
             API_HOST "/json/stations/search?%s=%s&hidebroken=true&order=clickcount&reverse=true&limit=10",
             by_tag ? "tag" : "name", encoded);

    body_t body = {.buf = heap_caps_malloc(RESPONSE_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)};
    if (!body.buf) {
        return ESP_ERR_NO_MEM;
    }
    const esp_http_client_config_t cfg = {
        .url = request,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 8000,
        .user_agent = RADIO_USER_AGENT,
        .event_handler = on_http,
        .user_data = &body,
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    esp_err_t err = client ? esp_http_client_perform(client) : ESP_ERR_NO_MEM;
    int status = client ? esp_http_client_get_status_code(client) : 0;
    if (client) {
        esp_http_client_cleanup(client);
    }
    if (err == ESP_OK && status != 200) {
        err = ESP_FAIL;
    }
    cJSON *list = NULL;
    if (err == ESP_OK) {
        body.buf[body.used] = '\0';
        list = cJSON_Parse(body.buf);
    }
    free(body.buf);

    const cJSON *s;
    cJSON_ArrayForEach(s, list) {
        if (*found >= max) {
            break;
        }
        if (playable(s)) {
            radio_station_t *o = &out[(*found)++];
            strlcpy(o->url, cJSON_GetObjectItem(s, "url_resolved")->valuestring, sizeof(o->url));
            const cJSON *n = cJSON_GetObjectItem(s, "name");
            strlcpy(o->name, cJSON_IsString(n) ? n->valuestring : query, sizeof(o->name));
        }
    }
    cJSON_Delete(list);
    ESP_LOGI(TAG, "%s \"%s\": %d candidate(s)%s%s", by_tag ? "tag" : "name", query, *found,
             *found ? ", first " : "", *found ? out[0].name : "");
    return *found ? ESP_OK : ESP_ERR_NOT_FOUND;
}
