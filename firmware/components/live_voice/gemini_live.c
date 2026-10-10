/*
 * Gemini Live (stage 3) voice session: listening, thinking, tool calls and speaking all happen over one BidiGenerateContent
 * WebSocket connection (docs/design-voice-saver-mode.md Sections 2.5 and 16.4, stage 3. Checked 2026-10 against ai.google.dev/api/live,
 * /gemini-api/docs/live-api/get-started-websocket, /gemini-api/docs/live-api/tools,
 * /gemini-api/docs/live-api/capabilities). Follows the same structure as live_voice.c (gpt-live-1): one session task
 * (connection, mic upload) + one response-parsing task (esp_websocket_client, with the same ws_stack_reserve internal RAM
 * trick). Differences:
 *   - Only gemini_live_proto.c (pure logic, self-tested) knows the message shapes.
 *   - No backend delegation. When the model calls a tool directly (toolCall), the response-parsing task runs it right away
 *     (assistant_execute, tool_guard unchanged) and returns a toolResponse. I found no evidence in the docs that
 *     gemini-3.8-live supports asynchronous (NON_BLOCKING) tool calls, so calls stay blocking; instead the instructions say
 *     "for slow tools, say something short first" (request 4). It runs in the response-parsing task, so the session loop
 *     (mic upload) is not blocked meanwhile.
 *   - Barge-in: the server VAD reports it with serverContent.interrupted; just clear the playback queue (request 3).
 *   - A short press of the center button (Key2) already calls live_voice_stop() through the default branch of
 *     live_voice_barge_in() (same as Live mode; only saver is handled separately), so this file does nothing extra.
 *   - Authentication goes in the x-goog-api-key WebSocket upgrade header (?key= in the URL is avoided because it can end up
 *     in logs and proxies; same reason as x-goog-api-key in gemini.saver. Checked 2026-10 in the forum/docs: the header is accepted).
 *
 * Known limitation (documented, request 4): the response-parsing task handles messages one at a time in order and runs tools
 * synchronously inside that, so while handling a toolCall message it cannot see a toolCallCancellation that arrives later
 * (it filters only cancellations already queued before handling). Since gemini-3.8-live supports only synchronous calls,
 * a cancellation actually arriving too late to filter should be rare.
 *
 * Logs keep only the same shapes as LIVE (GLIVE: limits …, 10-second diagnostics, connection and end reasons, tool counts).
 * Transcribed text, AI replies and keys are never logged.
 */
#include "gemini_live.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app_config.h"
#include "audio_core.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_transport_ssl.h"
#include "esp_transport_ws.h"
#include "esp_websocket_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gemini_base64.h"
#include "gemini_live_proto.h"
#include "gemini_schema.h"
#include "hangup_phrase.h"
#include "lwip/sockets.h"
#include "net.h"
#include "saver_resample.h"
#include "saver_voice.h"
#include "secret_store.h"
#include "wake.h"

static const char *TAG = "GLIVE";

#define GEMINI_LIVE_URI \
    "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
#define GEMINI_LIVE_PATH "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

#define MESSAGE_MAX          (128 * 1024)   /* same headroom as live_voice.c (audio and tool chunks arrive in one envelope) */
#define INPUT_QUEUE_FRAMES   64
#define INPUT_FRAME_SAMPLES  512
#define INPUT_BATCH_SAMPLES  1024            /* 64ms @16kHz, same size as the LIVE upload batch */
#define OUTBOUND_QUEUE       6
#define STARTUP_TIMEOUT_MS   20000
#define CONNECT_TIMEOUT_MS   20000
#define WIFI_WAIT_MS         15000
#define CLOCK_WAIT_MS        20000
#define CANCELLED_ID_MAX     8
#define CANCELLED_ID_LEN     40
/* Same as live_voice.c: the stack of the internal task esp_websocket_client creates (internal RAM). Only one
 * WebSocket is open at a time (openai.live and gemini.live never run together, guaranteed by s_busy), so the same reserved
 * spot (voice_shared_reserve_release/take, owned by live_voice.c) is shared as is */
