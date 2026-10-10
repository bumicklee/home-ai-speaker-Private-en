/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * gpt-live-1 voice session. Ported from live_voice.c in the original firmware (waveshare-ai-speaker-assistant).
 * Kept as is: external TLS transport + WebSocket (control frames passed through), TCP_NODELAY, 64ms upload batches,
 *   response queue backpressure, delegation event tracking, 60-second idle timeout / 10 minutes max, 15-second usage wait after session.close,
 *   hang-up phrases, logging fixed failure text only (external response bodies and headers are never logged).
 * Changed:
 *   - Tool execution is handed to the on_tool_calls handler (assistant tool worker). Results come back via the outbound queue
 *   - API keys from secret_store, Wi-Fi from net, time from the RTC-restored value first
 *   - State is reported with APP_EVT_VOICE_STATE, failures with APP_EVT_ERROR
 *   - Model name is the app_config.h default
 */
#include "live_voice.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "app_config.h"
#include "audio_core.h"
#include "delegation.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_transport_ssl.h"
#include "esp_transport_ws.h"
#include "esp_websocket_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "gemini_live.h"
#include "hangup_phrase.h"
#include "lwip/sockets.h"
#include "mbedtls/base64.h"
#include "net.h"
#include "saver_voice.h"
#include "secret_store.h"
#include "settings.h"
#include "wake.h"

static const char *TAG = "LIVE";

#define LIVE_URI            "wss://api.openai.com/v1/live/sessions"
#define LIVE_PATH           "/v1/live/sessions"
#define MESSAGE_MAX         (128 * 1024)
#define INPUT_QUEUE_FRAMES  64
#define INPUT_FRAME_SAMPLES 512
#define OUTBOUND_QUEUE      6
#define STARTUP_TIMEOUT_MS  20000
#define CONNECT_TIMEOUT_MS  20000
#define WIFI_WAIT_MS        15000
#define CLOCK_WAIT_MS       20000

typedef struct {
    size_t bytes;
    int16_t samples[INPUT_FRAME_SAMPLES];
} input_frame_t;

/* Upload batch: up to 64ms (1,024 samples = 2,048 bytes) -> base64 -> JSON */
typedef struct {
    uint8_t pcm[2048];
    char encoded[2733];
    char json[2816];
} upload_batch_t;

static live_voice_handlers_t s_handlers;
static upload_batch_t *s_upload;
static QueueHandle_t s_inputs;      /* mic -> upload */
static QueueHandle_t s_responses;   /* WebSocket receive -> parse task (char*) */
static QueueHandle_t s_outbound;    /* tool results and instructions -> session task (cJSON*) */
static SemaphoreHandle_t s_responses_idle;

static atomic_bool s_busy, s_ready, s_stopping, s_connected, s_finalized, s_failed;
static atomic_uint s_activity_ms, s_generation;
static atomic_int s_usage_seconds;
static atomic_int s_state = VOICE_IDLE;
static _Atomic(const char *) s_status = "Ready";

static char *s_message;
static size_t s_message_used;
static int s_message_opcode;
static hangup_phrase_t s_hangup;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void set_state(voice_state_t state)
{
    if (atomic_exchange(&s_state, state) != (int)state) {
        app_events_post(APP_EVT_VOICE_STATE, &state, sizeof(state), 0);
    }
}

/*
 * Saver mode (saver_voice.c) also shares this file's s_busy, s_state, s_ready, s_status, s_generation, s_stopping
 * (docs/design-voice-saver-mode.md 11.5: live_voice_start/stop/active/ready/state look the same from outside).
 * saver_voice.c touches them only through these small pass-through functions (saver_voice.h). The Live path (run_session etc.) is unchanged.
 */
static atomic_bool s_saver_active;        /* is the busy session the saver engine (for live_voice_barge_in) */
static atomic_bool s_gemini_live_active;  /* is the busy session the Gemini Live engine (stage 3, for text/instruction routing) */

void voice_shared_set_state(voice_state_t state) { set_state(state); }
void voice_shared_set_ready(bool ready) { atomic_store(&s_ready, ready); }
void voice_shared_set_status(const char *text) { atomic_store(&s_status, text); }
bool voice_shared_stopping(void) { return atomic_load(&s_stopping); }

void voice_shared_end(bool had_error)
{
    /* had_error=true means the caller already set the end reason with voice_shared_set_status() (not overwritten) */
    if (!had_error) {
        atomic_store(&s_status, "Ready");
    }
    atomic_store(&s_ready, false);
    atomic_store(&s_saver_active, false);
    atomic_store(&s_gemini_live_active, false);
    atomic_store(&s_busy, false);
    set_state(VOICE_IDLE);
}

const live_voice_handlers_t *voice_shared_handlers(void)
{
    return &s_handlers;
}

bool live_voice_active(void) { return atomic_load(&s_busy); }
bool live_voice_ready(void) { return atomic_load(&s_ready) && !atomic_load(&s_stopping); }
voice_state_t live_voice_state(void) { return atomic_load(&s_state); }
const char *live_voice_status(void) { return atomic_load(&s_status); }
unsigned live_voice_generation(void) { return atomic_load(&s_generation); }

