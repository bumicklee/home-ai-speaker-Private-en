/*
 * NimBLE GATT server and GAP (design document, Section 2.13).
 * FF50 (Wi-Fi) and FF60 (device info), with FF80 (settings commands) added and every write encrypted.
 * Callbacks are called from the NimBLE host task: they only copy the value and hand it to the worker task.
 */
#include <string.h>
#include "app_config.h"
#include "ble_internal.h"
#include "device_api.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "BLE_GATT";

/* declared here directly, as in the NimBLE examples (not in the public headers) */
void ble_store_config_init(void);

#define ATT_ERR_CCCD_IMPROPER 0xFD      /* writing 0xFF81 without turning on 0xFF82 notifications (Section 2.13) */

ble_state_t g_ble = {.conn_handle = BLE_HS_CONN_HANDLE_NONE};

static uint8_t s_own_addr_type;
static char s_name[20];
static volatile bool s_stack_running;

static void start_advertising(void);

/* ── Copying write values ─────────────────────────────────────────── */

static int copy_write(struct ble_gatt_access_ctxt *ctxt, void *dst, size_t max, size_t *out_len)
{
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len > max) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (ble_hs_mbuf_to_flat(ctxt->om, dst, max, &len) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    *out_len = len;
    return 0;
}

static int append_read(struct ble_gatt_access_ctxt *ctxt, const void *data, size_t len)
{
    return os_mbuf_append(ctxt->om, data, len) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

/* ── Characteristic callbacks ────────────────────────────────────────────── */

static int on_wifi(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    uint16_t uuid = ble_uuid_u16(ctxt->chr->uuid);
    size_t len = 0;
    int rc;
    switch (uuid) {
    case APP_BLE_CHR_SSID: {
        char ssid[33] = {0};
        rc = copy_write(ctxt, ssid, 32, &len);
        if (rc == 0) {
            if (len == 0) {
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }
            memcpy(g_ble.ssid, ssid, sizeof(ssid));
        }
        return rc;
    }
    case APP_BLE_CHR_PASSWORD: {
        char pw[65] = {0};
        rc = copy_write(ctxt, pw, 64, &len);     /* length 0 for an open network */
        if (rc == 0) {
            memcpy(g_ble.password, pw, sizeof(pw));
            memset(pw, 0, sizeof(pw));
            ble_post_job(JOB_PASSWORD, 0, NULL, 0);
        }
        return rc;
    }
    case APP_BLE_CHR_STATUS: {
        uint8_t status = g_ble.wifi_status;
        return append_read(ctxt, &status, 1);
    }
    case APP_BLE_CHR_SCAN:
        /* any write starts a scan. The scan runs in the worker task (never blocks inside the GATT callback) */
        ble_post_job(JOB_SCAN, 0, NULL, 0);
        return 0;
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

static int on_device(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    switch (ble_uuid_u16(ctxt->chr->uuid)) {
    case APP_BLE_CHR_MAC: {
        char mac[13];
        device_mac_string(mac);
        return append_read(ctxt, mac, 12);
    }
    case APP_BLE_CHR_PRODUCT:
        return append_read(ctxt, APP_PRODUCT_CODE, strlen(APP_PRODUCT_CODE));
    case APP_BLE_CHR_FIRMWARE:
        return append_read(ctxt, APP_FW_VERSION, strlen(APP_FW_VERSION));
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

static int on_config(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    switch (ble_uuid_u16(ctxt->chr->uuid)) {
    case APP_BLE_CHR_CMD_RX: {
        if (!g_ble.cmd_tx_subscribed) {
            return ATT_ERR_CCCD_IMPROPER;
        }
        uint8_t buf[517];
        size_t len = 0;
        int rc = copy_write(ctxt, buf, sizeof(buf), &len);
        return rc ? rc : ble_cmd_on_fragment(buf, len);
    }
    case APP_BLE_CHR_CMD_TX:
        return 0;
    case APP_BLE_CHR_PROV_DONE: {
        uint8_t v = 0;
        size_t len = 0;
        int rc = copy_write(ctxt, &v, 1, &len);
        if (rc == 0 && len == 1 && v == 0x01) {
            ble_post_job(JOB_PROV_DONE, 0, NULL, 0);
            return 0;
        }
        return rc ? rc : BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

/* ── GATT table ──────────────────────────────────────────────── */

#define ENC_WRITE (BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC)

static const struct ble_gatt_svc_def s_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(APP_BLE_SVC_WIFI),
        .characteristics = (struct ble_gatt_chr_def[]){
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_SSID), .access_cb = on_wifi, .flags = ENC_WRITE},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_PASSWORD), .access_cb = on_wifi, .flags = ENC_WRITE},
            /* 0xFF53 and 0xFF54 are not encrypted (nearby Wi-Fi names may be visible; accepted) */
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_STATUS), .access_cb = on_wifi,
             .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY, .val_handle = &g_ble.status_handle},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_SCAN), .access_cb = on_wifi,
             .flags = ENC_WRITE | BLE_GATT_CHR_F_NOTIFY, .val_handle = &g_ble.scan_handle},
            {0},
        },
    },
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(APP_BLE_SVC_DEVICE),
        .characteristics = (struct ble_gatt_chr_def[]){
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_MAC), .access_cb = on_device, .flags = BLE_GATT_CHR_F_READ},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_PRODUCT), .access_cb = on_device, .flags = BLE_GATT_CHR_F_READ},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_FIRMWARE), .access_cb = on_device, .flags = BLE_GATT_CHR_F_READ},
            {0},
        },
    },
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(APP_BLE_SVC_CONFIG),
        .characteristics = (struct ble_gatt_chr_def[]){
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_CMD_RX), .access_cb = on_config, .flags = ENC_WRITE},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_CMD_TX), .access_cb = on_config,
             .flags = BLE_GATT_CHR_F_NOTIFY, .val_handle = &g_ble.cmd_tx_handle},
            {.uuid = BLE_UUID16_DECLARE(APP_BLE_CHR_PROV_DONE), .access_cb = on_config, .flags = ENC_WRITE},
            {0},
        },
    },
    {0},
};