#define WS_TASK_STACK        12288

typedef struct {
    size_t  bytes;
    int16_t samples[INPUT_FRAME_SAMPLES];
} input_frame_t;

static QueueHandle_t     s_inputs;          /* mic → upload */
static QueueHandle_t     s_responses;       /* WebSocket receive → parsing task (char*) */
static QueueHandle_t     s_outbound;        /* parsing task (tool responses) → session task (char*, complete JSON) */
static SemaphoreHandle_t s_responses_idle;
static SemaphoreHandle_t s_pending_lock;
static char             *s_pending_text;     /* text queued by gemini_live_text() (PSRAM, consumed by the session) */

static atomic_bool s_ws_connected, s_failed, s_session_active;
static char       *s_message;
static size_t      s_message_used;
static int         s_message_opcode;

/* All fixed buffers live in PSRAM (2026-10-07, real board: with them in internal RAM, headroom after boot fell from 15KB → 9.9KB
 * and Telegram TLS failed with "esp-aes: Failed to allocate memory"). Allocated in gemini_live_init */
static char (*s_cancelled_ids)[CANCELLED_ID_LEN];
static int16_t *s_batch;            /* INPUT_BATCH_SAMPLES */
#define KEY_BUF_LEN     513
#define HEADERS_BUF_LEN 560
static char *s_key, *s_headers;
static int   s_cancelled_next;
static saver_resample_t s_resampler;
static hangup_phrase_t  s_hangup;
static atomic_uint s_tools_total;    /* tool runs over the whole session (for the end log) */

typedef enum { ACT_START, ACT_AUDIO, ACT_IN_TEXT, ACT_OUT_TEXT, ACT_TOOL, ACT_COUNT } activity_t;
static const char *const ACT_NAMES[ACT_COUNT] = {"start", "speaker audio", "heard speech", "assistant text",
                                                 "tool call"};
static atomic_uint s_activity_ms;
static atomic_int  s_last_act;
static atomic_uint s_act_count[ACT_COUNT];

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void touch_activity(activity_t why)
{
    atomic_store(&s_activity_ms, now_ms());
    atomic_store(&s_last_act, why);
    atomic_fetch_add(&s_act_count[why], 1);
}