void live_voice_set_handlers(const live_voice_handlers_t *handlers)
{
    s_handlers = *handlers;
}

void live_voice_stop(void)
{
    if (atomic_load(&s_busy) && !atomic_exchange(&s_stopping, true)) {
        set_state(VOICE_CLOSING);
    }
}

void live_voice_barge_in(void)
{
    if (!atomic_load(&s_busy)) {
        return;
    }
    if (atomic_load(&s_saver_active)) {
        saver_voice_barge_in();     /* stop playback only and keep listening (Section 11.5) */
        return;
    }
    live_voice_stop();              /* Live (both openai.live and gemini.live): end the conversation as before */
}

/* Record fixed text only. Keep only the first failure */
static void fail(const char *text, app_error_t code)
{
    bool expected = false;
    if (atomic_compare_exchange_strong(&s_failed, &expected, true)) {
        atomic_store(&s_status, text);
        ESP_LOGW(TAG, "%s (internal free %u)", text,
                 (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
    }
    live_voice_stop();
}

/*
 * What restarted the idle timer (diagnostics, 2026-10-04 "no speech for over 30 s but the conversation didn't end").
 * Counts per type only; no content is kept.
 */
typedef enum { ACT_START, ACT_AUDIO, ACT_IN_TEXT, ACT_OUT_TEXT, ACT_EVENT, ACT_COUNT } activity_t;
static const char *const ACT_NAMES[ACT_COUNT] = {"start", "speaker audio", "heard speech", "assistant text", "backend event"};
static atomic_int s_last_act;
static atomic_uint s_act_count[ACT_COUNT];

static void touch_activity(activity_t why)
{
    atomic_store(&s_activity_ms, now_ms());
    atomic_store(&s_last_act, why);
    atomic_fetch_add(&s_act_count[why], 1);
}

/* ── Response parsing ────────────────────────────────────────────── */

static void handle_audio_delta(const cJSON *root)
{
    const cJSON *delta = cJSON_GetObjectItem(root, "delta");
    if (!cJSON_IsString(delta)) {
        return;
    }
    size_t encoded = strlen(delta->valuestring), capacity = encoded / 4 * 3 + 4, decoded = 0;
    uint8_t *pcm = heap_caps_malloc(capacity, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!pcm || mbedtls_base64_decode(pcm, capacity, &decoded, (const uint8_t *)delta->valuestring, encoded) != 0 ||
        decoded % 2) {
        fail("Invalid voice audio", APP_ERR_VOICE_INTERNAL);
    } else if (decoded) {
        /* The transcript can arrive well before the audio. Speaking a long reply also counts as activity.
         * Silent chunks are excluded (the server kept sending silence after speech ended, so the conversation never ended, 2026-10-04) */
        const int16_t *pcm16 = (const int16_t *)pcm;
        for (size_t i = 0; i < decoded / 2; i++) {
            if (pcm16[i] > 200 || pcm16[i] < -200) {
                touch_activity(ACT_AUDIO);
                break;
            }
        }
        if (!audio_core_voice_enqueue((const int16_t *)pcm, decoded / 2)) {
            fail("Speaker backlog", APP_ERR_VOICE_INTERNAL);
        }
    }
    free(pcm);
}

static void parse_message(const char *text)
{
    cJSON *root = cJSON_Parse(text);
    if (!root) {
        fail("Invalid voice response", APP_ERR_VOICE_INTERNAL);
        return;
    }
    const cJSON *type = cJSON_GetObjectItem(root, "type");
    const char *t = cJSON_IsString(type) ? type->valuestring : "";

    if (!strcmp(t, "session.started")) {
        hangup_phrase_reset(&s_hangup);
        touch_activity(ACT_START);
        atomic_store(&s_ready, true);
        atomic_store(&s_status, "Listening");
        set_state(VOICE_LIVE);
        audio_core_tone();
    } else if (!strcmp(t, "session.output_audio.delta") && !atomic_load(&s_stopping)) {
        handle_audio_delta(root);
    } else if (!strcmp(t, "session.input_transcript.delta") || !strcmp(t, "session.output_transcript.delta")) {
        const cJSON *delta = cJSON_GetObjectItem(root, "delta");
        if (cJSON_IsString(delta) && delta->valuestring[0]) {
            touch_activity(!strcmp(t, "session.input_transcript.delta") ? ACT_IN_TEXT : ACT_OUT_TEXT);
            if (s_handlers.on_transcript) {
                s_handlers.on_transcript(!strcmp(t, "session.input_transcript.delta"), delta->valuestring);
            }
            /* Transcript content is never logged (Section 2.2) */
            if (!strcmp(t, "session.input_transcript.delta") && live_voice_ready()) {
                hangup_phrase_feed(&s_hangup, delta->valuestring, now_ms());
                if (s_handlers.on_user_input) {
                    s_handlers.on_user_input();
                }
            }
        }
    } else if (!strcmp(t, "response.event") && !atomic_load(&s_stopping)) {
        touch_activity(ACT_EVENT);
        cJSON *calls = delegation_event(root);
        if (calls) {
            if (s_handlers.on_tool_calls) {
                s_handlers.on_tool_calls(calls, atomic_load(&s_generation));
            } else {
                cJSON_Delete(calls);
            }
        }
    } else if (!strcmp(t, "session.closed")) {
        const cJSON *seconds = cJSON_GetObjectItem(cJSON_GetObjectItem(root, "usage"), "seconds");
        if (cJSON_IsNumber(seconds)) {
            atomic_store(&s_usage_seconds, seconds->valueint);
        }
        atomic_store(&s_finalized, true);
        live_voice_stop();
    } else if (!strcmp(t, "error")) {
        fail("OpenAI rejected the session", APP_ERR_VOICE_REJECTED);
    }
    cJSON_Delete(root);
}

static void response_task(void *arg)
{
    for (;;) {
        char *text = NULL;
        if (xQueueReceive(s_responses, &text, pdMS_TO_TICKS(100)) == pdTRUE) {
            if (text) {
                parse_message(text);
                free(text);
            } else {
                xSemaphoreGive(s_responses_idle);   /* session end barrier */
            }
        }
        if (live_voice_ready() && hangup_phrase_ready(&s_hangup, now_ms())) {
            ESP_LOGI(TAG, "hangup phrase heard");
            atomic_store(&s_status, "Hangup phrase heard");
            live_voice_stop();
            audio_core_voice_clear();
        }
    }
}

/* ── WebSocket events ─────────────────────────────────────── */

static void queue_message(void)
{
    s_message[s_message_used] = '\0';
    char *copy = heap_caps_malloc(s_message_used + 1, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!copy) {
        fail("Voice response allocation failed", APP_ERR_VOICE_INTERNAL);
        return;
    }
    memcpy(copy, s_message, s_message_used + 1);
    /* When receiving outpaces parsing, wait briefly instead of dropping at once. Sending has its own lock, so uploads continue */
    if (xQueueSend(s_responses, &copy, 0) != pdTRUE &&
        xQueueSend(s_responses, &copy, pdMS_TO_TICKS(250)) != pdTRUE) {
        free(copy);
        if (!atomic_load(&s_stopping)) {
            fail("Voice response backlog", APP_ERR_VOICE_INTERNAL);
        }
    }
}

static void websocket_event(void *arg, esp_event_base_t base, int32_t id, void *raw)
{
    esp_websocket_event_data_t *event = raw;
    if (id == WEBSOCKET_EVENT_CONNECTED) {
        int fd = esp_transport_get_socket((esp_transport_handle_t)arg), enabled = 1;
        if (fd < 0 || setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled)) != 0) {
            fail("Could not configure voice socket", APP_ERR_VOICE_CONNECT);
            return;
        }
        atomic_store(&s_connected, true);
        return;
    }
    if (id == WEBSOCKET_EVENT_ERROR || id == WEBSOCKET_EVENT_DISCONNECTED || id == WEBSOCKET_EVENT_CLOSED) {
        if (!atomic_load(&s_stopping)) {
            if (event->error_handle.error_type == WEBSOCKET_ERROR_TYPE_TCP_TRANSPORT) {
                ESP_LOGW(TAG, "transport error: errno %d, tls 0x%x", event->error_handle.esp_transport_sock_errno,
                         event->error_handle.esp_tls_stack_err);
            }
            fail(event->error_handle.error_type == WEBSOCKET_ERROR_TYPE_PONG_TIMEOUT ? "Voice heartbeat timed out"
                                                                                     : "Voice connection ended",
                 APP_ERR_VOICE_DROPPED);
        }
        atomic_store(&s_connected, false);
        return;
    }
    if (id != WEBSOCKET_EVENT_DATA || (event->op_code != 1 && event->op_code != 0)) {
        return;
    }
    /* Join text message fragments */
    if (event->payload_offset == 0 && event->op_code == 1) {
        s_message_used = 0;
        s_message_opcode = 1;
    }
    if (s_message_opcode != 1 || event->data_len < 0 || s_message_used + event->data_len >= MESSAGE_MAX) {
        fail("Voice response exceeds buffer", APP_ERR_VOICE_INTERNAL);
        return;
    }
    memcpy(s_message + s_message_used, event->data_ptr, event->data_len);
    s_message_used += event->data_len;
    if (event->fin && event->payload_offset + event->data_len == event->payload_len) {
        queue_message();
        s_message_used = 0;
        s_message_opcode = 0;
    }
}

