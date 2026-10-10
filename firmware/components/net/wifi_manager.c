/*
 * Wi-Fi station management. Design points:
 * - Does not include higher-module headers such as ble_prov (higher modules are notified through app_events)
 * - Wi-Fi details are read from the settings module
 * - The disconnect reason mapping adds the IDF 5.x 2xx codes (NO_AP_FOUND_W_COMPATIBLE_SECURITY, etc.)
 * - Logs record only the SSID length, not the SSID
 */
#include "net.h"

#include <string.h>
#include "app_config.h"
#include "app_events.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/timers.h"
#include "settings.h"

static const char *TAG = "WIFI";

#define CONNECTED_BIT BIT0

static EventGroupHandle_t s_flags;
static TimerHandle_t s_reconnect_timer;
static TimerHandle_t s_dhcp_timer;
static volatile bool s_connected;
static volatile bool s_started;
static volatile int64_t s_assoc_since_us;   /* 0 = not connected */
static uint32_t s_retry_delay_ms = APP_WIFI_RETRY_MIN_MS;
static uint8_t s_last_reason;
static bool s_power_save = true;

/* Provisioning test connection */
static volatile bool s_testing;
static volatile bool s_test_reported;
static net_test_cb_t s_test_cb;
static TimerHandle_t s_test_timer;
static int64_t s_test_started_us;
/* The test state is touched by both the Wi-Fi event task and the ble_worker task */
static portMUX_TYPE s_test_lock = portMUX_INITIALIZER_UNLOCKED;
#define TEST_SETTLE_US (500 * 1000)    /* a disconnect within this time right after a new attempt is treated as belonging to the previous attempt */

net_wifi_status_t net_status_from_reason(uint8_t reason)
{
    switch (reason) {
    case WIFI_REASON_NO_AP_FOUND:
    case WIFI_REASON_NO_AP_FOUND_W_COMPATIBLE_SECURITY:
    case WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD:
    case WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD:
        return NET_WIFI_NO_SSID;
    case WIFI_REASON_AUTH_FAIL:
    case WIFI_REASON_AUTH_EXPIRE:
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_MIC_FAILURE:
    case WIFI_REASON_CONNECTION_FAIL:
        return NET_WIFI_AUTH_FAIL;
    case WIFI_REASON_UNSPECIFIED:
    case WIFI_REASON_ASSOC_LEAVE:
        return NET_WIFI_CONNECTING;     /* not an error; the normal flow */
    default:
        return NET_WIFI_TIMEOUT;
    }
}

uint8_t net_last_disconnect_reason(void)
{
    return s_last_reason;
}

bool net_is_connected(void)
{
    return s_connected;
}

bool net_wait_connected(uint32_t timeout_ms)
{
    if (!s_flags) {
        return false;
    }
    return xEventGroupWaitBits(s_flags, CONNECTED_BIT, pdFALSE, pdTRUE, pdMS_TO_TICKS(timeout_ms)) & CONNECTED_BIT;
}

esp_err_t net_get_sta_mac(uint8_t mac[6])
{
    return esp_wifi_get_mac(WIFI_IF_STA, mac);
}

void net_set_power_save(bool enable)
{
    s_power_save = enable;
    if (s_started) {
        esp_wifi_set_ps(enable ? WIFI_PS_MIN_MODEM : WIFI_PS_NONE);
    }
}

bool net_is_testing(void)
{
    return s_testing;
}

/* Send a terminal status only once per attempt. The first reason decided wins (sending it twice makes the app show the wrong guidance) */
static void report_test(net_wifi_status_t status)
{
    net_test_cb_t cb = NULL;
    portENTER_CRITICAL(&s_test_lock);
    bool stale = status != NET_WIFI_SUCCESS && status != NET_WIFI_TIMEOUT &&
                 esp_timer_get_time() - s_test_started_us < TEST_SETTLE_US;
    if (s_testing && !s_test_reported && !stale) {
        s_test_reported = true;
        cb = s_test_cb;
    }
    portEXIT_CRITICAL(&s_test_lock);
    if (!cb) {
        return;
    }
    xTimerStop(s_test_timer, 0);
    ESP_LOGI(TAG, "test result: %d", status);
    cb(status);
}

static void test_timeout_cb(TimerHandle_t t)
{
    report_test(NET_WIFI_TIMEOUT);
}

static void reconnect_cb(TimerHandle_t t)
{
    if (!s_connected && s_assoc_since_us == 0) {
        esp_wifi_connect();
    }
}

/* Associated with the AP but DHCP is slow and no IP arrives: there is no disconnect event, so no retry happens. Disconnect directly */
static void dhcp_watch_cb(TimerHandle_t t)
{
    if (s_connected || s_assoc_since_us == 0) {
        return;
    }
    int64_t waited_ms = (esp_timer_get_time() - s_assoc_since_us) / 1000;
    if (waited_ms >= APP_WIFI_DHCP_GRACE_MS) {
        ESP_LOGW(TAG, "associated %lld ms without IP, reconnecting", (long long)waited_ms);
        s_assoc_since_us = 0;
        esp_wifi_disconnect();
    }
}

