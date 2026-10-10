/**
 * @file media_radio.h
 * @brief Internet radio (design document Section 2.9, features RAD-01–12)
 *
 * Receives HTTP/HTTPS streams directly with esp_http_client: 302 redirects, .pls/.m3u playlists,
 * ICY metadata (song title), MP3/AAC (including HE-AAC). Decoded audio is converted to mono at the output rate
 * and fed to the audio_core music channel. On a drop, reconnects 5 times at intervals from 1 s up to 30 s.
 *
 * Presets (up to 20) are in /storage/presets.json on the storage (littlefs) partition.
 * Posts APP_EVT_MEDIA_STATE (app_media_event_t) when the state changes.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "app_events.h"
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RADIO_MAX_PRESETS 20
#define RADIO_NAME_MAX    48
#define RADIO_URL_MAX     256
#define RADIO_SEARCH_MAX  3     /* number of search candidates. If the first is HLS or fails to connect, move to the next */

/** One station (search result) */
typedef struct {
    char url[RADIO_URL_MAX + 1];
    char name[RADIO_NAME_MAX + 1];
} radio_station_t;
#define RADIO_GENRE_MAX   64

typedef struct {
    media_play_state_t state;
    int preset;                         /* preset index if playing a preset, else -1 */
    char station[RADIO_NAME_MAX + 1];
    char icy_title[128];                /* song now playing (only if the station reports it) */
    unsigned bitrate_kbps;
} radio_status_t;

/** Mounts littlefs, loads the presets and starts the playback task */
esp_err_t media_radio_init(void);

esp_err_t radio_play_url(const char *url, const char *title);
/** Plays list[0]; if it can't be played (HLS, connection failure), tries the rest in turn. count 1..RADIO_SEARCH_MAX */
esp_err_t radio_play_stations(const radio_station_t *list, int count);
esp_err_t radio_play_preset(int index);
/** The last station listened to (or the first preset if none). "Play the radio" */
esp_err_t radio_play_last(void);
esp_err_t radio_stop(void);
esp_err_t radio_pause(void);
esp_err_t radio_resume(void);
/** Step through presets (+1 next, -1 previous) */
esp_err_t radio_step(int delta);
bool      radio_is_active(void);        /* buffering, playing or paused */

void   radio_get_status(radio_status_t *out);
/** /api/v1/media/now format: source, state, title, artist, station */
cJSON *radio_now_json(void);

/* ── Presets (radio_presets.c) ────────────────────────────── */

/** Copy of [{name, url, genre}] */
cJSON    *radio_presets_get(void);
/** Replaces the whole list. ESP_ERR_INVALID_ARG if validation fails */
esp_err_t radio_presets_set(const cJSON *presets);
/** Restores the default presets (factory reset) */
esp_err_t radio_presets_reset(void);
/** Finds by part of the name (case-insensitive) or by genre tag. -1 if none */
int       radio_presets_find(const char *name, const char *genre);
int       radio_presets_count(void);
/** Copies the url and name of preset number index */
bool      radio_presets_entry(int index, char *url, size_t url_len, char *name, size_t name_len);

/* ── Station search (radio_search.c, Radio-Browser) ───────── */

/**
 * Searches by genre tag (by_tag) or name and picks up to max stations that look playable, by popularity.
 * Count goes in *found. ESP_ERR_NOT_FOUND if none. Blocking (HTTPS, several seconds). Call it from the tool worker.
 */
esp_err_t radio_search(const char *query, bool by_tag, radio_station_t *out, int max, int *found);

#ifdef __cplusplus
}
#endif
