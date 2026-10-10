/*
 * Substitute code for builds with Spotify off (CONFIG_APP_SPOTIFY=n, the default). User decision of 2026-10-03.
 * The public API is the same as spotify_api.c, and it always answers "not connected".
 * Uses no resources: no locks, tasks, HTTPS, or memory allocation.
 * - spotify_linked() is false, so Spotify does not appear in the assistant tools or instructions, and music control goes to the radio
 * - BLE spotify.link gives ESP_ERR_NOT_SUPPORTED (response UNKNOWN_OP)
 * - spotify.logout erases previously saved values if any (when coming from a build that had it on)
 */
#include "media_spotify.h"

#include "esp_log.h"
#include "secret_store.h"

static const char *TAG = "SPOTIFY";

esp_err_t media_spotify_init(void)
{
    ESP_LOGI(TAG, "disabled (CONFIG_APP_SPOTIFY=n)");
    return ESP_OK;
}

esp_err_t spotify_link(const char *client_id, const char *refresh_token)
{
    return ESP_ERR_NOT_SUPPORTED;
}

esp_err_t spotify_logout(void)
{
    esp_err_t a = secret_erase(SECRET_SP_CLIENT_ID);
    esp_err_t b = secret_erase(SECRET_SP_REFRESH);
    esp_err_t c = secret_erase(SECRET_SP_CONNECT_BLOB);
    return a != ESP_OK ? a : (b != ESP_OK ? b : c);
}

bool spotify_linked(void)
{
    return false;
}

spotify_state_t spotify_state(void)
{
    return SPOTIFY_OFF;
}

const char *spotify_state_name(spotify_state_t state)
{
    static const char *const names[] = {"off", "ok", "relogin_required", "premium_required", "error"};
    return (unsigned)state < 5 ? names[state] : "off";
}

esp_err_t spotify_play(const char *query, const char *type, char *desc, size_t desc_len)
{
    if (desc && desc_len) {
        desc[0] = '\0';
    }
    return ESP_ERR_NOT_SUPPORTED;
}

esp_err_t spotify_control(const char *action)
{
    return ESP_ERR_NOT_SUPPORTED;
}

static cJSON *now_none(void)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "source", "none");
    cJSON_AddStringToObject(j, "state", "stopped");
    return j;
}

cJSON *spotify_now_json(void)
{
    return now_none();
}

cJSON *spotify_now_cached(void)
{
    return now_none();
}

cJSON *spotify_status_json(void)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddBoolToObject(j, "linked", false);
    cJSON_AddStringToObject(j, "state", "off");
    cJSON_AddBoolToObject(j, "available", false);     /* this firmware has no Spotify (the app hides the screen) */
    return j;
}

bool spotify_recently_playing(void)
{
    return false;
}
