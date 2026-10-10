/*
 * Internet radio player (design document Section 2.9, RAD-01/03/04/05/06).
 *
 * Flow (a single radio task does it all):
 *   HTTP(S) connect → (follow redirects) → if a playlist, reopen the first URL → strip ICY metadata
 *   → decode MP3/AAC → mix down to mono → convert to the output rate → audio_core music channel
 *
 * When the music buffer is full, audio_core_music_write() waits, so the download speed matches the playback speed.
 * On a drop, reconnect 5 times at intervals doubling from 1 s up to 30 s; if that still fails, stop and play the alert tone.
 *
 * Why esp_http_client is used directly instead of the ESP-GMF player (esp_audio_simple_player):
 * this file has to handle playlists, ICY, reconnects and redirects, and how much of that GMF supports was not confirmed
 * (an alternative allowed by design document Section 2.9). Decoding uses the same esp_audio_codec library.
 */
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "app_config.h"
#include "audio_core.h"
#include "esp_ae_rate_cvt.h"
#include "esp_aac_dec.h"
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec.h"
#include "esp_audio_simple_dec_default.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "media_radio.h"
#include "nvs.h"
#include "radio_internal.h"

static const char *TAG = "RADIO";

#define READ_CHUNK        4096
#define PLAYLIST_MAX      8192
#define PCM_MAX_SAMPLES   4608      /* max per decode call (HE-AAC 2048 × 2 channels, with margin) */
#define MAX_REDIRECTS     5
#define MAX_PLAYLIST_HOPS 3
#define MAX_RETRIES       5
#define RETRY_MIN_MS      1000
#define RETRY_MAX_MS      30000
#define STABLE_MS         10000     /* after playing cleanly this long, reset the retry count to 0 */
#define PLAYING_AFTER_MS  300       /* once this much is buffered, state is "playing" */
#define DECODE_ERR_LIMIT  50
#define STATS_MS          10000     /* playback diagnostic log interval */

typedef enum {
    CMD_PLAY,
    CMD_STOP,
    CMD_PAUSE,
    CMD_RESUME,
} cmd_type_t;

typedef struct {
    cmd_type_t type;
    int preset;
    char url[RADIO_URL_MAX + 1];
    char title[RADIO_NAME_MAX + 1];
} radio_cmd_t;

typedef enum {
    STREAM_ABORTED,         /* stopped because a new command arrived */
    STREAM_ENDED,           /* server closed → reconnect */
    STREAM_FAILED,          /* connect/decode failure → reconnect */
    STREAM_UNSUPPORTED,     /* HLS, Ogg, etc. → no retry */
} stream_result_t;

/* Values collected from the HTTP response headers */
typedef struct {
    char content_type[64];
    int metaint;
    char icy_name[RADIO_NAME_MAX + 1];
    int icy_br;
} stream_headers_t;

/* ICY metadata stripping state */
typedef struct {
    int metaint;
    int until_meta;
    int meta_left;
    int meta_used;
    char meta[4081];        /* max 255 × 16 */
} icy_t;

static QueueHandle_t s_cmds;
static SemaphoreHandle_t s_lock;
static radio_status_t s_status = {.state = MEDIA_STOPPED, .preset = -1};
static char s_url[RADIO_URL_MAX + 1];

/*
 * Remaining search candidates (tried in turn when the first can't be played). PSRAM.
 * s_pending_*: filled by the caller inside s_lock before queuing the command. s_alts: used only by the radio task.
 */
static radio_station_t *s_pending_alts, *s_alts;
static int s_pending_alt_count, s_alt_count, s_alt_next;

/* Buffers used by the playback task (PSRAM, allocated once at start) */
static uint8_t *s_read_buf, *s_audio_buf, *s_dec_buf;
static uint32_t s_dec_buf_size;
static int16_t *s_mono, *s_resampled;
static uint32_t s_resampled_cap;
static icy_t *s_icy;

/* ── State ────────────────────────────────────────────────── */

static void post_state(void)
{
    app_media_event_t evt = {.source = MEDIA_SOURCE_RADIO, .state = s_status.state};
    if (s_status.state == MEDIA_STOPPED) {
        evt.source = MEDIA_SOURCE_NONE;
    }
    app_events_post(APP_EVT_MEDIA_STATE, &evt, sizeof(evt), 0);
}

