/*
 * BLE window and worker task (design document, Section 2.13).
 *
 * What the worker task does: bring NimBLE up and down, Wi-Fi scan, test connection to new Wi-Fi, command handling,
 * 0xFF88 commit, window timing. GATT callbacks put jobs here and return right away.
 *
 * Fixed from led-app:
 * - defect where Wi-Fi was always saved on done (0xFF88): now saved only if status 2 (success) was reached in this connection
 * - defect where status was sent from two places and "auth failed" got overwritten by "timeout": one final status per attempt (net guarantees it)
 */
#include "ble_prov.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app_config.h"
#include "app_events.h"
#include "ble_internal.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "net.h"
#include "settings.h"

static const char *TAG = "BLE_PROV";

#define SCAN_MAX       20
#define SCAN_FETCH     32
#define SCAN_ENTRY_LEN 34      /* SSID 32 + RSSI 1 + security 1 (same size as led-app) */
#define SCAN_FAILED    0xFF

static QueueHandle_t s_jobs;
static esp_timer_handle_t s_tick;
static volatile bool s_open;
static bool s_unlimited;
static uint32_t s_opened_ms, s_idle_since_ms;
static bool s_wifi_ok;          /* reached status 2 in this connection */

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

bool ble_post_job(ble_job_type_t type, int arg, char *data, size_t len)
{
    ble_job_t job = {.type = type, .arg = arg, .data = data, .len = len};
    return s_jobs && xQueueSend(s_jobs, &job, 0) == pdTRUE;
}

bool ble_prov_is_open(void)
{
    return s_open;
}

/* ── Wi-Fi status (0xFF53) ──────────────────────────────────── */

static void set_wifi_status(uint8_t status)
{
    g_ble.wifi_status = status;
    ble_notify(g_ble.status_handle, &status, 1);
}

static void on_test_result(net_wifi_status_t status)
{
    /* called from the net event task. Hands off to the worker task */
    ble_post_job(JOB_WIFI_RESULT, status, NULL, 0);
}

static void handle_password(void)
{
    if (!g_ble.ssid[0]) {
        set_wifi_status(NET_WIFI_NO_SSID);
        return;
    }
    s_wifi_ok = false;
    set_wifi_status(NET_WIFI_CONNECTING);
    if (net_test_credentials(g_ble.ssid, g_ble.password, on_test_result) != ESP_OK) {
        set_wifi_status(NET_WIFI_TIMEOUT);
    }
}

/* ── Scan (0xFF54) ────────────────────────────────────────── */

/* IDF wifi_auth_mode_t numbers differ between versions, so they aren't sent as is (Section 2.13 table) */
static uint8_t security_code(wifi_auth_mode_t mode)
{
    switch (mode) {
    case WIFI_AUTH_OPEN: return 0;
    case WIFI_AUTH_WEP: return 1;
    case WIFI_AUTH_WPA_PSK: return 2;
    case WIFI_AUTH_WPA2_PSK: return 3;
    case WIFI_AUTH_WPA_WPA2_PSK: return 4;
    case WIFI_AUTH_WPA3_PSK: return 5;
    case WIFI_AUTH_WPA2_WPA3_PSK: return 6;
    case WIFI_AUTH_WPA2_ENTERPRISE:
    case WIFI_AUTH_WPA3_ENTERPRISE:
    case WIFI_AUTH_WPA2_WPA3_ENTERPRISE:
    case WIFI_AUTH_WPA3_ENT_192:
        return 7;
    default: return 255;
    }
}