/* ── GAP ──────────────────────────────────────────────────── */

static int on_gap(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            g_ble.conn_handle = event->connect.conn_handle;
            g_ble.connected = true;
            g_ble.cmd_tx_subscribed = false;
            ble_post_job(JOB_CONNECTED, 0, NULL, 0);
        } else {
            start_advertising();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnected (reason 0x%x)", event->disconnect.reason);
        g_ble.connected = false;
        g_ble.cmd_tx_subscribed = false;
        g_ble.conn_handle = BLE_HS_CONN_HANDLE_NONE;
        ble_post_job(JOB_DISCONNECTED, 0, NULL, 0);
        if (s_stack_running) {
            start_advertising();
        }
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == g_ble.cmd_tx_handle) {
            g_ble.cmd_tx_subscribed = event->subscribe.cur_notify;
        }
        return 0;
    case BLE_GAP_EVENT_ENC_CHANGE:
        ESP_LOGI(TAG, "encryption %s", event->enc_change.status == 0 ? "on" : "failed");
        return 0;
    case BLE_GAP_EVENT_REPEAT_PAIRING: {
        /* bonds aren't stored, so usually there's none; if any is left over, delete it and pair again */
        struct ble_gap_conn_desc desc;
        if (ble_gap_conn_find(event->repeat_pairing.conn_handle, &desc) == 0) {
            ble_store_util_delete_peer(&desc.peer_id_addr);
        }
        return BLE_GAP_REPEAT_PAIRING_RETRY;
    }
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU %d", event->mtu.value);
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (s_stack_running && !g_ble.connected) {
            start_advertising();
        }
        return 0;
    default:
        return 0;
    }
}

static void start_advertising(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (const uint8_t *)s_name;
    fields.name_len = strlen(s_name);
    fields.name_is_complete = 1;
    static const ble_uuid16_t svc = BLE_UUID16_INIT(APP_BLE_SVC_WIFI);
    fields.uuids16 = &svc;
    fields.num_uuids16 = 1;
    fields.uuids16_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv fields: %d", rc);
        return;
    }
    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
    };
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &params, on_gap, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) {
        ESP_LOGE(TAG, "adv start: %d", rc);
    }
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own_addr_type);
    ESP_LOGI(TAG, "advertising as %s", s_name);
    start_advertising();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "host reset: %d", reason);
}

static void host_task(void *arg)
{
    nimble_port_run();              /* until nimble_port_stop() is called */
    nimble_port_freertos_deinit();
}

/* ── Start and stop ────────────────────────────────────────────── */

esp_err_t ble_stack_start(const char *device_name)
{
    strlcpy(s_name, device_name, sizeof(s_name));
    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble init: %s", esp_err_to_name(err));
        return err;
    }
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    /* LE Secure Connections, Just Works, no bonding (Section 2.13, security) */
    ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_bonding = 0;
    ble_hs_cfg.sm_our_key_dist = 0;
    ble_hs_cfg.sm_their_key_dist = 0;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_gatts_count_cfg(s_services);
    if (rc == 0) {
        rc = ble_gatts_add_svcs(s_services);
    }
    if (rc == 0) {
        rc = ble_svc_gap_device_name_set(s_name);
    }
    if (rc != 0) {
        ESP_LOGE(TAG, "GATT setup: %d", rc);
        nimble_port_deinit();
        return ESP_FAIL;
    }
    ble_store_config_init();
    g_ble.connected = false;
    g_ble.cmd_tx_subscribed = false;
    g_ble.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_stack_running = true;
    nimble_port_freertos_init(host_task);
    return ESP_OK;
}

void ble_stack_stop(void)
{
    if (!s_stack_running) {
        return;
    }
    s_stack_running = false;
    if (g_ble.connected) {
        ble_gap_terminate(g_ble.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
        vTaskDelay(pdMS_TO_TICKS(200));
    }
    ble_gap_adv_stop();
    /* called outside the host task (from the worker task). Controller memory isn't released for good, so the window can open again */
    if (nimble_port_stop() == 0) {
        nimble_port_deinit();
    }
    g_ble.connected = false;
    ESP_LOGI(TAG, "stack stopped");
}

uint16_t ble_mtu(void)
{
    return g_ble.connected ? ble_att_mtu(g_ble.conn_handle) : BLE_ATT_MTU_DFLT;
}

esp_err_t ble_notify(uint16_t handle, const void *data, size_t len)
{
    for (int attempt = 0; attempt < 10; attempt++) {
        if (!g_ble.connected) {
            return ESP_ERR_INVALID_STATE;
        }
        struct os_mbuf *om = ble_hs_mbuf_from_flat(data, len);
        if (om) {
            int rc = ble_gatts_notify_custom(g_ble.conn_handle, handle, om);    /* hands over ownership of om */
            if (rc == 0) {
                return ESP_OK;
            }
            if (rc != BLE_HS_ENOMEM) {
                return ESP_FAIL;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(20));      /* out of notification buffers: retry after 20ms (Section 2.13) */
    }
    return ESP_ERR_NO_MEM;
}