/*
 * Backup DNS (2026-10-03 real board: the router's DNS did not answer, so name lookups for api.telegram.org and SNTP kept failing,
 * getaddrinfo() 202). The router's DNS is used first; if it does not answer, lwIP moves on to the next server (1.1.1.1 → 8.8.8.8).
 * If DHCP provided a backup DNS, leave it and fill only the last slot.
 */
static void add_backup_dns(esp_netif_t *netif)
{
    esp_netif_dns_info_t dns = {0};
    if (esp_netif_get_dns_info(netif, ESP_NETIF_DNS_MAIN, &dns) == ESP_OK) {
        ESP_LOGI(TAG, "DNS from router: " IPSTR, IP2STR(&dns.ip.u_addr.ip4));
    }
    esp_netif_dns_info_t backup = {0};
    bool has_backup = esp_netif_get_dns_info(netif, ESP_NETIF_DNS_BACKUP, &backup) == ESP_OK &&
                      backup.ip.u_addr.ip4.addr != 0;
    esp_netif_dns_info_t extra = {.ip = {.type = ESP_IPADDR_TYPE_V4}};
    if (!has_backup) {
        extra.ip.u_addr.ip4.addr = ESP_IP4TOADDR(1, 1, 1, 1);
        esp_netif_set_dns_info(netif, ESP_NETIF_DNS_BACKUP, &extra);
    }
    extra.ip.u_addr.ip4.addr = ESP_IP4TOADDR(8, 8, 8, 8);
    esp_err_t err = esp_netif_set_dns_info(netif, ESP_NETIF_DNS_FALLBACK, &extra);
    ESP_LOGI(TAG, "backup DNS %s8.8.8.8: %s", has_backup ? "" : "1.1.1.1, ", esp_err_to_name(err));
}

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        /* During first-boot BLE setup the SSID is empty. Do not try to connect, so that only scanning happens */
        wifi_config_t cfg;
        if (esp_wifi_get_config(WIFI_IF_STA, &cfg) == ESP_OK && cfg.sta.ssid[0]) {
            esp_wifi_connect();
        }
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_CONNECTED) {
        s_assoc_since_us = esp_timer_get_time();
        /*
         * Turn power save off until an IP arrives. In power save the radio wakes only at DTIM intervals and can miss the DHCP reply (broadcast).
         * On real hardware "no IP for 16 seconds" kept repeating (Appendix I, Section I.6). Restored once an IP arrives
         */
        esp_wifi_set_ps(WIFI_PS_NONE);
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        const wifi_event_sta_disconnected_t *evt = data;
        bool was_connected = s_connected;
        s_last_reason = evt->reason;
        s_connected = false;
        s_assoc_since_us = 0;
        xEventGroupClearBits(s_flags, CONNECTED_BIT);
        if (was_connected) {
            app_events_post(APP_EVT_WIFI_DOWN, &s_last_reason, sizeof(s_last_reason), 0);
        }

        net_wifi_status_t status = net_status_from_reason(evt->reason);
        if (s_testing) {
            /* No backoff retries during a test. In the normal flow (reasons 1 and 8), try to reattach */
            if (status == NET_WIFI_CONNECTING && !s_test_reported) {
                esp_wifi_connect();
            } else {
                report_test(status);
            }
            return;
        }
        ESP_LOGW(TAG, "disconnected: reason %d (status %d), retry in %lu ms",
                 evt->reason, status, (unsigned long)s_retry_delay_ms);
        if (status == NET_WIFI_CONNECTING) {
            esp_wifi_connect();
            return;
        }
        /* Retries never stop. This recovers from router reboots and temporary outages with no intervention */
        xTimerChangePeriod(s_reconnect_timer, pdMS_TO_TICKS(s_retry_delay_ms), 0);
        xTimerStart(s_reconnect_timer, 0);
        s_retry_delay_ms *= 2;
        if (s_retry_delay_ms > APP_WIFI_RETRY_MAX_MS) {
            s_retry_delay_ms = APP_WIFI_RETRY_MAX_MS;
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        const ip_event_got_ip_t *evt = data;
        s_retry_delay_ms = APP_WIFI_RETRY_MIN_MS;
        s_connected = true;
        s_assoc_since_us = 0;
        xEventGroupSetBits(s_flags, CONNECTED_BIT);
        esp_wifi_set_ps(s_power_save ? WIFI_PS_MIN_MODEM : WIFI_PS_NONE);
        ESP_LOGI(TAG, "connected, IP " IPSTR, IP2STR(&evt->ip_info.ip));
        add_backup_dns(evt->esp_netif);
        report_test(NET_WIFI_SUCCESS);
        app_events_post(APP_EVT_WIFI_UP, NULL, 0, 0);
    }
}

