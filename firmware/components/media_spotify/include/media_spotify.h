/**
 * @file media_spotify.h
 * @brief Spotify Web API (design document Section 2.10, features SPT-*)
 *
 * This file is the Web API side (account linking, token refresh, search, playback control, now playing).
 * The Connect receiver that lets the speaker play sound itself (cspot family) does not exist yet, pending the Q2 decision.
 * Meanwhile the playback target is picked from the account's Spotify devices (this speaker's name → active device → first device).
 *
 * Reflects the 2026 Spotify Development Mode changes:
 * - Search limit is at most 10, and GET /me has no product (Premium status) → Premium is judged from a 403 on a playback command
 * - Artist top tracks (top-tracks) were removed → artists are played as an artist context
 * - The refresh token expires 6 months after the first authorization, and refreshing does not extend it → on 400, prompt a new login
 *
 * Secrets (client_id, refresh token, access token) never go into logs or responses.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SPOTIFY_OFF,                /* not linked */
    SPOTIFY_OK,
    SPOTIFY_RELOGIN_REQUIRED,   /* refresh token expired or revoked (6 months) */
    SPOTIFY_PREMIUM_REQUIRED,   /* playback control is Premium only */
    SPOTIFY_ERROR,              /* temporary error, e.g. network */
} spotify_state_t;

esp_err_t media_spotify_init(void);

/**
 * Saves the client_id (32 hex digits) and refresh token the app obtained through PKCE.
 * Tries one token refresh before saving; on failure, saves nothing and returns ESP_ERR_INVALID_ARG.
 * Blocking (HTTPS). Called from the BLE work task.
 */
esp_err_t spotify_link(const char *client_id, const char *refresh_token);
/** Erases client_id, the refresh token, and Connect credentials */
esp_err_t spotify_logout(void);
bool      spotify_linked(void);

spotify_state_t spotify_state(void);
const char     *spotify_state_name(spotify_state_t state);

/**
 * Searches and plays. type: track · artist · album · playlist.
 * Fills desc with a description like "title - artist". Blocking (HTTPS). Called from the tool worker.
 * ESP_ERR_NOT_FOUND: no results, ESP_ERR_INVALID_STATE: no device to play on, ESP_ERR_NOT_ALLOWED: not Premium
 */
esp_err_t spotify_play(const char *query, const char *type, char *desc, size_t desc_len);

/** pause · resume · next · previous · stop (= pause). Blocking */
esp_err_t spotify_control(const char *action);

/** /api/v1/media/now format (source none if nothing is playing). Blocking */
cJSON *spotify_now_json(void);
/** GET /api/v1/spotify: linked, state, account, device, last_error */
cJSON *spotify_status_json(void);

/** Last playback state, from the cache (non-blocking). For tools and status display */
bool spotify_recently_playing(void);
/** Copy of the last now result received (non-blocking). For LAN handlers. source none if there is none yet */
cJSON *spotify_now_cached(void);

#ifdef __cplusplus
}
#endif
