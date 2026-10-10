/**
 * @file device_api.h
 * @brief Device control layer shared by BLE (ble_prov) and LAN (local_api) (design document Sections 2.13, 2.14, 4)
 *
 * If the two paths parsed the same settings separately, their schemas would drift apart. So JSON conversion, validation and
 * application all happen in this one module. The settings group schema is the same as LAN /api/v1/settings/{group}.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include "cJSON.h"
#include "esp_err.h"
#include "secret_store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Settings groups (device_settings.c) ─────────────────── */

/** group: audio · wake · assistant · led. NULL for an unknown group */
cJSON    *device_settings_get(const char *group);

/**
 * Changes only the given keys (partial update). An unknown key or a wrong type or range gives ESP_ERR_INVALID_ARG,
 * an unknown group gives ESP_ERR_NOT_FOUND. On success it applies and saves immediately, then
 * sends APP_EVT_SETTINGS_CHANGED.
 */
esp_err_t device_settings_set(const char *group, const cJSON *value);

/* ── Device info (device_info.c) ─────────────────────────── */

/** BLE device.info: protocol_version, fw, mac, provisioned, wifi_connected, secrets */
cJSON *device_info(void);
/** LAN /status */
cJSON *device_status(void);
/** Whether each key is saved {"openai_key": true, ...}. Never includes the values */
cJSON *device_secrets_state(void);
/** STA MAC as 12 uppercase hex digits */
void   device_mac_string(char out[13]);

/**
 * Secret name → ID. Accepts only names the app is allowed to write
 * (openai_key, tg_bot_token, stock_key). Spotify values are for spotify.link only, so they are rejected.
 */
bool device_secret_from_name(const char *name, secret_id_t *out);

/* ── Phone tokens (phones.c) ─────────────────────────────── */

#define PHONE_ID_MAX    36      /* UUID string */
#define PHONE_NAME_MAX  32
#define PHONE_TOKEN_LEN 43      /* 32 bytes as base64url (no padding) */

esp_err_t phones_init(void);

/**
 * Creates a new token. The same phone_id replaces its existing token.
 * If all 5 phones are registered, ESP_ERR_INVALID_SIZE (give evict a phone_id to remove that one and register).
 * The device stores only the token's SHA-256.
 */
esp_err_t phones_pair(const char *phone_id, const char *name, const char *evict, char token[PHONE_TOKEN_LEN + 1]);

/** Checks a Bearer token (constant-time comparison). On a match, fills phone_id */
bool phones_verify(const char *token, char phone_id[PHONE_ID_MAX + 1]);

/** [{phone_id, name, created, self}] */
cJSON    *phones_list(const char *self_phone_id);
esp_err_t phones_revoke(const char *phone_id);
esp_err_t phones_clear(void);

#ifdef __cplusplus
}
#endif
