/**
 * @file ble_prov.h
 * @brief BLE provisioning GATT server (design document, Section 2.13)
 *
 * Services: Wi-Fi 0xFF50, device info 0xFF60, settings 0xFF80. Every write requires link encryption
 * (LE Secure Connections, Just Works, no bonding).
 *
 * BLE window: no time limit on first boot. A window opened by holding Key2 3 s closes after 5 min with no connection,
 * and after 15 min max even while connected. NimBLE is initialized fresh each time the window opens and fully shut down when it closes.
 * Open/close is announced with APP_EVT_PROV_START / APP_EVT_PROV_DONE.
 */
#pragma once

#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** creates the worker task. NimBLE comes up when the window opens */
esp_err_t ble_prov_init(void);

/** window opened by holding Key2 3 s (5 min / 15 min max) */
esp_err_t ble_prov_open_window(void);
/** unprovisioned first boot: no time limit */
esp_err_t ble_prov_open_unlimited(void);
/** close the window (handled by the worker task, returns right away) */
void      ble_prov_close_window(void);

/**
 * Functions called just before BLE comes up and right after it shuts down. The BLE controller uses internal RAM only, so main briefly frees memory used elsewhere.
 * Called from the ble_worker task (PSRAM stack).
 */
typedef void (*ble_prov_memory_hook_t)(void);
void ble_prov_set_memory_hooks(ble_prov_memory_hook_t before_open, ble_prov_memory_hook_t after_close);
bool      ble_prov_is_open(void);

#ifdef __cplusplus
}
#endif
