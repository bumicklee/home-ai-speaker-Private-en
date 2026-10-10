/**
 * @file secret_store.h
 * @brief Secret store (secrets partition, plaintext NVS)
 *
 * secret_get results never go out over BLE or LAN. The app can only see whether a value is stored.
 * Logs show only the length, never the value.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SECRET_OPENAI_KEY,
    SECRET_TG_BOT_TOKEN,
    SECRET_SP_CLIENT_ID,
    SECRET_SP_REFRESH,
    SECRET_SP_CONNECT_BLOB,
    SECRET_STOCK_KEY,
    SECRET_GEMINI_KEY,      /* docs/design-voice-saver-mode.md 11.2 (1–512 bytes) */
    SECRET_COUNT,
} secret_id_t;

esp_err_t secret_set(secret_id_t id, const void *value, size_t len);
esp_err_t secret_get(secret_id_t id, void *out, size_t *len);   /* firmware-internal only */
bool      secret_exists(secret_id_t id);
esp_err_t secret_erase(secret_id_t id);

#ifdef __cplusplus
}
#endif