esp_err_t net_init(void)
{
    s_flags = xEventGroupCreate();
    s_reconnect_timer = xTimerCreate("wifi_retry", pdMS_TO_TICKS(1000), pdFALSE, NULL, reconnect_cb);
    s_dhcp_timer = xTimerCreate("wifi_dhcp", pdMS_TO_TICKS(APP_WIFI_DHCP_CHECK_MS), pdTRUE, NULL, dhcp_watch_cb);
    s_test_timer = xTimerCreate("wifi_test", pdMS_TO_TICKS(APP_WIFI_CONNECT_TIMEOUT_MS), pdFALSE, NULL, test_timeout_cb);
    if (!s_flags || !s_reconnect_timer || !s_dhcp_timer || !s_test_timer) {
        return ESP_ERR_NO_MEM;
    }

    ESP_ERROR_CHECK(esp_netif_init());
    esp_err_t err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));   /* Wi-Fi details are managed by settings */
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_wifi_event, NULL, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    return ESP_OK;
}

static esp_err_t apply_config(const char *ssid, const char *password)
{
    wifi_config_t cfg = {0};
    strlcpy((char *)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid));
    strlcpy((char *)cfg.sta.password, password, sizeof(cfg.sta.password));
    /* If the network is not open, accept only WPA2 or better */
    cfg.sta.threshold.authmode = cfg.sta.password[0] ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    cfg.sta.pmf_cfg.capable = true;
    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &cfg);
    memset(&cfg, 0, sizeof(cfg));
    return err;
}

static esp_err_t ensure_started(void)
{
    if (s_started) {
        return ESP_OK;
    }
    esp_err_t err = esp_wifi_start();      /* the connection starts on the STA_START event */
    if (err == ESP_OK) {
        s_started = true;
        xTimerStart(s_dhcp_timer, 0);
    }
    return err;
}

static bool s_time_started;

esp_err_t net_start(void)
{
    char ssid[33], password[65];
    esp_err_t err = settings_get_wifi(ssid, password);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "no saved Wi-Fi");
        return ESP_ERR_NOT_FOUND;
    }
    err = apply_config(ssid, password);
    memset(password, 0, sizeof(password));
    if (err == ESP_OK) {
        err = ensure_started();
    }
    if (err != ESP_OK) {
        return err;
    }
    ESP_LOGI(TAG, "connecting (ssid_len=%u)", (unsigned)strlen(ssid));
    if (!s_time_started) {
        s_time_started = true;
        return net_time_start();
    }
    return ESP_OK;
}

esp_err_t net_test_credentials(const char *ssid, const char *password, net_test_cb_t cb)
{
    if (!ssid || !ssid[0] || strlen(ssid) > 32 || !password || strlen(password) > 64) {
        return ESP_ERR_INVALID_ARG;
    }
    xTimerStop(s_reconnect_timer, 0);
    portENTER_CRITICAL(&s_test_lock);
    s_test_cb = cb;
    s_test_reported = false;
    s_testing = true;
    s_test_started_us = esp_timer_get_time();
    portEXIT_CRITICAL(&s_test_lock);
    bool was_started = s_started;
    if (was_started) {
        esp_wifi_disconnect();
    }
    esp_err_t err = apply_config(ssid, password);
    if (err == ESP_OK) {
        err = ensure_started();
    }
    if (err == ESP_OK && was_started) {
        esp_wifi_connect();
    }
    if (err != ESP_OK) {
        s_testing = false;
        return err;
    }
    xTimerChangePeriod(s_test_timer, pdMS_TO_TICKS(APP_WIFI_CONNECT_TIMEOUT_MS), 0);
    xTimerStart(s_test_timer, 0);
    ESP_LOGI(TAG, "testing new Wi-Fi (ssid_len=%u)", (unsigned)strlen(ssid));
    return ESP_OK;
}

void net_end_test(bool keep)
{
    portENTER_CRITICAL(&s_test_lock);
    bool was_testing = s_testing;
    s_testing = false;
    s_test_reported = true;
    portEXIT_CRITICAL(&s_test_lock);
    if (!was_testing) {
        return;
    }
    xTimerStop(s_test_timer, 0);
    if (keep && s_connected) {
        return;
    }
    /* Go back to the saved Wi-Fi. If none is saved, stay disconnected */
    char ssid[33], password[65];
    esp_wifi_disconnect();
    if (settings_get_wifi(ssid, password) == ESP_OK && apply_config(ssid, password) == ESP_OK) {
        esp_wifi_connect();
    }
    memset(password, 0, sizeof(password));
}

int net_scan(wifi_ap_record_t *out, uint16_t max)
{
    if (ensure_started() != ESP_OK) {
        return -1;
    }
    const wifi_scan_config_t cfg = {
        .show_hidden = false,
        .scan_type = WIFI_SCAN_TYPE_ACTIVE,
        .scan_time.active = {.min = 100, .max = 300},
    };
    esp_err_t err = esp_wifi_scan_start(&cfg, true);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "scan failed: %s", esp_err_to_name(err));
        return -1;
    }
    uint16_t n = max;
    if (esp_wifi_scan_get_ap_records(&n, out) != ESP_OK) {
        return -1;
    }
    return n;
}