static void set_state(media_play_state_t state)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    bool changed = s_status.state != state;
    s_status.state = state;
    if (state == MEDIA_STOPPED) {
        s_status.icy_title[0] = '\0';
    }
    xSemaphoreGive(s_lock);
    if (changed) {
        ESP_LOGI(TAG, "state %d", state);
        post_state();
    }
}

void radio_get_status(radio_status_t *out)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    *out = s_status;
    xSemaphoreGive(s_lock);
}

bool radio_is_active(void)
{
    radio_status_t st;
    radio_get_status(&st);
    return st.state != MEDIA_STOPPED;
}

cJSON *radio_now_json(void)
{
    radio_status_t st;
    radio_get_status(&st);
    static const char *const names[] = {"stopped", "buffering", "playing", "paused"};
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "source", st.state == MEDIA_STOPPED ? "none" : "radio");
    cJSON_AddStringToObject(j, "state", names[st.state]);
    /* ICY titles are usually "Artist - Title" */
    char artist[128] = "", title[128];
    strlcpy(title, st.icy_title, sizeof(title));
    char *dash = strstr(st.icy_title, " - ");
    if (dash) {
        size_t n = dash - st.icy_title;
        memcpy(artist, st.icy_title, n < sizeof(artist) - 1 ? n : sizeof(artist) - 1);
        artist[n < sizeof(artist) - 1 ? n : sizeof(artist) - 1] = '\0';
        strlcpy(title, dash + 3, sizeof(title));
    }
    cJSON_AddStringToObject(j, "title", title);
    cJSON_AddStringToObject(j, "artist", artist);
    cJSON_AddStringToObject(j, "station", st.station);
    if (st.preset >= 0) {
        cJSON_AddNumberToObject(j, "preset", st.preset);
    }
    if (st.bitrate_kbps) {
        cJSON_AddNumberToObject(j, "bitrate_kbps", st.bitrate_kbps);
    }
    return j;
}

/* ── Last station (NVS media) ─────────────────────────────── */

static void save_last(const char *url, const char *title, int preset)
{
    nvs_handle_t h;
    if (nvs_open("media", NVS_READWRITE, &h) != ESP_OK) {
        return;
    }
    nvs_set_u8(h, "last_source", MEDIA_SOURCE_RADIO);
    nvs_set_u8(h, "last_preset", preset < 0 ? 0xFF : (uint8_t)preset);
    nvs_set_str(h, "last_url", url);
    nvs_set_str(h, "last_title", title);
    nvs_commit(h);
    nvs_close(h);
}

/* ── Commands ─────────────────────────────────────────────── */