/* ── Sending ─────────────────────────────────────────────────── */

static bool send_json(esp_websocket_client_handle_t client, cJSON *event)
{
    char *text = cJSON_PrintUnformatted(event);
    cJSON_Delete(event);
    if (!text) {
        return false;
    }
    size_t n = strlen(text);
    bool ok = esp_websocket_client_send_text(client, text, n, pdMS_TO_TICKS(1000)) == (int)n;
    free(text);
    return ok;
}

/* outbound item: {"generation": n, "events": [...], "respond": bool} */
static bool send_outbound(esp_websocket_client_handle_t client, cJSON *item)
{
    const cJSON *generation = cJSON_GetObjectItem(item, "generation");
    if (!cJSON_IsNumber(generation) || (unsigned)generation->valuedouble != atomic_load(&s_generation)) {
        return true;    /* discard results from an earlier session */
    }
    cJSON *events = cJSON_DetachItemFromObject(item, "events");
    cJSON *event;
    while (events && (event = cJSON_DetachItemFromArray(events, 0))) {
        if (!send_json(client, event)) {
            cJSON_Delete(events);
            return false;
        }
    }
    cJSON_Delete(events);
    if (cJSON_IsTrue(cJSON_GetObjectItem(item, "respond"))) {
        return send_json(client, cJSON_Parse("{\"type\":\"response.create\"}"));
    }
    return true;
}

