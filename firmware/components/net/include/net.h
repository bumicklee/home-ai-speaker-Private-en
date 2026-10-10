/**
 * @file net.h
 * @brief Wi-Fi station management (ported from led-app wifi_manager) and time sync (design document Section 2.4)
 *
 * - Reconnection keeps going with exponential backoff and never stops. A Wi-Fi failure alone does not enter provisioning.
 * - In the "connected but no IP" state, the DHCP watchdog disconnects and tries again.
 * - Connect/disconnect is announced with the APP_EVT_WIFI_UP / APP_EVT_WIFI_DOWN events.
 * - During provisioning, a test connection can be made with new, unsaved Wi-Fi details (net_test_credentials).
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "esp_wifi_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Same values as the BLE 0xFF53 status codes (Section 2.13) */
typedef enum {
    NET_WIFI_IDLE = 0,
    NET_WIFI_CONNECTING = 1,
    NET_WIFI_SUCCESS = 2,
    NET_WIFI_NO_SSID = 3,
    NET_WIFI_AUTH_FAIL = 4,
    NET_WIFI_TIMEOUT = 5,
} net_wifi_status_t;

/** Prepares netif, the default event loop, and the Wi-Fi driver (does not connect yet) */
esp_err_t net_init(void);

/** Starts connecting with the saved Wi-Fi and turns on SNTP. ESP_ERR_NOT_FOUND if no Wi-Fi is saved */
esp_err_t net_start(void);

bool net_is_connected(void);
bool net_wait_connected(uint32_t timeout_ms);

/** Wi-Fi STA MAC (device identifier, Section 2.13) */
esp_err_t net_get_sta_mac(uint8_t mac[6]);

/** Power save while idle (true); off during voice or music playback (false) (Section 2.19) */
void net_set_power_save(bool enable);

/** Disconnect reason → 0xFF53 status code */
net_wifi_status_t net_status_from_reason(uint8_t reason);
uint8_t           net_last_disconnect_reason(void);

/* ── Test connection for provisioning (Section 2.13 0xFF53 rules) ─ */

/** Test result. Called exactly once per attempt with a terminal status (2–5) (on the event task; must not block) */
typedef void (*net_test_cb_t)(net_wifi_status_t status);

/**
 * Tries to connect with new details without saving them. NET_WIFI_TIMEOUT if no IP arrives within 20 seconds.
 * No automatic reconnection (backoff) during the test. Calling again discards the previous attempt.
 */
esp_err_t net_test_credentials(const char *ssid, const char *password, net_test_cb_t cb);

/** Ends the test. keep=true keeps the current connection; false goes back to the saved Wi-Fi */
void net_end_test(bool keep);
bool net_is_testing(void);

/**
 * Scans nearby APs (blocking, about 2–3 seconds). Turns Wi-Fi on if needed.
 * Returns the count, or -1 on failure. Do not call from inside a GATT callback.
 */
int net_scan(wifi_ap_record_t *out, uint16_t max);

/* ── mDNS (net_mdns.c, Section 2.14) ────────────────────── */

/** jarvis-XXXXXX.local, _aispeaker._tcp:80, TXT id·pv */
esp_err_t net_mdns_start(void);

/* ── Time (net_time.c) ───────────────────────────────────── */

/** Whether the system clock is valid (after RTC restore or SNTP sync) */
bool net_time_valid(void);

/** Called every time SNTP sync completes (e.g. to update the RTC). Register before net_start() */
typedef void (*net_time_sync_cb_t)(void);
void net_set_time_sync_cb(net_time_sync_cb_t cb);

/* Internal */
esp_err_t net_time_start(void);

#ifdef __cplusplus
}
#endif
