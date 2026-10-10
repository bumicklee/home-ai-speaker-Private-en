/*
 * Shared internal state for ble_prov. Used by ble_prov.c (window, worker task), ble_gatt.c (GATT, GAP)
 * and ble_cmd.c (command protocol).
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

/* Worker task jobs. GATT callbacks don't do slow work themselves; they put it here (Section 2.2) */
typedef enum {
    JOB_OPEN,
    JOB_CLOSE,
    JOB_TICK,
    JOB_CONNECTED,
    JOB_DISCONNECTED,
    JOB_SCAN,
    JOB_PASSWORD,           /* password written → test connection */
    JOB_WIFI_RESULT,        /* arg = net_wifi_status_t */
    JOB_PROV_DONE,          /* 0xFF88 */
    JOB_COMMAND,            /* data = reassembled JSON (freed by the worker task) */
    JOB_COMMAND_BUSY,       /* arg = request id */
    JOB_COMMAND_ERROR,      /* arg = error kind, reassembly failed */
} ble_job_type_t;

typedef struct {
    ble_job_type_t type;
    int arg;
    char *data;
    size_t len;
} ble_job_t;

bool ble_post_job(ble_job_type_t type, int arg, char *data, size_t len);

/* ── Connection state (updated by ble_gatt.c) ───────────────────────── */
typedef struct {
    volatile bool connected;
    volatile uint16_t conn_handle;
    volatile bool cmd_tx_subscribed;
    uint16_t status_handle, scan_handle, cmd_tx_handle;
    /* Wi-Fi info received in this connection (not yet saved) */
    char ssid[33];
    char password[65];
    volatile uint8_t wifi_status;       /* 0xFF53 value */
} ble_state_t;

extern ble_state_t g_ble;

/* ble_gatt.c */
esp_err_t ble_stack_start(const char *device_name);
void      ble_stack_stop(void);
/** Send a notification. If no buffer is free, retry after 20ms, up to 10 times (call from the worker task only) */
esp_err_t ble_notify(uint16_t handle, const void *data, size_t len);
uint16_t  ble_mtu(void);

/* ble_cmd.c */
/** One 0xFF81 write chunk (called from the GATT callback, never blocks). Returns an ATT error code or 0 */
int  ble_cmd_on_fragment(const uint8_t *data, size_t len);
void ble_cmd_reset(void);
/** Worker task: handle the command, then respond */
void ble_cmd_handle(char *json, size_t len);
void ble_cmd_reply_error(int id, const char *code);
/** Did a prov.close request arrive? (so the window closes after the response is sent) */
bool ble_cmd_take_close_request(void);
void ble_cmd_frame_error(int kind);