/* Logs fixed phrases only (same as fail() in live_voice.c) */
static void fail(const char *text, app_error_t code)
{
    bool expected = false;
    if (atomic_compare_exchange_strong(&s_failed, &expected, true)) {
        voice_shared_set_status(text);
        ESP_LOGW(TAG, "%s (internal free %u)", text,
                 (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
    }
    live_voice_stop();
}

static bool is_cancelled(const char *id)
{
    for (int i = 0; i < CANCELLED_ID_MAX; i++) {
        if (s_cancelled_ids[i][0] && !strcmp(s_cancelled_ids[i], id)) {
            return true;
        }
    }
    return false;
}

static void remember_cancelled(const char *id)
{
    snprintf(s_cancelled_ids[s_cancelled_next], CANCELLED_ID_LEN, "%s", id);
    s_cancelled_next = (s_cancelled_next + 1) % CANCELLED_ID_MAX;
}

/* ── Response parsing ────────────────────────────────────────────── */

/* Decode modelTurn's inlineData (24kHz PCM, base64), convert it to 16kHz, and put it in the playback queue */
static void handle_audio_inline(const char *b64, size_t b64_len)
{
    uint8_t *pcm = heap_caps_malloc(b64_len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);   /* decoded size <= length */
    size_t pcm_len = pcm ? gemini_base64_decode(b64, b64_len, pcm, b64_len) : SIZE_MAX;
    if (!pcm || pcm_len == SIZE_MAX || (pcm_len % 2)) {
        fail("Invalid voice audio", APP_ERR_VOICE_INTERNAL);
        free(pcm);
        return;
    }
    const int16_t *pcm24 = (const int16_t *)pcm;
    size_t samples24 = pcm_len / 2;
    /* Silent chunks don't count as activity (the server may keep sending silence after speech ends. Chapter 16, Bug 2; Chapter 18, Section 18.3) */
    for (size_t i = 0; i < samples24; i++) {
        if (pcm24[i] > 200 || pcm24[i] < -200) {
            touch_activity(ACT_AUDIO);
            break;
        }
    }
    for (size_t i = 0; i < samples24 && !voice_shared_stopping(); i += 1024) {
        size_t n = samples24 - i < 1024 ? samples24 - i : 1024;
        int16_t pcm16[700];
        size_t out_n = saver_resample_24to16(&s_resampler, pcm24 + i, n, pcm16, sizeof(pcm16) / sizeof(pcm16[0]));
        if (out_n && !audio_core_voice_enqueue(pcm16, out_n)) {
            fail("Speaker backlog", APP_ERR_VOICE_INTERNAL);
            break;
        }
    }
    free(pcm);
}

/* Runs toolCall.functionCalls[] in order (assistant_execute, tool_guard unchanged) and returns them all at once.
 * The model waits for the response (synchronous call), and while this function runs the session loop's mic upload is not blocked
 * (this function runs only in the response-parsing task, a different task from the session task) */
static void handle_tool_calls(const cJSON *calls)
{
    touch_activity(ACT_TOOL);
    const live_voice_handlers_t *h = voice_shared_handlers();
    cJSON *responses = cJSON_CreateArray();
    int n = 0, ignored = 0;
    const cJSON *call;
    cJSON_ArrayForEach(call, calls) {
        const cJSON *id = cJSON_GetObjectItemCaseSensitive(call, "id");
        const cJSON *name = cJSON_GetObjectItemCaseSensitive(call, "name");
        const cJSON *args = cJSON_GetObjectItemCaseSensitive(call, "args");
        if (!cJSON_IsString(id) || !cJSON_IsString(name)) {
            continue;
        }
        if (is_cancelled(id->valuestring)) {
            ignored++;
            continue;      /* request 4: ignore results for cancelled ids (see the limitation in the header comment) */
        }
        char *args_text = args ? cJSON_PrintUnformatted(args) : NULL;
        cJSON *result = h && h->execute_tool ? h->execute_tool(name->valuestring, args_text ? args_text : "{}") : NULL;
        free(args_text);
        atomic_fetch_add(&s_tools_total, 1);
        cJSON *item = cJSON_CreateObject();
        cJSON_AddStringToObject(item, "id", id->valuestring);
        cJSON_AddStringToObject(item, "name", name->valuestring);
        cJSON_AddItemToObject(item, "response", result ? result : cJSON_Parse("{\"ok\":false}"));
        cJSON_AddItemToArray(responses, item);
        n++;
    }
    if (ignored) {
        ESP_LOGI(TAG, "tool call ignored (cancelled): %d", ignored);
    }
    if (!n) {
        cJSON_Delete(responses);
        return;
    }
    char *text = gemini_live_build_tool_response(responses);     /* takes ownership of responses */
    if (!text || xQueueSend(s_outbound, &text, pdMS_TO_TICKS(250)) != pdTRUE) {
        free(text);
        if (!voice_shared_stopping()) {
            fail("Device tool response failed", APP_ERR_VOICE_DROPPED);
        }
    }
}

static void parse_message(const char *text)
{
    cJSON *root = cJSON_Parse(text);
    if (!root) {
        fail("Invalid voice response", APP_ERR_VOICE_INTERNAL);
        return;
    }
    if (gemini_live_is_setup_complete(root)) {
        hangup_phrase_reset(&s_hangup);
        touch_activity(ACT_START);
        voice_shared_set_ready(true);
        voice_shared_set_status("Listening");
        voice_shared_set_state(VOICE_LIVE);
        audio_core_tone();
        ESP_LOGI(TAG, "setup complete");
        goto done;
    }
    if (gemini_live_is_goaway(root)) {
        ESP_LOGI(TAG, "server goAway (closing soon)");
        voice_shared_set_status("Gemini server closing soon");
        live_voice_stop();
        goto done;
    }
    {
        const cJSON *content = gemini_live_server_content(root);
        if (content && !voice_shared_stopping()) {
            bool interrupted = gemini_live_is_interrupted(content);
            if (interrupted) {
                audio_core_voice_clear();      /* server VAD barge-in (request 3): clear only the audio that was playing */
            }
            const live_voice_handlers_t *h = voice_shared_handlers();
            const char *in_text = gemini_live_transcript_text(content, true);
            if (in_text) {
                touch_activity(ACT_IN_TEXT);
                if (h && h->on_transcript) {
                    h->on_transcript(true, in_text);
                }
                if (live_voice_ready()) {
                    hangup_phrase_feed(&s_hangup, in_text, now_ms());
                    if (h && h->on_user_input) {
                        h->on_user_input();     /* TLG-14: inputAudioTranscription is the "person spoke again" signal */
                    }
                }
            }
            const char *out_text = gemini_live_transcript_text(content, false);
            if (out_text) {
                touch_activity(ACT_OUT_TEXT);
                if (h && h->on_transcript) {
                    h->on_transcript(false, out_text);
                }
            }
            size_t b64_len = 0;
            const char *b64 = gemini_live_find_inline_audio(content, &b64_len);
            if (b64) {
                handle_audio_inline(b64, b64_len);
            }
            if (interrupted || gemini_live_is_turn_complete(content)) {
                saver_resample_reset(&s_resampler);   /* turn boundary: the next audio starts a fresh join */
            }
        }
        const cJSON *calls = gemini_live_tool_calls(root);
        if (calls && !voice_shared_stopping()) {
            handle_tool_calls(calls);
        }
        const cJSON *cancelled = gemini_live_cancelled_ids(root);
        if (cancelled) {
            const cJSON *id;
            cJSON_ArrayForEach(id, cancelled) {
                if (cJSON_IsString(id)) {
                    remember_cancelled(id->valuestring);
                }
            }
        }
    }
done:
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
                xSemaphoreGive(s_responses_idle);    /* session-end barrier */
            }
        }
        if (live_voice_ready() && hangup_phrase_ready(&s_hangup, now_ms())) {
            ESP_LOGI(TAG, "hangup phrase heard");
            voice_shared_set_status("Hangup phrase heard");
            live_voice_stop();
            audio_core_voice_clear();
        }
    }
}

