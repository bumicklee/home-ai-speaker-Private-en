/*
 * Real-time events WebSocket: GET /api/v1/events (design document Section 2.14).
 * - esp_http_server has no pre-handshake auth hook. At handshake time (the first call, with HTTP_GET)
 *   the headers are checked; if they are wrong, the connection is closed without sending a single event.
 * - Up to 5 concurrent connections. A ping every 30 seconds.
 * - App events (app_events) are turned into JSON and sent to every connection. Event handlers must not block, so
 *   the sending happens on the httpd task (httpd_queue_work).
 */
#include <stdlib.h>
#include <string.h>
#include "api_internal.h"
#include "app_events.h"
#include "audio_core.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "media_radio.h"
#include "messenger_telegram.h"
#include "lesson.h"
#include "media_spotify.h"
#include "freertos/FreeRTOS.h"

static const char *TAG = "API_WS";

#define MAX_CLIENTS  5
#define PING_MS      30000

static httpd_handle_t s_server;
static int s_fds[MAX_CLIENTS] = {-1, -1, -1, -1, -1};
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;

typedef struct {
    httpd_ws_type_t type;
    size_t len;
    char text[];
} ws_msg_t;

static bool add_client(int fd)
{
    bool added = false;
    portENTER_CRITICAL(&s_lock);
    for (int i = 0; i < MAX_CLIENTS && !added; i++) {
        if (s_fds[i] < 0) {
            s_fds[i] = fd;
            added = true;
        }
    }
    portEXIT_CRITICAL(&s_lock);
    return added;
}

void api_events_on_close(int sockfd)
{
    portENTER_CRITICAL(&s_lock);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (s_fds[i] == sockfd) {
            s_fds[i] = -1;
        }
    }
    portEXIT_CRITICAL(&s_lock);
}

/* Runs on the httpd task */
static void broadcast_work(void *arg)
{
    ws_msg_t *msg = arg;
    int fds[MAX_CLIENTS];
    portENTER_CRITICAL(&s_lock);
    memcpy(fds, s_fds, sizeof(fds));
    portEXIT_CRITICAL(&s_lock);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (fds[i] < 0) {
            continue;
        }
        if (httpd_ws_get_fd_info(s_server, fds[i]) != HTTPD_WS_CLIENT_WEBSOCKET) {
            api_events_on_close(fds[i]);
            continue;
        }
        httpd_ws_frame_t frame = {.type = msg->type, .payload = (uint8_t *)msg->text, .len = msg->len};
        if (httpd_ws_send_frame_async(s_server, fds[i], &frame) != ESP_OK) {
            httpd_sess_trigger_close(s_server, fds[i]);
        }
    }
    free(msg);
}

static void queue_frame(httpd_ws_type_t type, const char *text)
{
    size_t len = text ? strlen(text) : 0;
    ws_msg_t *msg = malloc(sizeof(ws_msg_t) + len + 1);
    if (!msg) {
        return;
    }
    msg->type = type;
    msg->len = len;
    memcpy(msg->text, text ? text : "", len + 1);
    if (httpd_queue_work(s_server, broadcast_work, msg) != ESP_OK) {
        free(msg);
    }
}

static void send_event(cJSON *event)
{
    char *text = cJSON_PrintUnformatted(event);
    cJSON_Delete(event);
    if (text) {
        queue_frame(HTTPD_WS_TYPE_TEXT, text);
        free(text);
    }
}

static const char *voice_name(voice_state_t s)
{
    static const char *const names[] = {"idle", "wake_ack", "connecting", "live", "closing"};
    return (unsigned)s < 5 ? names[s] : "idle";
}

