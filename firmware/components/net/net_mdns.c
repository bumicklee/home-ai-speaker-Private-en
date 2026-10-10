/*
 * mDNS: lets the app on the same Wi-Fi find the speaker (design document Section 2.14).
 * The firmware version and assistant name are not put in TXT (only in the authenticated /status).
 */
#include "net.h"

#include <stdio.h>
#include "app_config.h"
#include "esp_log.h"
#include "mdns.h"

static const char *TAG = "MDNS";

esp_err_t net_mdns_start(void)
{
    uint8_t mac[6];
    esp_err_t err = net_get_sta_mac(mac);
    if (err != ESP_OK) {
        return err;
    }
    char host[24], id[8], pv[8];
    snprintf(id, sizeof(id), "%02X%02X%02X", mac[3], mac[4], mac[5]);
    snprintf(host, sizeof(host), APP_MDNS_HOST_PREFIX "%02x%02x%02x", mac[3], mac[4], mac[5]);
    snprintf(pv, sizeof(pv), "%d", APP_PROTOCOL_VERSION);

    err = mdns_init();
    if (err == ESP_OK) {
        err = mdns_hostname_set(host);
    }
    if (err == ESP_OK) {
        err = mdns_instance_name_set(host);
    }
    mdns_txt_item_t txt[] = {{"id", id}, {"pv", pv}};
    if (err == ESP_OK) {
        err = mdns_service_add(NULL, APP_MDNS_SERVICE, APP_MDNS_PROTO, APP_HTTP_PORT, txt, 2);
    }
    ESP_LOGI(TAG, "%s.local %s: %s", host, APP_MDNS_SERVICE, esp_err_to_name(err));
    return err;
}