static esp_err_t push_outbound(cJSON *events, bool respond, unsigned generation)
{
    cJSON *item = cJSON_CreateObject();
    if (!item || !events) {
        cJSON_Delete(item);
        cJSON_Delete(events);
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddNumberToObject(item, "generation", generation);
    cJSON_AddItemToObject(item, "events", events);
    cJSON_AddBoolToObject(item, "respond", respond);
    if (xQueueSend(s_outbound, &item, 0) != pdTRUE) {
        cJSON_Delete(item);
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

esp_err_t live_voice_submit_tool_outputs(cJSON *outputs, unsigned generation)
{
    cJSON *events = cJSON_CreateArray();
    const cJSON *out;
    cJSON_ArrayForEach(out, outputs) {
        cJSON *event = cJSON_CreateObject(), *item = cJSON_AddObjectToObject(event, "item");
        cJSON_AddStringToObject(event, "type", "response.item.create");
        cJSON_AddStringToObject(item, "type", "function_call_output");
        cJSON_AddItemToObject(item, "call_id", cJSON_Duplicate(cJSON_GetObjectItem(out, "call_id"), true));
        cJSON_AddItemToObject(item, "output", cJSON_Duplicate(cJSON_GetObjectItem(out, "output"), true));
        cJSON_AddItemToArray(events, event);
    }
    cJSON_Delete(outputs);
    esp_err_t err = push_outbound(events, true, generation);
    if (err != ESP_OK && live_voice_ready()) {
        fail("Device tool queue full", APP_ERR_VOICE_INTERNAL);
    }
    return err;
}

esp_err_t live_voice_text(const char *text)
{
    if (atomic_load(&s_saver_active)) {
        /* Saver mode: synthesize as is without the AI, then back to listening (Section 11.7; only reminder sentences take this path for now) */
        return saver_voice_text(text);
    }
    if (atomic_load(&s_gemini_live_active)) {
        /* Gemini Live (stage 3): send as a clientContent user turn (request 5, gemini_live_proto.h header) */
        return gemini_live_text(text);
    }
    if (!live_voice_ready() || !text || !text[0] || strlen(text) > 600) {
        return ESP_ERR_INVALID_STATE;
    }
    cJSON *event = cJSON_Parse("{\"type\":\"response.item.create\",\"item\":{\"type\":\"message\",\"role\":\"user\",\"content\":[]}}");
    if (!event) {
        return ESP_ERR_NO_MEM;
    }
    cJSON *part = cJSON_CreateObject();
    cJSON_AddStringToObject(part, "type", "input_text");
    cJSON_AddStringToObject(part, "text", text);
    cJSON_AddItemToArray(cJSON_GetObjectItem(cJSON_GetObjectItem(event, "item"), "content"), part);
    cJSON *events = cJSON_CreateArray();
    cJSON_AddItemToArray(events, event);
    if (s_handlers.on_user_input) {
        s_handlers.on_user_input();     /* a request sent as text is user input too */
    }
    return push_outbound(events, true, atomic_load(&s_generation));
}

bool live_voice_instruction(const char *text)
{
    if (atomic_load(&s_gemini_live_active)) {
        /* Gemini Live has no dedicated "append to instructions" message (checked 2026-10) -> same path (clientContent) */
        return gemini_live_text(text) == ESP_OK;
    }
    if (!live_voice_ready()) {
        return false;
    }
    cJSON *event = cJSON_CreateObject();
    cJSON_AddStringToObject(event, "type", "session.instructions.append");
    cJSON_AddNullToObject(event, "delegation_id");
    cJSON_AddStringToObject(event, "content", text);
    cJSON *events = cJSON_CreateArray();
    cJSON_AddItemToArray(events, event);
    return push_outbound(events, false, atomic_load(&s_generation)) == ESP_OK;
}

/* Called from the mic task. Never blocks; when backed up, drops the oldest audio */
static void live_voice_feed(const int16_t *samples, size_t count)
{
    if (!atomic_load(&s_ready) || atomic_load(&s_stopping)) {
        return;
    }
    while (count) {
        size_t take = count > INPUT_FRAME_SAMPLES ? INPUT_FRAME_SAMPLES : count;
        input_frame_t frame = {.bytes = take * sizeof(int16_t)};
        memcpy(frame.samples, samples, frame.bytes);
        if (xQueueSend(s_inputs, &frame, 0) != pdTRUE) {
            input_frame_t stale;
            xQueueReceive(s_inputs, &stale, 0);
            xQueueSend(s_inputs, &frame, 0);
        }
        samples += take;
        count -= take;
    }
}

/* ── Session ─────────────────────────────────────────────────── */

static bool wait_flag(atomic_bool *flag, uint32_t timeout_ms)
{
    for (uint32_t waited = 0; waited < timeout_ms && !atomic_load(flag) && !atomic_load(&s_stopping); waited += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    return atomic_load(flag);
}

/* Batch up to 64ms before sending (so there's no TLS send for every 16ms AEC chunk) */
static bool upload_audio(esp_websocket_client_handle_t client, input_frame_t *frame)
{
    size_t bytes = frame->bytes, length = 0;
    unsigned frames = 1;
    memcpy(s_upload->pcm, frame->samples, bytes);
    while (bytes < sizeof(s_upload->pcm) && frames < 4 && !atomic_load(&s_stopping)) {
        if (xQueuePeek(s_inputs, frame, pdMS_TO_TICKS(20)) != pdTRUE || frame->bytes > sizeof(s_upload->pcm) - bytes ||
            xQueueReceive(s_inputs, frame, 0) != pdTRUE) {
            break;
        }
        memcpy(s_upload->pcm + bytes, frame->samples, frame->bytes);
        bytes += frame->bytes;
        frames++;
    }
    if (mbedtls_base64_encode((uint8_t *)s_upload->encoded, sizeof(s_upload->encoded), &length, s_upload->pcm, bytes)) {
        return false;
    }
    s_upload->encoded[length] = '\0';
    int size = snprintf(s_upload->json, sizeof(s_upload->json),
                        "{\"type\":\"session.input_audio.append\",\"audio\":\"%s\"}", s_upload->encoded);
    if (size < 0 || size >= (int)sizeof(s_upload->json)) {
        return false;
    }
    return esp_websocket_client_send_text(client, s_upload->json, size, pdMS_TO_TICKS(1000)) == size;
}

/* Time limits for the next session only (English lesson: lesson length, 2 minutes even with silence). 0 means the default */
static atomic_uint s_next_max_ms, s_next_idle_ms;

void live_voice_set_next_limits(uint32_t max_ms, uint32_t idle_ms)
{
    atomic_store(&s_next_max_ms, max_ms);
    atomic_store(&s_next_idle_ms, idle_ms);
}

void voice_shared_take_next_limits(uint32_t *max_ms, uint32_t *idle_ms)
{
    *max_ms = atomic_exchange(&s_next_max_ms, 0);
    *idle_ms = atomic_exchange(&s_next_idle_ms, 0);
}

static void reset_session_state(void)
{
    atomic_store(&s_ready, false);
    atomic_store(&s_connected, false);
    atomic_store(&s_finalized, false);
    atomic_store(&s_failed, false);
    atomic_store(&s_usage_seconds, -1);
    xQueueReset(s_inputs);
    audio_core_voice_clear();
    delegation_reset();
    s_message_used = 0;
    s_message_opcode = 0;
}

static TaskHandle_t s_session;

/* One conversation (inside the session task) */
/*
 * Reserving the spot for the OpenAI WebSocket task stack (Chapter 7, Bug 3).
 * esp_websocket_client creates its task with xTaskCreatePinnedToCore, so its stack (12KB) must be one contiguous block of internal RAM.
 * After a long uptime or opening and closing the BLE window, internal RAM had 37KB in total but no 12KB block, so conversations wouldn't start.
 * So that size is reserved at boot, released right before connecting, and reserved again when the conversation ends.
 */
#define WS_TASK_STACK    12288
#define WS_STACK_RESERVE (WS_TASK_STACK + 512)
static void *s_ws_reserve;

static void ws_stack_reserve(void)
{
    /* The idle task returns a finished WebSocket task's stack a little later -> retry a few times with waits */
    for (int i = 0; !s_ws_reserve && i < 10; i++) {
        s_ws_reserve = heap_caps_malloc(WS_STACK_RESERVE, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
        if (!s_ws_reserve) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
    }
    if (!s_ws_reserve) {
        ESP_LOGW(TAG, "could not reserve %d B for the voice task (largest internal %u)", WS_STACK_RESERVE,
                 (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
    }
}

static void ws_stack_release(void)
{
    free(s_ws_reserve);
    s_ws_reserve = NULL;
}

/* Saver mode also releases this spot during a conversation, because HTTPS (TLS) uses internal RAM (2026-10-04 on real hardware:
 * Telegram TLS during a Saver mode conversation gave "esp-aes: Failed to allocate memory") */
void voice_shared_reserve_release(void) { ws_stack_release(); }
void voice_shared_reserve_take(void) { ws_stack_reserve(); }

static void run_session(void)
{
    esp_websocket_client_handle_t client = NULL;
    esp_transport_handle_t tls = NULL, ws = NULL;
    const char *limit_reason = NULL;
    char *start_event = NULL;
    static char key[513], headers[560];

    reset_session_state();
    atomic_store(&s_status, "Connecting Wi-Fi");

    /* Unload the wake-word model to free internal memory for the TLS connection */
    if (!wake_pause()) {
        fail("Wake detector did not release memory", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    net_set_power_save(false);      /* audio streaming doesn't get along with Wi-Fi power saving */

    if (!net_wait_connected(WIFI_WAIT_MS)) {
        fail("Wi-Fi unavailable", APP_ERR_WIFI);
        goto cleanup;
    }
    /* If there's a time restored from the RTC, start TLS right away. Otherwise wait for SNTP */
    atomic_store(&s_status, "Checking clock");
    for (uint32_t w = 0; w < CLOCK_WAIT_MS && !net_time_valid() && !atomic_load(&s_stopping); w += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!net_time_valid()) {
        fail("Clock sync failed", APP_ERR_CLOCK);
        goto cleanup;
    }
    if (atomic_load(&s_stopping)) {
        goto cleanup;
    }

    size_t key_len = sizeof(key) - 1;
    if (secret_get(SECRET_OPENAI_KEY, key, &key_len) != ESP_OK || key_len == 0) {
        fail("OpenAI API key not set", APP_ERR_NO_API_KEY);
        goto cleanup;
    }
    key[key_len] = '\0';
    snprintf(headers, sizeof(headers), "Authorization: Bearer %s\r\n", key);
    memset(key, 0, sizeof(key));

    tls = esp_transport_ssl_init();
    if (tls) {
        esp_transport_ssl_crt_bundle_attach(tls, esp_crt_bundle_attach);
        ws = esp_transport_ws_init(tls);
    }
    if (!ws) {
        fail("Could not allocate voice transport", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    /* With an external transport, the client's default settings are bypassed.
     * PONG/CLOSE frames must be passed through for heartbeat and close handling to work */
    const esp_transport_ws_config_t ws_cfg = {
        .ws_path = LIVE_PATH,
        .headers = headers,
        .propagate_control_frames = true,
    };
    if (esp_transport_ws_set_config(ws, &ws_cfg) != ESP_OK) {
        fail("Could not configure voice transport", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    const esp_websocket_client_config_t cfg = {
        .uri = LIVE_URI,
        .port = 443,
        .headers = headers,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .disable_auto_reconnect = true,
        .buffer_size = 4096,
        .task_stack = WS_TASK_STACK,
        .network_timeout_ms = 5000,
        .ext_transport = ws,
    };
    client = esp_websocket_client_init(&cfg);
    if (!client) {
        fail("Could not allocate voice connection", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    esp_websocket_register_events(client, WEBSOCKET_EVENT_ANY, websocket_event, tls);
    atomic_store(&s_status, "Connecting to OpenAI");
    ws_stack_release();     /* let the WebSocket task stack use the reserved spot */
    if (esp_websocket_client_start(client) != ESP_OK || !wait_flag(&s_connected, CONNECT_TIMEOUT_MS)) {
        fail("OpenAI connection failed", APP_ERR_VOICE_CONNECT);
        goto cleanup;
    }

    start_event = s_handlers.build_start_event ? s_handlers.build_start_event() : NULL;
    if (!start_event ||
        esp_websocket_client_send_text(client, start_event, strlen(start_event), pdMS_TO_TICKS(2000)) !=
            (int)strlen(start_event)) {
        fail("Session startup failed", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    free(start_event);
    start_event = NULL;

    uint32_t began = now_ms();
    uint32_t max_ms = atomic_exchange(&s_next_max_ms, 0), idle_ms = atomic_exchange(&s_next_idle_ms, 0);
    max_ms = max_ms ? max_ms : APP_VOICE_MAX_SESSION_MS;
    idle_ms = idle_ms ? idle_ms : APP_VOICE_IDLE_TIMEOUT_MS;
    ESP_LOGI(TAG, "limits: idle %u s, max %u s", (unsigned)(idle_ms / 1000), (unsigned)(max_ms / 1000));
    for (int i = 0; i < ACT_COUNT; i++) {
        atomic_store(&s_act_count[i], 0);
    }
    uint32_t act_log_ms = began;
    while (!atomic_load(&s_stopping)) {
        if (s_handlers.on_tick) {
            s_handlers.on_tick();
        }
        uint32_t now = now_ms();
        if (!atomic_load(&s_ready) && now - began > STARTUP_TIMEOUT_MS) {
            fail("Voice startup timed out", APP_ERR_VOICE_CONNECT);
            break;
        }
        /*
         * The idle timer counts only "time the person hasn't spoken" (2026-10-04, user). Assistant audio chunks arrive faster than
         * real speaking speed, so activity is the time the assistant's voice actually plays from the speaker, not the chunks.
         * So it doesn't end in the middle of a long reply; counting starts after the assistant finishes speaking.
         */
        if (atomic_load(&s_ready) && audio_core_voice_playing()) {
            touch_activity(ACT_AUDIO);
        }
        /* Diagnostics: every 10 s, the idle time and what restarted it (counts per type, no content) */
        if (atomic_load(&s_ready) && now - act_log_ms >= 10000) {
            act_log_ms = now;
            int32_t quiet = (int32_t)(now - atomic_load(&s_activity_ms));
            ESP_LOGI(TAG, "idle %d/%u s, last: %s | 10 s: heard %u, assistant text %u, audio %u, events %u",
                     (int)(quiet > 0 ? quiet / 1000 : 0), (unsigned)(idle_ms / 1000), ACT_NAMES[atomic_load(&s_last_act)],
                     atomic_exchange(&s_act_count[ACT_IN_TEXT], 0), atomic_exchange(&s_act_count[ACT_OUT_TEXT], 0),
                     atomic_exchange(&s_act_count[ACT_AUDIO], 0), atomic_exchange(&s_act_count[ACT_EVENT], 0));
        }
        /* The response task may update the activity time after now, so compare with a signed difference */
        if (now - began > max_ms) {
            limit_reason = "Conversation limit reached";
        } else if (atomic_load(&s_ready) && (int32_t)(now - atomic_load(&s_activity_ms)) > (int32_t)idle_ms) {
            limit_reason = "Idle timeout";
        }
        if (limit_reason) {
            ESP_LOGI(TAG, "%s", limit_reason);
            atomic_store(&s_status, limit_reason);
            live_voice_stop();
            break;
        }

        cJSON *item = NULL;
        if (xQueueReceive(s_outbound, &item, 0) == pdTRUE) {
            bool ok = send_outbound(client, item);
            cJSON_Delete(item);
            if (!ok) {
                if (!atomic_load(&s_stopping)) {
                    fail("Device tool response failed", APP_ERR_VOICE_DROPPED);
                }
                break;
            }
        }

        input_frame_t frame;
        if (xQueueReceive(s_inputs, &frame, pdMS_TO_TICKS(20)) == pdTRUE && atomic_load(&s_ready)) {
            if (!upload_audio(client, &frame) && !atomic_load(&s_stopping)) {
                fail("Audio upload interrupted", APP_ERR_VOICE_DROPPED);
            }
        }
    }

cleanup:
    if (s_handlers.on_session_end) {
        s_handlers.on_session_end();
    }
    free(start_event);
    atomic_store(&s_ready, false);
    audio_core_voice_clear();
    if (client) {
        /* Send session.close and wait up to 15 s to get the final usage */
        if (atomic_load(&s_connected) && !atomic_load(&s_finalized)) {
            const char *close = "{\"type\":\"session.close\"}";
            esp_websocket_client_send_text(client, close, strlen(close), pdMS_TO_TICKS(1000));
            for (int i = 0; i < APP_VOICE_USAGE_WAIT_MS / 100 && !atomic_load(&s_finalized) && atomic_load(&s_connected); i++) {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
        }
        esp_websocket_client_stop(client);
        esp_websocket_client_destroy(client);
    }
    if (ws) {
        esp_transport_destroy(ws);
    }
    if (tls) {
        esp_transport_destroy(tls);
    }
    /* Wait until the parse task has handled all remaining messages before allowing the next session */
    char *barrier = NULL;
    xQueueSend(s_responses, &barrier, portMAX_DELAY);
    xSemaphoreTake(s_responses_idle, portMAX_DELAY);
    cJSON *stale = NULL;
    while (xQueueReceive(s_outbound, &stale, 0) == pdTRUE) {
        cJSON_Delete(stale);
    }
    /* Keep the failure text until the next session (checked before reset clears the failure flag) */
    bool failed = atomic_load(&s_failed);
    reset_session_state();
    memset(headers, 0, sizeof(headers));
    if (!failed && !limit_reason) {
        atomic_store(&s_status, "Ready");
    }
    /* So lesson limits don't carry over to the next normal conversation even if the connect step failed before the loop */
    atomic_store(&s_next_max_ms, 0);
    atomic_store(&s_next_idle_ms, 0);
    ESP_LOGI(TAG, "session ended (usage %d s)", atomic_load(&s_usage_seconds));
    net_set_power_save(true);
    ws_stack_reserve();     /* reserve the spot before reloading the wake-word model (before fragmentation) */
    wake_resume();
    atomic_store(&s_busy, false);
    set_state(VOICE_IDLE);
}

/*
 * The session task is created once at boot and kept (stack in PSRAM). Creating and deleting it per conversation
 * is risky, because a WithCaps task deleting itself needs another cleanup task in internal RAM (Chapter 7, Section 7.3)
 */
static void session_task(void *arg)
{
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        run_session();
    }
}

static void copy_str(char *dst, size_t dst_len, const char *src)
{
    if (!dst_len) {
        return;
    }
    size_t n = strlen(src);
    if (n >= dst_len) {
        n = dst_len - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

/*
 * Reads ai_provider, mode_openai, mode_gemini directly from NVS (the same setting strings in the assistant group,
 * a read-only copy separate from assistant.c's cache). live_voice can't REQUIRE assistant
 * (assistant REQUIRES live_voice, so the reverse would be a circular dependency). If unreadable, openai/live (safe default).
 */
static void read_voice_choice(char *provider, size_t provider_len, char *mode, size_t mode_len)
{
    copy_str(provider, provider_len, "openai");
    copy_str(mode, mode_len, "live");
    size_t len = 4096;
    char *buf = heap_caps_malloc(len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!buf) {
        return;
    }
    if (settings_get_str("assistant", "settings", buf, &len) == ESP_OK) {
        cJSON *s = cJSON_Parse(buf);
        if (s) {
            const cJSON *p = cJSON_GetObjectItemCaseSensitive(s, "ai_provider");
            if (cJSON_IsString(p) && !strcmp(p->valuestring, "gemini")) {
                copy_str(provider, provider_len, "gemini");
            }
            const cJSON *m = cJSON_GetObjectItemCaseSensitive(s, !strcmp(provider, "gemini") ? "mode_gemini" : "mode_openai");
            if (cJSON_IsString(m) && (!strcmp(m->valuestring, "live") || !strcmp(m->valuestring, "saver"))) {
                copy_str(mode, mode_len, m->valuestring);
            }
            cJSON_Delete(s);
        }
    }
    free(buf);
}

static TaskHandle_t s_saver_session;
static TaskHandle_t s_gemini_live_session;   /* stage 3: Gemini Live (gemini_live.c) */

esp_err_t live_voice_start(void)
{
    if (wake_is_testing() || audio_core_aec_suspended()) {
        return ESP_ERR_INVALID_STATE;     /* during a detection test, or mic processing suspended for the BLE window */
    }

    /* AI choice and Live/Saver mode (docs/design-voice-saver-mode.md 11.5) */
    bool force_live = s_handlers.force_openai_live && s_handlers.force_openai_live();
    char provider[8], mode[8];
    if (force_live) {
        copy_str(provider, sizeof(provider), "openai");
        copy_str(mode, sizeof(mode), "live");
    } else {
        read_voice_choice(provider, sizeof(provider), mode, sizeof(mode));
    }
    bool gemini = !strcmp(provider, "gemini");
    bool saver = !strcmp(mode, "saver");
    if (!secret_exists(gemini ? SECRET_GEMINI_KEY : SECRET_OPENAI_KEY)) {
        atomic_store(&s_status, gemini ? "Gemini API key not set" : "OpenAI API key not set");
        app_error_t code = APP_ERR_NO_API_KEY;
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
        return ESP_ERR_INVALID_STATE;
    }
    bool expected = false;
    if (!atomic_compare_exchange_strong(&s_busy, &expected, true)) {
        return ESP_ERR_INVALID_STATE;
    }
    atomic_store(&s_stopping, false);
    atomic_store(&s_saver_active, saver);
    atomic_store(&s_gemini_live_active, gemini && !saver);
    atomic_fetch_add(&s_generation, 1);
    set_state(VOICE_CONNECTING);
    TaskHandle_t target = saver ? s_saver_session : (gemini ? s_gemini_live_session : s_session);
    xTaskNotifyGive(target);
    return ESP_OK;
}

esp_err_t live_voice_init(void)
{
    static StaticQueue_t input_ctrl;
    uint8_t *input_storage = heap_caps_malloc(INPUT_QUEUE_FRAMES * sizeof(input_frame_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_upload = heap_caps_malloc(sizeof(upload_batch_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_message = heap_caps_malloc(MESSAGE_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!input_storage || !s_upload || !s_message) {
        return ESP_ERR_NO_MEM;
    }
    s_inputs = xQueueCreateStatic(INPUT_QUEUE_FRAMES, sizeof(input_frame_t), input_storage, &input_ctrl);
    s_responses = xQueueCreate(16, sizeof(char *));
    s_outbound = xQueueCreate(OUTBOUND_QUEUE, sizeof(cJSON *));
    s_responses_idle = xSemaphoreCreateBinary();
    if (!s_inputs || !s_responses || !s_outbound || !s_responses_idle) {
        return ESP_ERR_NO_MEM;
    }
    atomic_store(&s_usage_seconds, -1);
    ESP_ERROR_CHECK(audio_core_add_mic_sink(live_voice_feed));
    ws_stack_reserve();     /* early in boot, while internal RAM is still less fragmented */
    if (xTaskCreatePinnedToCoreWithCaps(session_task, "live_voice", 12288, NULL, 5, &s_session, 0,
                                        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    /* Only parses responses, queues playback, and tracks delegation (no flash access) -> stack in PSRAM (Chapter 7, Section 7.3) */
    if (xTaskCreatePinnedToCoreWithCaps(response_task, "voice_rx", 8192, NULL, 5, NULL, 0,
                                        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    /*
     * Saver mode session task (docs/design-voice-saver-mode.md 11.6). Unlike esp_websocket_client, esp_http_client
     * runs inside the calling task (it creates no task of its own) -> no internal RAM reservation like
     * ws_stack_reserve is needed. Stack in PSRAM (this task only), Core 0 (networking/HTTP on Core 0, Section 2.x rule).
     */
    esp_err_t err = saver_voice_init();
    if (err != ESP_OK) {
        return err;
    }
    if (xTaskCreatePinnedToCoreWithCaps(saver_voice_task_entry, "saver_voice", 12288, NULL, 5, &s_saver_session, 0,
                                        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    /*
     * Gemini Live session task (stage 3, docs/design-voice-saver-mode.md 2.5, 16.4). This engine also uses esp_websocket_client
     * (gemini_live.c), so it is created the same size as the live_voice session task (stack in PSRAM, Core 0). Only one of
     * the three engines runs at a time (guaranteed by s_busy) -> they share the ws_stack_reserve spot.
     */
    err = gemini_live_init();
    if (err != ESP_OK) {
        return err;
    }
    if (xTaskCreatePinnedToCoreWithCaps(gemini_live_task_entry, "gemini_live", 12288, NULL, 5, &s_gemini_live_session,
                                        0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}
