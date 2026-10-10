/*
 * LAN API authentication (design document Section 2.14, authentication).
 * - Reject if Host is not jarvis-*.local or an IP address: this blocks the attack where a malicious web page changes DNS
 *   so that the browser sends requests to the speaker (DNS rebinding).
 * - Reject if there is an Origin header: the app never sends one, browsers do.
 * - 5 consecutive failures from the same IP give 429 for 30 seconds. The record table has 8 slots.
 * - The 401 response body is always the same. Token comparison is the constant-time comparison in phones_verify.
 */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include "api_internal.h"
#include "app_config.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "lwip/sockets.h"

static const char *TAG = "API_AUTH";

#define RATE_SLOTS      8
#define RATE_MAX_FAILS  5
#define RATE_BLOCK_MS   30000

typedef struct {
    uint32_t ip;
    uint8_t fails;
    uint32_t blocked_until;
    uint32_t last_ms;
} rate_slot_t;

static rate_slot_t s_rate[RATE_SLOTS];
static portMUX_TYPE s_rate_lock = portMUX_INITIALIZER_UNLOCKED;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static uint32_t peer_ip(httpd_req_t *req)
{
    struct sockaddr_storage addr;
    socklen_t len = sizeof(addr);
    if (getpeername(httpd_req_to_sockfd(req), (struct sockaddr *)&addr, &len) != 0) {
        return 0;
    }
    if (addr.ss_family == AF_INET) {
        return ((struct sockaddr_in *)&addr)->sin_addr.s_addr;
    }
#if LWIP_IPV6
    if (addr.ss_family == AF_INET6) {
        const uint32_t *w = (const uint32_t *)&((struct sockaddr_in6 *)&addr)->sin6_addr;
        return w[3] ^ w[2];     /* for an IPv4-mapped address, the last 4 bytes are the IPv4 address */
    }
#endif
    return 0;
}

static rate_slot_t *slot_for(uint32_t ip)
{
    rate_slot_t *oldest = &s_rate[0];
    for (int i = 0; i < RATE_SLOTS; i++) {
        if (s_rate[i].ip == ip) {
            return &s_rate[i];
        }
        if ((int32_t)(s_rate[i].last_ms - oldest->last_ms) < 0) {
            oldest = &s_rate[i];
        }
    }
    /* when the table is full, reuse the least recently used slot */
    memset(oldest, 0, sizeof(*oldest));
    oldest->ip = ip;
    return oldest;
}

static bool is_blocked(uint32_t ip)
{
    bool blocked;
    portENTER_CRITICAL(&s_rate_lock);
    rate_slot_t *s = slot_for(ip);
    s->last_ms = now_ms();
    blocked = s->blocked_until && (int32_t)(s->blocked_until - s->last_ms) > 0;
    portEXIT_CRITICAL(&s_rate_lock);
    return blocked;
}

static void record(uint32_t ip, bool success)
{
    portENTER_CRITICAL(&s_rate_lock);
    rate_slot_t *s = slot_for(ip);
    if (success) {
        s->fails = 0;
        s->blocked_until = 0;
    } else if (++s->fails >= RATE_MAX_FAILS) {
        s->fails = 0;
        s->blocked_until = now_ms() + RATE_BLOCK_MS;
    }
    portEXIT_CRITICAL(&s_rate_lock);
}

static bool is_ipv4(const char *h, size_t n)
{
    int dots = 0;
    for (size_t i = 0; i < n; i++) {
        if (h[i] == '.') {
            dots++;
        } else if (!isdigit((unsigned char)h[i])) {
            return false;
        }
    }
    return dots == 3;
}

static bool host_allowed(httpd_req_t *req)
{
    char host[64];
    if (httpd_req_get_hdr_value_str(req, "Host", host, sizeof(host)) != ESP_OK) {
        return false;
    }
    size_t n = strcspn(host, ":");      /* strip the port */
    for (size_t i = 0; i < n; i++) {
        host[i] = (char)tolower((unsigned char)host[i]);
    }
    if (is_ipv4(host, n)) {
        return true;
    }
    const size_t prefix = strlen(APP_MDNS_HOST_PREFIX), suffix = strlen(".local");
    return n > prefix + suffix && !strncmp(host, APP_MDNS_HOST_PREFIX, prefix) && !strncmp(host + n - suffix, ".local", suffix);
}

bool api_authorize(httpd_req_t *req, char phone_id[PHONE_ID_MAX + 1])
{
    if (!host_allowed(req) || httpd_req_get_hdr_value_len(req, "Origin") > 0) {
        api_send_error(req, "403 Forbidden", "FORBIDDEN");
        return false;
    }
    uint32_t ip = peer_ip(req);
    if (is_blocked(ip)) {
        api_send_error(req, "429 Too Many Requests", "RATE_LIMITED");
        return false;
    }
    char auth[16 + PHONE_TOKEN_LEN + 8] = {0};
    bool ok = httpd_req_get_hdr_value_str(req, "Authorization", auth, sizeof(auth)) == ESP_OK &&
              !strncmp(auth, "Bearer ", 7) && phones_verify(auth + 7, phone_id);
    memset(auth, 0, sizeof(auth));
    record(ip, ok);
    if (!ok) {
        ESP_LOGW(TAG, "unauthorized request");
        api_send_error(req, "401 Unauthorized", "UNAUTHORIZED");
    }
    return ok;
}

esp_err_t api_send_json(httpd_req_t *req, const char *status, cJSON *body)
{
    char *text = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);
    httpd_resp_set_status(req, status);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    esp_err_t err = httpd_resp_sendstr(req, text ? text : "{}");
    free(text);
    return err;
}

esp_err_t api_send_error(httpd_req_t *req, const char *status, const char *code)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddStringToObject(j, "error", code);
    return api_send_json(req, status, j);
}

esp_err_t api_send_ok(httpd_req_t *req)
{
    cJSON *j = cJSON_CreateObject();
    cJSON_AddBoolToObject(j, "ok", true);
    return api_send_json(req, "200 OK", j);
}