static void handle_scan(void)
{
    static wifi_ap_record_t aps[SCAN_FETCH];
    int n = net_scan(aps, SCAN_FETCH);
    if (n < 0) {
        uint8_t fail = SCAN_FAILED;
        ble_notify(g_ble.scan_handle, &fail, 1);
        return;
    }
    /* for duplicate SSIDs keep only the strongest signal; skip hidden SSIDs */
    int keep[SCAN_MAX], count = 0;
    for (int i = 0; i < n && count < SCAN_MAX; i++) {
        if (!aps[i].ssid[0]) {
            continue;
        }
        int dup = -1;
        for (int k = 0; k < count && dup < 0; k++) {
            if (!strcmp((const char *)aps[keep[k]].ssid, (const char *)aps[i].ssid)) {
                dup = k;
            }
        }
        if (dup < 0) {
            keep[count++] = i;
        } else if (aps[i].rssi > aps[keep[dup]].rssi) {
            keep[dup] = i;
        }
    }
    uint8_t c = (uint8_t)count;
    ble_notify(g_ble.scan_handle, &c, 1);
    for (int k = 0; k < count; k++) {
        const wifi_ap_record_t *ap = &aps[keep[k]];
        uint8_t entry[SCAN_ENTRY_LEN] = {0};
        memcpy(entry, ap->ssid, strnlen((const char *)ap->ssid, 32));
        entry[32] = (uint8_t)(ap->rssi + 128);
        entry[33] = security_code(ap->authmode);
        ble_notify(g_ble.scan_handle, entry, sizeof(entry));
    }
    ESP_LOGI(TAG, "scan: %d network(s)", count);
}

/* ── Opening and closing the window ─────────────────────────────────────────── */

static void reset_connection_state(void)
{
    memset(g_ble.ssid, 0, sizeof(g_ble.ssid));
    memset(g_ble.password, 0, sizeof(g_ble.password));
    g_ble.wifi_status = NET_WIFI_IDLE;
    s_wifi_ok = false;
    ble_cmd_reset();
}

static ble_prov_memory_hook_t s_before_open, s_after_close;

void ble_prov_set_memory_hooks(ble_prov_memory_hook_t before_open, ble_prov_memory_hook_t after_close)
{
    s_before_open = before_open;
    s_after_close = after_close;
}

static void do_open(bool unlimited)
{
    if (s_open) {
        s_unlimited |= unlimited;
        s_opened_ms = s_idle_since_ms = now_ms();     /* pressing again restarts the timer */
        return;
    }
    uint8_t mac[6] = {0};
    net_get_sta_mac(mac);
    char name[20];
    snprintf(name, sizeof(name), APP_BLE_NAME_PREFIX "%02X%02X%02X", mac[3], mac[4], mac[5]);
    reset_connection_state();
    if (s_before_open) {
        s_before_open();    /* free internal RAM for the BLE controller (main: end the conversation + suspend AEC) */
    }
    if (ble_stack_start(name) != ESP_OK) {
        if (s_after_close) {
            s_after_close();
        }
        return;
    }
    s_open = true;
    s_unlimited = unlimited;
    s_opened_ms = s_idle_since_ms = now_ms();
    esp_timer_start_periodic(s_tick, 1000 * 1000);
    ESP_LOGI(TAG, "window open (%s)", unlimited ? "no limit" : "5 min");
    app_events_post(APP_EVT_PROV_START, NULL, 0, 0);
}

static void do_close(void)
{
    if (!s_open) {
        return;
    }
    esp_timer_stop(s_tick);
    ble_stack_stop();
    if (s_after_close) {
        s_after_close();
    }
    /* if an uncommitted test connection is left, revert to the saved Wi-Fi */
    net_end_test(false);
    reset_connection_state();
    s_open = false;
    ESP_LOGI(TAG, "window closed");
    app_events_post(APP_EVT_PROV_DONE, NULL, 0, 0);
}

static void handle_tick(void)
{
    if (!s_open || s_unlimited) {
        return;
    }
    uint32_t now = now_ms();
    if (now - s_opened_ms >= APP_BLE_WINDOW_MAX_MS) {
        ESP_LOGI(TAG, "window max time reached");
        do_close();
    } else if (!g_ble.connected && now - s_idle_since_ms >= APP_BLE_WINDOW_MS) {
        ESP_LOGI(TAG, "window idle timeout");
        do_close();
    }
}

/* ── 0xFF88 commit ──────────────────────────────────────────── */

