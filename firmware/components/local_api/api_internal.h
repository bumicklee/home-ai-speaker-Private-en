/* Shared internals of local_api */
#pragma once

#include <stdbool.h>
#include "cJSON.h"
#include "device_api.h"
#include "esp_http_server.h"

/**
 * Checks the request: Host (DNS rebinding), Origin (browser), failure rate limit, Bearer token.
 * If it fails, returns false with the error response already sent. phone_id may be NULL.
 */
bool api_authorize(httpd_req_t *req, char phone_id[PHONE_ID_MAX + 1]);

/* Responses (ownership of the cJSON is handed over) */
esp_err_t api_send_json(httpd_req_t *req, const char *status, cJSON *body);
esp_err_t api_send_error(httpd_req_t *req, const char *status, const char *code);
esp_err_t api_send_ok(httpd_req_t *req);

/* WebSocket events (api_events.c) */
esp_err_t api_events_register(httpd_handle_t server);
void      api_events_on_close(int sockfd);