/* ── WebSocket events (same shape as websocket_event() in live_voice.c) ─────────────── */

static void queue_message(void)
{
    s_message[s_message_used] = '\0';
    char *copy = heap_caps_malloc(s_message_used + 1, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!copy) {
        fail("Voice response allocation failed", APP_ERR_VOICE_INTERNAL);
        return;
    }
    memcpy(copy, s_message, s_message_used + 1);
    if (xQueueSend(s_responses, &copy, 0) != pdTRUE && xQueueSend(s_responses, &copy, pdMS_TO_TICKS(250)) != pdTRUE) {
        free(copy);
        if (!voice_shared_stopping()) {
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
        atomic_store(&s_ws_connected, true);
        return;
    }
    if (id == WEBSOCKET_EVENT_ERROR || id == WEBSOCKET_EVENT_DISCONNECTED || id == WEBSOCKET_EVENT_CLOSED) {
        if (!voice_shared_stopping()) {
            if (event->error_handle.error_type == WEBSOCKET_ERROR_TYPE_TCP_TRANSPORT) {
                ESP_LOGW(TAG, "transport error: errno %d, tls 0x%x", event->error_handle.esp_transport_sock_errno,
                         event->error_handle.esp_tls_stack_err);
            }
            fail(event->error_handle.error_type == WEBSOCKET_ERROR_TYPE_PONG_TIMEOUT ? "Voice heartbeat timed out"
                                                                                     : "Voice connection ended",
                 APP_ERR_VOICE_DROPPED);
        }
        atomic_store(&s_ws_connected, false);
        return;
    }
    /* When the server closes the connection, log the close code and reason (to find causes like a rejected setup. The reason is the server's error text, not conversation content) */
    if (id == WEBSOCKET_EVENT_DATA && event->op_code == 8) {
        int code = event->data_len >= 2 ? (((uint8_t)event->data_ptr[0]) << 8) | (uint8_t)event->data_ptr[1] : 0;
        int reason_len = event->data_len > 2 ? event->data_len - 2 : 0;
        ESP_LOGW(TAG, "server closed: code %d, reason: %.*s", code, reason_len > 160 ? 160 : reason_len,
                 reason_len ? event->data_ptr + 2 : "");
        return;
    }
    /*
     * Gemini Live sends JSON messages as binary (op 2) frames. Accepting only text (op 1) threw away setupComplete and
     * ended in "Voice startup timed out" (2026-10-07, real board). Accept both text and binary as JSON. op 0 is a continuation fragment
     */
    if (id != WEBSOCKET_EVENT_DATA || (event->op_code != 1 && event->op_code != 2 && event->op_code != 0)) {
        return;
    }
    if (event->payload_offset == 0 && (event->op_code == 1 || event->op_code == 2)) {
        s_message_used = 0;
        s_message_opcode = event->op_code;
    }
    if ((s_message_opcode != 1 && s_message_opcode != 2) || event->data_len < 0 ||
        s_message_used + event->data_len >= MESSAGE_MAX) {
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

/* ── Mic feed (same as live_voice_feed() in live_voice.c: never blocks; when backed up, drops the oldest audio) ── */

static void gemini_live_feed(const int16_t *samples, size_t count)
{
    if (!live_voice_ready() || voice_shared_stopping()) {
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

/* Batch up to INPUT_BATCH_SAMPLES (64ms) into one realtimeInput.audio */
static bool upload_audio(esp_websocket_client_handle_t client, input_frame_t *frame)
{
    int16_t *batch = s_batch;
    size_t samples = frame->bytes / sizeof(int16_t);
    memcpy(batch, frame->samples, frame->bytes);
    while (samples < INPUT_BATCH_SAMPLES && !voice_shared_stopping()) {
        if (xQueuePeek(s_inputs, frame, pdMS_TO_TICKS(20)) != pdTRUE ||
            frame->bytes / sizeof(int16_t) > INPUT_BATCH_SAMPLES - samples ||
            xQueueReceive(s_inputs, frame, 0) != pdTRUE) {
            break;
        }
        memcpy(batch + samples, frame->samples, frame->bytes);
        samples += frame->bytes / sizeof(int16_t);
    }
    char *text = gemini_live_build_audio_chunk(batch, samples);
    if (!text) {
        return false;
    }
    size_t n = strlen(text);
    bool ok = esp_websocket_client_send_text(client, text, n, pdMS_TO_TICKS(1000)) == (int)n;
    free(text);
    return ok;
}

/* ── Session ─────────────────────────────────────────────────── */

static bool wait_flag(atomic_bool *flag, uint32_t timeout_ms)
{
    for (uint32_t waited = 0; waited < timeout_ms && !atomic_load(flag) && !voice_shared_stopping(); waited += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    return atomic_load(flag);
}

static void reset_session_state(void)
{
    atomic_store(&s_ws_connected, false);
    atomic_store(&s_failed, false);
    atomic_store(&s_tools_total, 0);
    xQueueReset(s_inputs);
    audio_core_voice_clear();
    s_message_used = 0;
    s_message_opcode = 0;
    memset(s_cancelled_ids, 0, sizeof(s_cancelled_ids));
    s_cancelled_next = 0;
    saver_resample_reset(&s_resampler);
    hangup_phrase_reset(&s_hangup);
    for (int i = 0; i < ACT_COUNT; i++) {
        atomic_store(&s_act_count[i], 0);
    }
    xSemaphoreTake(s_pending_lock, portMAX_DELAY);
    free(s_pending_text);
    s_pending_text = NULL;
    xSemaphoreGive(s_pending_lock);
}

static void run_session(void)
{
    const live_voice_handlers_t *h = voice_shared_handlers();
    esp_websocket_client_handle_t client = NULL;
    esp_transport_handle_t tls = NULL, ws = NULL;
    const char *limit_reason = NULL;
    char *instructions = NULL, *setup_text = NULL;
    cJSON *gemini_tools = NULL;
    char *key = s_key, *headers = s_headers;

    reset_session_state();
    voice_shared_set_status("Connecting Wi-Fi");
    if (h->on_session_start) {
        h->on_session_start();
    }

    if (!wake_pause()) {
        fail("Wake detector did not release memory", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    net_set_power_save(false);

    if (!net_wait_connected(WIFI_WAIT_MS)) {
        fail("Wi-Fi unavailable", APP_ERR_WIFI);
        goto cleanup;
    }
    voice_shared_set_status("Checking clock");
    for (uint32_t w = 0; w < CLOCK_WAIT_MS && !net_time_valid() && !voice_shared_stopping(); w += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!net_time_valid()) {
        fail("Clock sync failed", APP_ERR_CLOCK);
        goto cleanup;
    }
    if (voice_shared_stopping()) {
        goto cleanup;
    }

    size_t key_len = KEY_BUF_LEN - 1;
    if (secret_get(SECRET_GEMINI_KEY, key, &key_len) != ESP_OK || key_len == 0) {
        fail("Gemini API key not set", APP_ERR_NO_API_KEY);
        goto cleanup;
    }
    key[key_len] = '\0';
    snprintf(headers, HEADERS_BUF_LEN, "x-goog-api-key: %s\r\n", key);
    memset(key, 0, KEY_BUF_LEN);

    {
        char voice[32] = "";
        bool search = false;
        instructions = h->build_gemini_live_instructions
                           ? h->build_gemini_live_instructions(voice, sizeof(voice), &search)
                           : NULL;
        if (!instructions) {
            instructions = strdup("Answer briefly and naturally for speech.");
        }
        cJSON *tools = h->build_saver_tools ? h->build_saver_tools() : NULL;
        gemini_tools = gemini_schema_convert_tools(tools);   /* the same tool list in Gemini shape (request 4) */
        cJSON_Delete(tools);
        setup_text = gemini_live_build_setup(APP_GEMINI_LIVE_MODEL_DEFAULT, gemini_tts_voice(voice), instructions,
                                             gemini_tools, search);
    }
    if (!setup_text) {
        fail("Session startup failed", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }

    tls = esp_transport_ssl_init();
    if (tls) {
        esp_transport_ssl_crt_bundle_attach(tls, esp_crt_bundle_attach);
        ws = esp_transport_ws_init(tls);
    }
    if (!ws) {
        fail("Could not allocate voice transport", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    const esp_transport_ws_config_t ws_cfg = {
        .ws_path = GEMINI_LIVE_PATH,
        .headers = headers,
        .propagate_control_frames = true,
    };
    if (esp_transport_ws_set_config(ws, &ws_cfg) != ESP_OK) {
        fail("Could not configure voice transport", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    const esp_websocket_client_config_t cfg = {
        .uri = GEMINI_LIVE_URI,
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
    voice_shared_set_status("Connecting to Gemini");
    voice_shared_reserve_release();    /* let the WebSocket task stack use the reserved internal RAM spot */
    if (esp_websocket_client_start(client) != ESP_OK || !wait_flag(&s_ws_connected, CONNECT_TIMEOUT_MS)) {
        fail("Gemini connection failed", APP_ERR_VOICE_CONNECT);
        goto cleanup;
    }
    if (esp_websocket_client_send_text(client, setup_text, strlen(setup_text), pdMS_TO_TICKS(2000)) !=
        (int)strlen(setup_text)) {
        fail("Session startup failed", APP_ERR_VOICE_INTERNAL);
        goto cleanup;
    }
    free(setup_text);
    setup_text = NULL;

    uint32_t began = now_ms();
    uint32_t max_ms, idle_ms;
    voice_shared_take_next_limits(&max_ms, &idle_ms);
    max_ms = max_ms ? max_ms : APP_VOICE_MAX_SESSION_MS;
    idle_ms = idle_ms ? idle_ms : APP_VOICE_IDLE_TIMEOUT_MS;
    ESP_LOGI(TAG, "limits: idle %u s, max %u s", (unsigned)(idle_ms / 1000), (unsigned)(max_ms / 1000));
    uint32_t act_log_ms = began;

    while (!voice_shared_stopping()) {
        if (h->on_tick) {
            h->on_tick();
        }
        uint32_t now = now_ms();
        if (!live_voice_ready() && now - began > STARTUP_TIMEOUT_MS) {
            fail("Voice startup timed out", APP_ERR_VOICE_CONNECT);
            break;
        }
        /* Idle time: count as activity only while audible assistant audio is going out (same as LIVE. Chapter 16, Bug 2) */
        if (live_voice_ready() && audio_core_voice_playing()) {
            touch_activity(ACT_AUDIO);
        }
        if (live_voice_ready() && now - act_log_ms >= 10000) {
            act_log_ms = now;
            int32_t quiet = (int32_t)(now - atomic_load(&s_activity_ms));
            ESP_LOGI(TAG, "idle %d/%u s, last: %s | 10 s: heard %u, assistant text %u, audio %u, tool %u",
                     (int)(quiet > 0 ? quiet / 1000 : 0), (unsigned)(idle_ms / 1000), ACT_NAMES[atomic_load(&s_last_act)],
                     atomic_exchange(&s_act_count[ACT_IN_TEXT], 0), atomic_exchange(&s_act_count[ACT_OUT_TEXT], 0),
                     atomic_exchange(&s_act_count[ACT_AUDIO], 0), atomic_exchange(&s_act_count[ACT_TOOL], 0));
        }
        if (now - began > max_ms) {
            limit_reason = "Conversation limit reached";
        } else if (live_voice_ready() && (int32_t)(now - atomic_load(&s_activity_ms)) > (int32_t)idle_ms) {
            limit_reason = "Idle timeout";
        }
        if (limit_reason) {
            ESP_LOGI(TAG, "%s", limit_reason);
            voice_shared_set_status(limit_reason);
            live_voice_stop();
            break;
        }

        /* Text the device sends (reminders, auto-read, mic calibration guidance; request 5): as clientContent */
        xSemaphoreTake(s_pending_lock, portMAX_DELAY);
        char *pending = s_pending_text;
        s_pending_text = NULL;
        xSemaphoreGive(s_pending_lock);
        if (pending) {
            char *msg = gemini_live_build_client_text(pending);
            free(pending);
            if (msg) {
                size_t n = strlen(msg);
                if (esp_websocket_client_send_text(client, msg, n, pdMS_TO_TICKS(1000)) != (int)n &&
                    !voice_shared_stopping()) {
                    fail("Device message failed", APP_ERR_VOICE_DROPPED);
                }
                free(msg);
            }
        }

        /* Tool responses (queued by the response-parsing task) */
        char *out = NULL;
        if (xQueueReceive(s_outbound, &out, 0) == pdTRUE) {
            size_t n = strlen(out);
            if (esp_websocket_client_send_text(client, out, n, pdMS_TO_TICKS(1000)) != (int)n &&
                !voice_shared_stopping()) {
                fail("Device tool response failed", APP_ERR_VOICE_DROPPED);
            }
            free(out);
        }

        input_frame_t frame;
        if (xQueueReceive(s_inputs, &frame, pdMS_TO_TICKS(20)) == pdTRUE && live_voice_ready()) {
            if (!upload_audio(client, &frame) && !voice_shared_stopping()) {
                fail("Audio upload interrupted", APP_ERR_VOICE_DROPPED);
            }
        }
    }

cleanup:
    if (h->on_session_end) {
        h->on_session_end();
    }
    free(instructions);
    free(setup_text);
    cJSON_Delete(gemini_tools);
    voice_shared_set_ready(false);
    audio_core_voice_clear();
    if (client) {
        esp_websocket_client_stop(client);
        esp_websocket_client_destroy(client);
    }
    if (ws) {
        esp_transport_destroy(ws);
    }
    if (tls) {
        esp_transport_destroy(tls);
    }
    /* Wait until the parsing task has handled the remaining messages, then allow the next session (same as live_voice.c) */
    char *barrier = NULL;
    xQueueSend(s_responses, &barrier, portMAX_DELAY);
    xSemaphoreTake(s_responses_idle, portMAX_DELAY);
    char *stale = NULL;
    while (xQueueReceive(s_outbound, &stale, 0) == pdTRUE) {
        free(stale);
    }
    bool failed = atomic_load(&s_failed);
    unsigned tools_total = atomic_load(&s_tools_total);
    reset_session_state();
    memset(headers, 0, HEADERS_BUF_LEN);
    if (!failed && !limit_reason) {
        voice_shared_set_status("Ready");
    }
    ESP_LOGI(TAG, "session ended: %s (tools %u)", limit_reason ? limit_reason : (failed ? "error" : "stopped"),
             tools_total);
    net_set_power_save(true);
    voice_shared_reserve_take();    /* reserve the spot before reloading the wake-word model */
    wake_resume();
    voice_shared_end(true);
}

void gemini_live_task_entry(void *arg)
{
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        atomic_store(&s_session_active, true);
        run_session();
        atomic_store(&s_session_active, false);
    }
}

bool gemini_live_active(void)
{
    return atomic_load(&s_session_active);
}

esp_err_t gemini_live_text(const char *text)
{
    if (!atomic_load(&s_session_active) || !text || !text[0] || strlen(text) > 600) {
        return ESP_ERR_INVALID_STATE;
    }
    char *copy = strdup(text);
    if (!copy) {
        return ESP_ERR_NO_MEM;
    }
    xSemaphoreTake(s_pending_lock, portMAX_DELAY);
    free(s_pending_text);
    s_pending_text = copy;
    xSemaphoreGive(s_pending_lock);
    const live_voice_handlers_t *h = voice_shared_handlers();
    if (h && h->on_user_input) {
        h->on_user_input();     /* a request sent as text is user input too (same as live_voice_text()) */
    }
    return ESP_OK;
}

esp_err_t gemini_live_init(void)
{
    static StaticQueue_t input_ctrl;
    uint8_t *input_storage = heap_caps_malloc(INPUT_QUEUE_FRAMES * sizeof(input_frame_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_message = heap_caps_malloc(MESSAGE_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_cancelled_ids = heap_caps_calloc(CANCELLED_ID_MAX, CANCELLED_ID_LEN, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_batch = heap_caps_malloc(INPUT_BATCH_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_key = heap_caps_calloc(1, KEY_BUF_LEN, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_headers = heap_caps_calloc(1, HEADERS_BUF_LEN, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!input_storage || !s_message || !s_cancelled_ids || !s_batch || !s_key || !s_headers) {
        return ESP_ERR_NO_MEM;
    }
    s_inputs = xQueueCreateStatic(INPUT_QUEUE_FRAMES, sizeof(input_frame_t), input_storage, &input_ctrl);
    s_responses = xQueueCreateWithCaps(16, sizeof(char *), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_outbound = xQueueCreateWithCaps(OUTBOUND_QUEUE, sizeof(char *), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_responses_idle = xSemaphoreCreateBinary();
    s_pending_lock = xSemaphoreCreateMutex();
    if (!s_inputs || !s_responses || !s_outbound || !s_responses_idle || !s_pending_lock) {
        return ESP_ERR_NO_MEM;
    }
    ESP_ERROR_CHECK(audio_core_add_mic_sink(gemini_live_feed));
    /* Response parsing, playback-queue enqueue, tool execution → stack in PSRAM (XIP from PSRAM, so tool flash writes work too; same as tool_worker).
     * Tools (radio search HTTPS etc.) run directly in this task, so 12KB like tool_worker (8KB could overflow) */
    if (xTaskCreatePinnedToCoreWithCaps(response_task, "gemini_rx", 12288, NULL, 5, NULL, 0,
                                        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}
