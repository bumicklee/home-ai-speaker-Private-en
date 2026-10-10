/**
 * @file local_api.h
 * @brief HTTP REST + WebSocket events for the app on the same Wi-Fi (design document Section 2.14)
 *
 * Every request carries Authorization: Bearer <api.pair token>. Writing secrets is not accepted over LAN (D6).
 * Radio, Telegram, Spotify and OTA endpoints are added in their respective Phases.
 */
#pragma once

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Starts the server on port 80 and subscribes to the event relay */
esp_err_t local_api_start(void);

#ifdef __cplusplus
}
#endif