static esp_err_t send_cmd(cmd_type_t type, int preset, const char *url, const char *title,
                          const radio_station_t *alts, int alt_count)
{
    radio_cmd_t cmd = {.type = type, .preset = preset};
    if (url) {
        if (strlen(url) > RADIO_URL_MAX || (strncmp(url, "http://", 7) && strncmp(url, "https://", 8))) {
            return ESP_ERR_INVALID_ARG;
        }
        strlcpy(cmd.url, url, sizeof(cmd.url));
    }
    strlcpy(cmd.title, title ? title : "", sizeof(cmd.title));
    if (type == CMD_PLAY) {
        save_last(cmd.url, cmd.title, preset);
        /* Replace the candidates on every new play (preset/URL play has 0 candidates) */
        xSemaphoreTake(s_lock, portMAX_DELAY);
        s_pending_alt_count = alt_count;
        if (alt_count > 0) {
            memcpy(s_pending_alts, alts, alt_count * sizeof(*alts));
        }
        xSemaphoreGive(s_lock);
    }
    /* If older commands are queued, only the latest one matters */
    if (xQueueSend(s_cmds, &cmd, pdMS_TO_TICKS(100)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    return ESP_OK;
}

esp_err_t radio_play_url(const char *url, const char *title)
{
    return send_cmd(CMD_PLAY, -1, url, title && title[0] ? title : "Radio", NULL, 0);
}

esp_err_t radio_play_stations(const radio_station_t *list, int count)
{
    if (!list || count < 1 || count > RADIO_SEARCH_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_cmd(CMD_PLAY, -1, list[0].url, list[0].name[0] ? list[0].name : "Radio", list + 1, count - 1);
}

esp_err_t radio_play_preset(int index)
{
    char url[RADIO_URL_MAX + 1], name[RADIO_NAME_MAX + 1];
    if (!radio_presets_entry(index, url, sizeof(url), name, sizeof(name))) {
        return ESP_ERR_NOT_FOUND;
    }
    return send_cmd(CMD_PLAY, index, url, name, NULL, 0);
}

esp_err_t radio_play_last(void)
{
    char url[RADIO_URL_MAX + 1] = "", title[RADIO_NAME_MAX + 1] = "";
    uint8_t preset = 0xFF;
    nvs_handle_t h;
    if (nvs_open("media", NVS_READONLY, &h) == ESP_OK) {
        size_t len = sizeof(url);
        nvs_get_str(h, "last_url", url, &len);
        len = sizeof(title);
        nvs_get_str(h, "last_title", title, &len);
        nvs_get_u8(h, "last_preset", &preset);
        nvs_close(h);
    }
    if (preset != 0xFF && preset < radio_presets_count()) {
        return radio_play_preset(preset);
    }
    if (url[0]) {
        return radio_play_url(url, title);
    }
    return radio_play_preset(0);
}

esp_err_t radio_stop(void)
{
    return send_cmd(CMD_STOP, -1, NULL, NULL, NULL, 0);
}

esp_err_t radio_pause(void)
{
    return radio_is_active() ? send_cmd(CMD_PAUSE, -1, NULL, NULL, NULL, 0) : ESP_ERR_INVALID_STATE;
}

esp_err_t radio_resume(void)
{
    radio_status_t st;
    radio_get_status(&st);
    return st.state == MEDIA_PAUSED ? send_cmd(CMD_RESUME, -1, NULL, NULL, NULL, 0) : ESP_ERR_INVALID_STATE;
}

esp_err_t radio_step(int delta)
{
    int n = radio_presets_count();
    if (n == 0) {
        return ESP_ERR_NOT_FOUND;
    }
    radio_status_t st;
    radio_get_status(&st);
    int next = st.preset < 0 ? 0 : ((st.preset + delta) % n + n) % n;
    return radio_play_preset(next);
}

static bool abort_requested(void)
{
    return uxQueueMessagesWaiting(s_cmds) > 0;
}

/* ── HTTP ─────────────────────────────────────────────────── */

static esp_err_t on_http(esp_http_client_event_t *evt)
{
    stream_headers_t *h = evt->user_data;
    if (evt->event_id != HTTP_EVENT_ON_HEADER || !h) {
        return ESP_OK;
    }
    if (!strcasecmp(evt->header_key, "Content-Type")) {
        strlcpy(h->content_type, evt->header_value, sizeof(h->content_type));
    } else if (!strcasecmp(evt->header_key, "icy-metaint")) {
        h->metaint = atoi(evt->header_value);
    } else if (!strcasecmp(evt->header_key, "icy-name")) {
        strlcpy(h->icy_name, evt->header_value, sizeof(h->icy_name));
    } else if (!strcasecmp(evt->header_key, "icy-br")) {
        h->icy_br = atoi(evt->header_value);
    }
    return ESP_OK;
}

/* Connect and follow redirects. On success, a client in 200 state ready to read the body */
static bool abort_requested(void);

static esp_http_client_handle_t open_stream(const char *url, stream_headers_t *hdr, char *final_url, size_t final_len)
{
    const esp_http_client_config_t cfg = {
        .url = url,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 5000,     /* short, because stop commands can't be seen while connecting */
        .buffer_size = READ_CHUNK,
        .user_agent = RADIO_USER_AGENT,
        .disable_auto_redirect = true,  /* streaming mode, so we follow them ourselves */
        .event_handler = on_http,
        .user_data = hdr,
        .keep_alive_enable = false,
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    if (!client) {
        return NULL;
    }
    esp_http_client_set_header(client, "Icy-MetaData", "1");
    for (int hop = 0; hop <= MAX_REDIRECTS && !abort_requested(); hop++) {
        memset(hdr, 0, sizeof(*hdr));
        if (esp_http_client_open(client, 0) != ESP_OK) {
            break;
        }
        esp_http_client_fetch_headers(client);
        int status = esp_http_client_get_status_code(client);
        if (status == 200) {
            /* URL after following redirects (for checking the playlist extension) */
            if (esp_http_client_get_url(client, final_url, final_len) != ESP_OK) {
                strlcpy(final_url, url, final_len);
            }
            return client;
        }
        if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
            esp_http_client_set_redirection(client);
            esp_http_client_close(client);
            continue;
        }
        ESP_LOGW(TAG, "HTTP status %d", status);
        break;
    }
    esp_http_client_cleanup(client);
    return NULL;
}

static bool is_playlist_type(const char *content_type, const char *url)
{
    size_t n = strcspn(url, "?#");
    bool ext = (n > 4 && !strncasecmp(url + n - 4, ".pls", 4)) || (n > 4 && !strncasecmp(url + n - 4, ".m3u", 4));
    return ext || strcasestr(content_type, "scpls") || strcasestr(content_type, "mpegurl") ||
           strcasestr(content_type, "x-pls");
}

/* Find the first stream URL in a playlist body. HLS is not supported */
static stream_result_t parse_playlist(char *body, char *out, size_t out_len)
{
    if (strstr(body, "#EXT-X-")) {
        return STREAM_UNSUPPORTED;      /* HLS (.m3u8) */
    }
    for (char *line = strtok(body, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        char *p = strstr(line, "http");
        if (!strncasecmp(line, "File", 4) || line[0] == 'h') {
            if (p && (!strncmp(p, "http://", 7) || !strncmp(p, "https://", 8)) && strlen(p) <= RADIO_URL_MAX) {
                strlcpy(out, p, out_len);
                return STREAM_ENDED;    /* found (the caller reopens this URL) */
            }
        }
    }
    return STREAM_UNSUPPORTED;
}

/* ── ICY metadata ─────────────────────────────────────────── */

static void icy_parse_title(const char *meta)
{
    const char *start = strstr(meta, "StreamTitle='");
    if (!start) {
        return;
    }
    start += 13;
    const char *end = strstr(start, "';");
    if (!end) {
        end = start + strlen(start);
    }
    char title[128];
    size_t n = end - start < (int)sizeof(title) - 1 ? (size_t)(end - start) : sizeof(title) - 1;
    memcpy(title, start, n);
    title[n] = '\0';
    xSemaphoreTake(s_lock, portMAX_DELAY);
    bool changed = strcmp(s_status.icy_title, title) != 0;
    strlcpy(s_status.icy_title, title, sizeof(s_status.icy_title));
    xSemaphoreGive(s_lock);
    if (changed) {
        post_state();   /* update the app's "now playing" */
    }
}

/* Strip metadata from received bytes and leave only audio bytes in out */
static size_t icy_filter(icy_t *s, const uint8_t *in, size_t n, uint8_t *out)
{
    size_t i = 0, o = 0;
    while (i < n) {
        if (s->metaint <= 0) {
            memcpy(out + o, in + i, n - i);
            return o + (n - i);
        }
        if (s->meta_left > 0) {
            size_t take = (size_t)s->meta_left < n - i ? (size_t)s->meta_left : n - i;
            memcpy(s->meta + s->meta_used, in + i, take);
            s->meta_used += take;
            s->meta_left -= take;
            i += take;
            if (s->meta_left == 0) {
                s->meta[s->meta_used] = '\0';
                icy_parse_title(s->meta);
                s->until_meta = s->metaint;
            }
            continue;
        }
        if (s->until_meta == 0) {
            s->meta_left = in[i++] * 16;    /* length byte */
            s->meta_used = 0;
            if (s->meta_left == 0) {
                s->until_meta = s->metaint;
            }
            continue;
        }
        size_t take = (size_t)s->until_meta < n - i ? (size_t)s->until_meta : n - i;
        memcpy(out + o, in + i, take);
        o += take;
        i += take;
        s->until_meta -= take;
    }
    return o;
}

/* ── Decode → music channel ───────────────────────────────── */

typedef struct {
    esp_audio_simple_dec_handle_t dec;
    esp_ae_rate_cvt_handle_t cvt;
    uint32_t src_rate;
    uint32_t written_samples;
    int errors;
} decode_ctx_t;

static void decode_ctx_close(decode_ctx_t *d)
{
    if (d->dec) {
        esp_audio_simple_dec_close(d->dec);
    }
    if (d->cvt) {
        esp_ae_rate_cvt_close(d->cvt);
    }
    memset(d, 0, sizeof(*d));
}

/* Convert to mono at the output rate and feed the music channel. false if we must stop */
static bool push_pcm_chunk(decode_ctx_t *d, const int16_t *pcm, size_t frames, unsigned channels, uint32_t rate);

/* If the decoded output is larger than the work buffer, feed it in parts (don't truncate) */
static bool push_pcm(decode_ctx_t *d, const int16_t *pcm, size_t frames, unsigned channels, uint32_t rate)
{
    while (frames) {
        size_t n = frames > PCM_MAX_SAMPLES ? PCM_MAX_SAMPLES : frames;
        if (!push_pcm_chunk(d, pcm, n, channels, rate)) {
            return false;
        }
        pcm += n * channels;
        frames -= n;
    }
    return true;
}

static bool push_pcm_chunk(decode_ctx_t *d, const int16_t *pcm, size_t frames, unsigned channels, uint32_t rate)
{
    for (size_t i = 0; i < frames; i++) {
        int sum = 0;
        for (unsigned c = 0; c < channels; c++) {
            sum += pcm[i * channels + c];
        }
        s_mono[i] = (int16_t)(sum / (int)channels);     /* one mono speaker, so mix down */
    }
    const int16_t *out = s_mono;
    uint32_t out_n = frames;
    if (rate != AUDIO_SAMPLE_RATE) {
        if (d->cvt && d->src_rate != rate) {
            esp_ae_rate_cvt_close(d->cvt);
            d->cvt = NULL;
        }
        if (!d->cvt) {
            esp_ae_rate_cvt_cfg_t cfg = {
                .src_rate = rate,
                .dest_rate = AUDIO_SAMPLE_RATE,
                .channel = 1,
                .bits_per_sample = 16,
                .complexity = 2,
                .perf_type = ESP_AE_RATE_CVT_PERF_TYPE_SPEED,
            };
            if (esp_ae_rate_cvt_open(&cfg, &d->cvt) != ESP_AE_ERR_OK) {
                ESP_LOGE(TAG, "rate converter %lu -> %d failed", (unsigned long)rate, AUDIO_SAMPLE_RATE);
                return false;
            }
            d->src_rate = rate;
        }
        out_n = s_resampled_cap;
        if (esp_ae_rate_cvt_process(d->cvt, s_mono, frames, s_resampled, &out_n) != ESP_AE_ERR_OK) {
            return true;    /* drop just this chunk */
        }
        out = s_resampled;
    }
    for (size_t w = 0; w < out_n;) {
        if (abort_requested()) {
            return false;
        }
        w += audio_core_music_write(out + w, out_n - w, 100);
    }
    d->written_samples += out_n;
    if (d->written_samples >= AUDIO_SAMPLE_RATE * PLAYING_AFTER_MS / 1000) {
        set_state(MEDIA_PLAYING);
    }
    return true;
}

static bool decode_bytes(decode_ctx_t *d, uint8_t *data, size_t len)
{
    esp_audio_simple_dec_raw_t raw = {.buffer = data, .len = len};
    while (raw.len > 0) {
        esp_audio_simple_dec_out_t out = {.buffer = s_dec_buf, .len = s_dec_buf_size};
        esp_audio_err_t ret = esp_audio_simple_dec_process(d->dec, &raw, &out);
        if (ret == ESP_AUDIO_ERR_BUFF_NOT_ENOUGH) {
            uint8_t *bigger = heap_caps_realloc(s_dec_buf, out.needed_size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
            if (!bigger) {
                return false;
            }
            s_dec_buf = bigger;
            s_dec_buf_size = out.needed_size;
            continue;
        }
        if (ret != ESP_AUDIO_ERR_OK) {
            /* Corrupt frame: drop this chunk and move on. Reconnect if it keeps failing */
            return ++d->errors < DECODE_ERR_LIMIT;
        }
        d->errors = 0;
        raw.buffer += raw.consumed;
        raw.len -= raw.consumed;
        if (out.decoded_size) {
            esp_audio_simple_dec_info_t info = {0};
            esp_audio_simple_dec_get_info(d->dec, &info);
            unsigned ch = info.channel ? info.channel : 1;
            if (info.bits_per_sample != 16 || ch > 2) {
                return false;
            }
            if (!push_pcm(d, (const int16_t *)s_dec_buf, out.decoded_size / 2 / ch, ch, info.sample_rate)) {
                return false;
            }
        } else if (raw.consumed == 0) {
            break;      /* need more data */
        }
    }
    return true;
}

/* ── Play one stream ──────────────────────────────────────── */

static stream_result_t stream_once(const char *url, int depth, uint32_t *played_ms)
{
    if (abort_requested()) {
        return STREAM_ABORTED;
    }
    stream_headers_t hdr;
    char final_url[RADIO_URL_MAX + 1];
    esp_http_client_handle_t client = open_stream(url, &hdr, final_url, sizeof(final_url));
    if (!client) {
        return abort_requested() ? STREAM_ABORTED : STREAM_FAILED;
    }

    if (is_playlist_type(hdr.content_type, final_url)) {
        int n = esp_http_client_read(client, (char *)s_read_buf, PLAYLIST_MAX - 1);
        esp_http_client_cleanup(client);
        if (n <= 0 || depth >= MAX_PLAYLIST_HOPS) {
            return STREAM_FAILED;
        }
        s_read_buf[n] = '\0';
        char next[RADIO_URL_MAX + 1];
        stream_result_t r = parse_playlist((char *)s_read_buf, next, sizeof(next));
        if (r != STREAM_ENDED) {
            ESP_LOGW(TAG, "unsupported playlist (HLS?)");
            return r;
        }
        return stream_once(next, depth + 1, played_ms);
    }

    bool aac = strcasestr(hdr.content_type, "aac") != NULL;
    if (strcasestr(hdr.content_type, "ogg") || strcasestr(hdr.content_type, "opus")) {
        esp_http_client_cleanup(client);
        return STREAM_UNSUPPORTED;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (!s_status.station[0] && hdr.icy_name[0]) {
        strlcpy(s_status.station, hdr.icy_name, sizeof(s_status.station));
    }
    s_status.bitrate_kbps = hdr.icy_br;
    xSemaphoreGive(s_lock);

    decode_ctx_t d = {0};
    esp_aac_dec_cfg_t aac_cfg = {.aac_plus_enable = true};     /* HE-AAC (RAD-05) */
    esp_audio_simple_dec_cfg_t dec_cfg = {
        .dec_type = aac ? ESP_AUDIO_SIMPLE_DEC_TYPE_AAC : ESP_AUDIO_SIMPLE_DEC_TYPE_MP3,
        .dec_cfg = aac ? &aac_cfg : NULL,
        .cfg_size = aac ? sizeof(aac_cfg) : 0,
    };
    if (esp_audio_simple_dec_open(&dec_cfg, &d.dec) != ESP_AUDIO_ERR_OK) {
        esp_http_client_cleanup(client);
        return STREAM_FAILED;
    }
    memset(s_icy, 0, sizeof(*s_icy));
    s_icy->metaint = hdr.metaint;
    s_icy->until_meta = hdr.metaint;
    ESP_LOGI(TAG, "streaming %s (metaint %d, %d kbps)", aac ? "AAC" : "MP3", hdr.metaint, hdr.icy_br);

    stream_result_t result = STREAM_ENDED;
    /* Dropout diagnostics: receive rate vs station bitrate, buffer low-water mark, buffer-empty count, share of time waiting on the network */
    int64_t stat_since = esp_timer_get_time(), read_wait_us = 0;
    uint32_t stat_bytes = 0, buf_min = UINT32_MAX;
    unsigned underruns_base = audio_core_music_underruns();
    for (;;) {
        if (abort_requested()) {
            result = STREAM_ABORTED;
            break;
        }
        int64_t t0 = esp_timer_get_time();
        int n = esp_http_client_read(client, (char *)s_read_buf, READ_CHUNK);
        read_wait_us += esp_timer_get_time() - t0;
        if (n > 0) {
            stat_bytes += n;
        }
        if (n < 0) {
            result = STREAM_FAILED;
            break;
        }
        if (n == 0) {
            result = STREAM_ENDED;
            break;
        }
        size_t audio = icy_filter(s_icy, s_read_buf, n, s_audio_buf);
        if (audio && !decode_bytes(&d, s_audio_buf, audio)) {
            result = abort_requested() ? STREAM_ABORTED : STREAM_FAILED;
            break;
        }
        uint32_t buffered = audio_core_music_buffered_ms();
        buf_min = buffered < buf_min ? buffered : buf_min;
        int64_t now = esp_timer_get_time();
        if (now - stat_since >= STATS_MS * 1000LL) {
            unsigned underruns = audio_core_music_underruns();
            int64_t span = now - stat_since;
            ESP_LOGI(TAG, "net %u kbps (stream %d kbps), buffer %u ms (min %u), underruns +%u, waiting for network %u%%",
                     (unsigned)(stat_bytes * 8000ULL / (uint64_t)span), hdr.icy_br, (unsigned)buffered,
                     (unsigned)buf_min, underruns - underruns_base, (unsigned)(read_wait_us * 100 / span));
            stat_since = now;
            stat_bytes = 0;
            read_wait_us = 0;
            buf_min = UINT32_MAX;
            underruns_base = underruns;
        }
    }
    *played_ms = d.written_samples * 1000ull / AUDIO_SAMPLE_RATE;
    /* For stack measurement: minimum headroom after TLS + decoder have run together (used to update the table in Section 2.6) */
    ESP_LOGI(TAG, "stream end: %u ms played, stack free min %u B", (unsigned)*played_ms,
             (unsigned)uxTaskGetStackHighWaterMark(NULL));
    decode_ctx_close(&d);
    esp_http_client_cleanup(client);
    return result;
}

static void fail_stop(void)
{
    ESP_LOGW(TAG, "station unavailable, stopping");
    audio_core_music_flush();
    set_state(MEDIA_STOPPED);
    audio_core_tone();      /* alert tone (RAD-06) */
    app_error_t code = APP_ERR_RADIO_UNAVAILABLE;
    app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
}

/* If search candidates remain, switch to the next one */
static bool next_alternative(void)
{
    if (s_alt_next >= s_alt_count) {
        return false;
    }
    const radio_station_t *a = &s_alts[s_alt_next++];
    strlcpy(s_url, a->url, sizeof(s_url));
    xSemaphoreTake(s_lock, portMAX_DELAY);
    strlcpy(s_status.station, a->name, sizeof(s_status.station));
    s_status.icy_title[0] = '\0';
    s_status.bitrate_kbps = 0;
    xSemaphoreGive(s_lock);
    /* With XIP from PSRAM, NVS is usable even from a PSRAM-stack task (Chapter 7, Section 7.3) */
    save_last(a->url, a->name, -1);
    ESP_LOGW(TAG, "trying next search result: \"%s\"", a->name);
    return true;
}

/* Keep playing, reconnecting on drops. Return when a new command arrives */
static void play_loop(void)
{
    int failures = 0;
    uint32_t backoff = RETRY_MIN_MS;
    bool ever_played = false;   /* has this station produced sound at least once */
    for (;;) {
        set_state(MEDIA_BUFFERING);
        uint32_t played_ms = 0;
        stream_result_t r = stream_once(s_url, 0, &played_ms);
        if (r == STREAM_ABORTED) {
            return;
        }
        ever_played |= played_ms > 0;
        /* If the format is unplayable or it failed without ever playing, move to the next candidate rather than retrying */
        if ((r == STREAM_UNSUPPORTED || !ever_played) && next_alternative()) {
            failures = 0;
            backoff = RETRY_MIN_MS;
            continue;
        }
        if (r == STREAM_UNSUPPORTED) {
            fail_stop();
            return;
        }
        if (played_ms >= STABLE_MS) {
            failures = 0;
            backoff = RETRY_MIN_MS;
        }
        if (++failures > MAX_RETRIES) {
            fail_stop();
            return;
        }
        ESP_LOGW(TAG, "stream dropped, retry %d/%d in %lu ms", failures, MAX_RETRIES, (unsigned long)backoff);
        radio_cmd_t peek;
        if (xQueuePeek(s_cmds, &peek, pdMS_TO_TICKS(backoff)) == pdTRUE) {
            return;     /* new command while waiting */
        }
        backoff = backoff * 2 > RETRY_MAX_MS ? RETRY_MAX_MS : backoff * 2;
    }
}

static void radio_task(void *arg)
{
    for (;;) {
        radio_cmd_t cmd;
        if (xQueueReceive(s_cmds, &cmd, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        switch (cmd.type) {
        case CMD_PLAY:
            audio_core_music_flush();
            strlcpy(s_url, cmd.url, sizeof(s_url));
            xSemaphoreTake(s_lock, portMAX_DELAY);
            s_alt_count = s_pending_alt_count;
            s_alt_next = 0;
            if (s_alt_count > 0) {
                memcpy(s_alts, s_pending_alts, s_alt_count * sizeof(*s_alts));
            }
            s_status.preset = cmd.preset;
            strlcpy(s_status.station, cmd.title, sizeof(s_status.station));
            s_status.icy_title[0] = '\0';
            s_status.bitrate_kbps = 0;
            xSemaphoreGive(s_lock);
            ESP_LOGI(TAG, "play \"%s\"", cmd.title);    /* never log the URL (Section 2.2) */
            play_loop();
            break;
        case CMD_RESUME:
            if (s_url[0]) {
                play_loop();    /* live broadcast, so resume = reconnect */
            }
            break;
        case CMD_PAUSE:
            audio_core_music_flush();
            if (radio_is_active()) {
                set_state(MEDIA_PAUSED);
            }
            break;
        case CMD_STOP:
            audio_core_music_flush();
            set_state(MEDIA_STOPPED);
            break;
        }
    }
}

esp_err_t media_radio_init(void)
{
    s_cmds = xQueueCreate(4, sizeof(radio_cmd_t));
    s_lock = xSemaphoreCreateMutex();
    s_read_buf = heap_caps_malloc(PLAYLIST_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_audio_buf = heap_caps_malloc(READ_CHUNK, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_dec_buf_size = PCM_MAX_SAMPLES * sizeof(int16_t);
    s_dec_buf = heap_caps_malloc(s_dec_buf_size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_mono = heap_caps_malloc(PCM_MAX_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    /* sized generously for the largest ratio (48k→16k shrinks, but also allow for cases like 8k→48k) */
    s_resampled_cap = PCM_MAX_SAMPLES * 6;
    s_resampled = heap_caps_malloc(s_resampled_cap * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_icy = heap_caps_calloc(1, sizeof(icy_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_pending_alts = heap_caps_calloc(RADIO_SEARCH_MAX - 1, sizeof(radio_station_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_alts = heap_caps_calloc(RADIO_SEARCH_MAX - 1, sizeof(radio_station_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_cmds || !s_lock || !s_read_buf || !s_audio_buf || !s_dec_buf || !s_mono || !s_resampled || !s_icy ||
        !s_pending_alts || !s_alts) {
        return ESP_ERR_NO_MEM;
    }
    esp_err_t err = radio_presets_init();     /* audio_core_init already registered the decoders */
    if (err != ESP_OK) {
        return err;
    }
    /*
     * Decoding (HE-AAC) and the TLS handshake run on this stack (16KB). Internal RAM is short, so the stack is in PSRAM
     * (real board 2026-10-03: ESP_ERR_NO_MEM when allocated in internal RAM). So this task was not allowed to touch
     * flash (NVS, littlefs). Since fix round 3 (XIP from PSRAM) it may, but the last-station save is mostly done by send_cmd()
     * and preset reads use the RAM copy (exception: next_alternative() when switching to the next search candidate).
     */
    return xTaskCreatePinnedToCoreWithCaps(radio_task, "media_radio", 16384, NULL, 4, NULL, 0,
                                           MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