static void handle_prov_done(void)
{
    bool was_provisioned = settings_is_provisioned();
    bool reboot = false;
    if (s_wifi_ok) {
        /* save only the Wi-Fi that succeeded in this connection (fixes led-app's overwrite defect) */
        if (settings_set_wifi(g_ble.ssid, g_ble.password) == ESP_OK) {
            net_end_test(true);
            reboot = true;
        }
    }
    if (!was_provisioned && settings_has_wifi()) {
        settings_set_provisioned(true);     /* first-time setup complete */
        reboot = true;
    }
    ESP_LOGI(TAG, "provisioning complete (wifi %s, reboot %d)", s_wifi_ok ? "saved" : "unchanged", reboot);
    do_close();
    if (reboot) {
        vTaskDelay(pdMS_TO_TICKS(APP_PROV_REBOOT_DELAY_MS));
        esp_restart();
    }
}

/* ── Worker task ──────────────────────────────────────────── */

static void worker(void *arg)
{
    for (;;) {
        ble_job_t job;
        if (xQueueReceive(s_jobs, &job, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        /* drop jobs left over after the window closes (except open requests) */
        if (!s_open && job.type != JOB_OPEN) {
            if (job.data) {
                memset(job.data, 0, job.len);
                free(job.data);
            }
            continue;
        }
        switch (job.type) {
        case JOB_OPEN:
            do_open(job.arg != 0);
            break;
        case JOB_CLOSE:
            do_close();
            break;
        case JOB_TICK:
            handle_tick();
            break;
        case JOB_CONNECTED:
            ESP_LOGI(TAG, "phone connected");
            break;
        case JOB_DISCONNECTED:
            /* revert an unsaved test connection; the next connection starts from scratch */
            if (net_is_testing()) {
                net_end_test(false);
            }
            reset_connection_state();
            s_idle_since_ms = now_ms();
            break;
        case JOB_SCAN:
            handle_scan();
            break;
        case JOB_PASSWORD:
            handle_password();
            break;
        case JOB_WIFI_RESULT:
            if (job.arg == NET_WIFI_SUCCESS) {
                s_wifi_ok = true;
            }
            set_wifi_status((uint8_t)job.arg);
            break;
        case JOB_PROV_DONE:
            handle_prov_done();
            break;
        case JOB_COMMAND:
            ble_cmd_handle(job.data, job.len);  /* frees data */
            if (ble_cmd_take_close_request()) {
                do_close();     /* prov.close: apply the values written so far, no reboot */
            }
            break;
        case JOB_COMMAND_BUSY:
            ble_cmd_reply_error(job.arg, "BUSY");
            break;
        case JOB_COMMAND_ERROR:
            ble_cmd_frame_error(job.arg);
            break;
        }
    }
}

static void tick_cb(void *arg)
{
    ble_post_job(JOB_TICK, 0, NULL, 0);
}

esp_err_t ble_prov_init(void)
{
    s_jobs = xQueueCreate(16, sizeof(ble_job_t));
    const esp_timer_create_args_t args = {.callback = tick_cb, .name = "ble_window"};
    if (!s_jobs || esp_timer_create(&args, &s_tick) != ESP_OK) {
        return ESP_ERR_NO_MEM;
    }
    /* generous, since it does the scan (about 3 s), NVS writes, NimBLE bring-up and the spotify.link TLS handshake */
    return xTaskCreatePinnedToCoreWithCaps(worker, "ble_worker", 10240, NULL, 4, NULL, 0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) == pdPASS ? ESP_OK
                                                                                         : ESP_ERR_NO_MEM;
}

esp_err_t ble_prov_open_window(void)
{
    return ble_post_job(JOB_OPEN, 0, NULL, 0) ? ESP_OK : ESP_ERR_NO_MEM;
}

esp_err_t ble_prov_open_unlimited(void)
{
    return ble_post_job(JOB_OPEN, 1, NULL, 0) ? ESP_OK : ESP_ERR_NO_MEM;
}

void ble_prov_close_window(void)
{
    ble_post_job(JOB_CLOSE, 0, NULL, 0);
}