static void on_app_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    cJSON *e = cJSON_CreateObject();
    switch ((app_event_id_t)id) {
    case APP_EVT_VOICE_STATE:
        cJSON_AddStringToObject(e, "event", "voice_state");
        cJSON_AddStringToObject(e, "state", voice_name(*(const voice_state_t *)data));
        break;
    case APP_EVT_SETTINGS_CHANGED:
        if (*(const app_setting_t *)data != APP_SETTING_VOLUME) {
            cJSON_Delete(e);
            return;
        }
        cJSON_AddStringToObject(e, "event", "volume");
        cJSON_AddNumberToObject(e, "value", audio_core_get_volume());
        break;
    case APP_EVT_MEDIA_STATE: {
        cJSON_Delete(e);
        /* Same format as /media/now. For Spotify, use the non-blocking cache (no HTTPS on the event task) */
        e = ((const app_media_event_t *)data)->source == MEDIA_SOURCE_SPOTIFY ? spotify_now_cached() : radio_now_json();
        cJSON_AddStringToObject(e, "event", "media_state");
        break;
    }
    case APP_EVT_TG_MESSAGE:
        /* The body is not sent (Section 2.14). Only the unread count */
        cJSON_AddStringToObject(e, "event", "tg_message");
        cJSON_AddNumberToObject(e, "unread", *(const int *)data);
        break;
    case APP_EVT_TG_PAIRED: {
        int64_t id = *(const int64_t *)data;
        cJSON_AddStringToObject(e, "event", "tg_paired");
        cJSON_AddNumberToObject(e, "chat_id", (double)id);
        const cJSON *c;
        cJSON *chats = telegram_chats();
        cJSON_ArrayForEach(c, chats) {
            if ((int64_t)cJSON_GetObjectItem(c, "chat_id")->valuedouble == id) {
                cJSON_AddItemToObject(e, "title", cJSON_Duplicate(cJSON_GetObjectItem(c, "title"), true));
                cJSON_AddItemToObject(e, "type", cJSON_Duplicate(cJSON_GetObjectItem(c, "type"), true));
            }
        }
        cJSON_Delete(chats);
        break;
    }
    case APP_EVT_TG_STATUS:
        cJSON_AddStringToObject(e, "event", "tg_status");
        cJSON_AddStringToObject(e, "state", telegram_state_name(*(const int *)data));
        break;
    case APP_EVT_WAKE_TEST:
        cJSON_AddStringToObject(e, "event", "wake_test");
        cJSON_AddNumberToObject(e, "detections", *(const unsigned *)data);
        break;
    case APP_EVT_LESSON:
        cJSON_Delete(e);
        e = lesson_json();
        cJSON_AddStringToObject(e, "event", "lesson");
        break;
    case APP_EVT_NOTES:
        cJSON_AddStringToObject(e, "event", "notes");
        cJSON_AddNumberToObject(e, "rev", *(const uint32_t *)data);
        break;
    case APP_EVT_REMINDER: {
        static const char *const ST[] = {"sent", "acked", "no_answer", "missed"};
        const app_notes_reminder_t *r = data;
        cJSON_AddStringToObject(e, "event", "reminder");
        cJSON_AddStringToObject(e, "id", r->id);
        cJSON_AddStringToObject(e, "status", (unsigned)r->status < 4 ? ST[r->status] : "sent");
        break;
    }
    case APP_EVT_ERROR:
        cJSON_AddStringToObject(e, "event", "error");
        cJSON_AddNumberToObject(e, "code", *(const app_error_t *)data);
        break;
    default:
        cJSON_Delete(e);
        return;
    }
    send_event(e);
}

static void ping_cb(void *arg)
{
    queue_frame(HTTPD_WS_TYPE_PING, NULL);
}

static esp_err_t events_handler(httpd_req_t *req)
{
    if (req->method == HTTP_GET) {
        /* Handshake: authenticate here */
        if (!api_authorize(req, NULL) || !add_client(httpd_req_to_sockfd(req))) {
            return ESP_FAIL;    /* close the session */
        }
        ESP_LOGI(TAG, "client connected");
        return ESP_OK;
    }
    /*
     * Control frames (PING, PONG, CLOSE) are also handled directly here (handle_ws_control_frames).
     * When they were left to httpd, reading the PONG the app sent in reply to the 30-second ping knocked the frames out of step ("WS frame is not properly masked")
     * and the session dropped and reconnected every 30 seconds (2026-10-03, real board). Data frames sent by the app are not used and are discarded.
     */
    httpd_ws_frame_t frame = {0};
    esp_err_t err = httpd_ws_recv_frame(req, &frame, 0);
    if (err != ESP_OK) {
        return err;
    }
    if (frame.len > 512) {
        /* Only the length was read, so the body is still in the socket. Close the session so the next frame is not misaligned */
        return ESP_FAIL;
    }
    uint8_t buf[513];
    if (frame.len) {
        frame.payload = buf;
        err = httpd_ws_recv_frame(req, &frame, frame.len);
        if (err != ESP_OK) {
            return err;
        }
    }
    switch (frame.type) {
    case HTTPD_WS_TYPE_PING: {
        httpd_ws_frame_t pong = {.final = true, .type = HTTPD_WS_TYPE_PONG, .payload = frame.payload, .len = frame.len};
        return httpd_ws_send_frame(req, &pong);
    }
    case HTTPD_WS_TYPE_CLOSE: {
        httpd_ws_frame_t close = {.final = true, .type = HTTPD_WS_TYPE_CLOSE};
        httpd_ws_send_frame(req, &close);
        return ESP_FAIL;    /* close the session */
    }
    default:
        return ESP_OK;      /* PONG, app text/binary: discard */
    }
}

esp_err_t api_events_register(httpd_handle_t server)
{
    s_server = server;
    static const httpd_uri_t uri = {
        .uri = "/api/v1/events",
        .method = HTTP_GET,
        .handler = events_handler,
        .is_websocket = true,
        .handle_ws_control_frames = true,
    };
    esp_err_t err = httpd_register_uri_handler(server, &uri);
    if (err != ESP_OK) {
        return err;
    }
    static const app_event_id_t ids[] = {APP_EVT_VOICE_STATE, APP_EVT_SETTINGS_CHANGED, APP_EVT_MEDIA_STATE, APP_EVT_TG_MESSAGE,
                                         APP_EVT_TG_PAIRED,   APP_EVT_TG_STATUS,        APP_EVT_WAKE_TEST,   APP_EVT_ERROR,
                                         APP_EVT_LESSON,      APP_EVT_NOTES,            APP_EVT_REMINDER};
    for (size_t i = 0; i < sizeof(ids) / sizeof(ids[0]); i++) {
        app_events_subscribe(ids[i], on_app_event, NULL);
    }
    const esp_timer_create_args_t args = {.callback = ping_cb, .name = "ws_ping"};
    esp_timer_handle_t timer;
    if (esp_timer_create(&args, &timer) == ESP_OK) {
        esp_timer_start_periodic(timer, PING_MS * 1000);
    }
    return ESP_OK;
}
