/**
 * @file saver_voice.c
 * @brief Saver mode (OpenAI) voice engine: listen (VAD) -> transcription -> text model (tools) -> speech synthesis (docs/design-voice-saver-mode.md 11.6)
 *
 * Runs the whole conversation loop in its own task, which live_voice.c wakes after choosing the engine (one session = one
 * call). Busy, state, ready, and idle/max time use the values live_voice.c holds, only through the small pass-through
 * functions in saver_voice.h (voice_shared_*). The Live (gpt-live-1) path is not touched at all.
 *
 * Logs record only per-step times and counts. Transcribed text, AI replies, and Telegram content are never logged.
 */
#include "saver_voice.h"

#include <stdatomic.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include "app_config.h"
#include "audio_core.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_vad.h"
#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gemini_base64.h"
#include "gemini_live_proto.h"
#include "gemini_schema.h"
#include "hangup_phrase.h"
#include "net.h"
#include "saver_endpoint.h"
#include "saver_resample.h"
#include "saver_text.h"
#include "secret_store.h"
#include "settings.h"
#include "wake.h"

static const char *TAG = "SAVER";

/* ── Constants ─────────────────────────────────────────────────── */

#define SAVER_VAD_FRAME_MS      20
#define SAVER_VAD_FRAME_SAMPLES (AUDIO_SAMPLE_RATE * SAVER_VAD_FRAME_MS / 1000)   /* 320 @16kHz */
/*
 * 2026-10-04 on real hardware: speech was not recognized at all. After echo cancellation the audio was quiet (peak 600-1,400) and VAD mode 3 (strictest)
 * treated speech as silence. Like the wake word, boost 4x (+12dB) for VAD and transcription, lower the mode,
 * and treat loud enough sound as speech even when VAD misses it (loudness rule).
 */
#define SAVER_INPUT_GAIN        4
#define SAVER_VAD_MODE          VAD_MODE_1
#define SAVER_SPEECH_RMS        700       /* RMS after boost. Above this is speech */
#define SAVER_START_FRAMES      3         /* speech starts only after 3 loud chunks (60ms) in a row (ignores door sounds etc.) */
/*
 * 2026-10-04 on real hardware, second round: WebRTC VAD called exactly half the chunks "speech" even in silence
 * ("listen 5 s: frames 250, vad speech 125, loud 0, peak 120"). So end of speech (0.7 s of silence) never came
 * and it never moved on to transcription. Endpointing uses loudness (RMS) only; VAD values go to the diagnostic log only.
 */
#define SAVER_PREROLL_MS        300
#define SAVER_PREROLL_SAMPLES   (AUDIO_SAMPLE_RATE * SAVER_PREROLL_MS / 1000)     /* 4800 */
#define SAVER_PCM_MAX_SAMPLES   (31 * AUDIO_SAMPLE_RATE)   /* 31 s > 30 s max utterance + margin */
#define SAVER_PCM_MAX_BYTES     (SAVER_PCM_MAX_SAMPLES * sizeof(int16_t))

#define SAVER_STT_URL   "https://api.openai.com/v1/audio/transcriptions"
#define SAVER_LLM_URL   "https://api.openai.com/v1/responses"
#define SAVER_TTS_URL   "https://api.openai.com/v1/audio/speech"
#define SAVER_STT_MODEL "gpt-transcribe"
#define SAVER_TTS_MODEL "gpt-4o-mini-tts"

#define STT_BOUNDARY "----aispkSaverBoundary7f3a"
#define STT_PREAMBLE \
    "--" STT_BOUNDARY "\r\n" \
    "Content-Disposition: form-data; name=\"model\"\r\n\r\n" SAVER_STT_MODEL "\r\n" \
    "--" STT_BOUNDARY "\r\n" \
    "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n" \
    "Content-Type: audio/wav\r\n\r\n"
#define STT_TAIL "\r\n--" STT_BOUNDARY "--\r\n"
#define STT_PREAMBLE_LEN (sizeof(STT_PREAMBLE) - 1)
#define STT_TAIL_LEN     (sizeof(STT_TAIL) - 1)
#define WAV_HEADER_LEN   44

#define STT_RESPONSE_CAP  4096
/* The response echoes back the instructions and tool list we sent (15-20KB), plus sources for a web search.
 * At 16KB the overflow was dropped, parsing failed, and the reply was empty (2026-10-04 on real hardware: "tts 0.0 s"). PSRAM, so be generous */
#define LLM_RESPONSE_CAP  (256 * 1024)
#define TOOL_MAX_ROUNDS   4
#define HISTORY_MAX_TURNS 20
#define TURN_TEXT_MAX     700
#define WIFI_WAIT_MS      15000
#define CLOCK_WAIT_MS     20000
#define CONSECUTIVE_FAIL_MAX 3

/*
 * Gemini Saver mode (docs/design-voice-saver-mode.md stage 2). Understanding + reply happen in one call (Section 2.5), so there is no
 * separate transcription step. Instead the audio goes straight into generateContent, and the model must call
 * report_transcript first (toolConfig mode ANY), so we get the transcript too (needed for hang-up phrases, TLG-14, noise filter; Section 11.6).
 * Structured output (responseSchema) can't be combined with function calling (checked at ai.google.dev, 2026-10), hence this approach.
 */
#define GEMINI_URL_FMT          "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
#define GEMINI_RESPONSE_CAP     (256 * 1024)   /* understanding + tool response: same reason as LLM_RESPONSE_CAP (Section 15.5) */
#define GEMINI_TTS_RESPONSE_CAP (512 * 1024)   /* larger because of base64 audio (request 10) */
#define GEMINI_MAX_AUDIO_SAMPLES (15 * AUDIO_SAMPLE_RATE)  /* uploading a full 30 s utterance as base64 costs PSRAM and time
    (about 1.3MB) -> cut to 15 s (request 1 note). Normal utterances are much shorter, so this rarely applies */
#define GEMINI_TRANSCRIBE_TIMEOUT_MS 25000  /* includes the audio upload, so longer than other calls */
#define GEMINI_TOOL_TIMEOUT_MS  20000
#define GEMINI_TTS_TIMEOUT_MS   25000

/* ── Recording buffer (PSRAM, with room for the multipart head and tail reserved up front: POSTed as is, without a single copy) ── */

static uint8_t *s_rec_buf;      /* STT_PREAMBLE + WAV_HEADER + PCM (max) + STT_TAIL */
static size_t   s_rec_capacity;
static int16_t *s_preroll;      /* small ring buffer, always the latest 0.3 s */
static size_t   s_preroll_write;
static bool     s_preroll_full;

/* ── Shared session state (mic task <-> saver task) ───────────── */

static vad_handle_t     s_vad;
static saver_endpoint_t s_endpoint;
static int16_t          s_carry[SAVER_VAD_FRAME_SAMPLES];
static size_t           s_carry_used;
static _Atomic size_t   s_rec_len_samples;     /* length the mic task is recording */
static atomic_bool      s_listening;           /* the mic sink records only when true (11.5: no input while speaking) */
static QueueHandle_t    s_utterances;          /* depth 1: saver_utterance_t, xQueueOverwrite */
static atomic_bool      s_barge;               /* Key2: stop current playback */
static atomic_bool      s_session_active;      /* session in progress (listening/thinking/speaking combined) */

static SemaphoreHandle_t s_pending_lock;
static char             *s_pending_text;       /* reminder sentence put in by saver_voice_text() (PSRAM, consumed by the session) */

typedef struct {
    saver_endpoint_result_t reason;
    size_t                  sample_count;
} saver_utterance_t;

typedef struct {
    bool is_user;
    char text[TURN_TEXT_MAX];
} saver_turn_t;

static saver_turn_t *s_history;     /* PSRAM, ring of HISTORY_MAX_TURNS */
static int           s_history_count, s_history_next;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

/* ── Mic sink: VAD -> endpointing -> recording buffer/pre-roll ──────────── */

static int16_t *pcm_region(void)
{
    return (int16_t *)(s_rec_buf + STT_PREAMBLE_LEN + WAV_HEADER_LEN);
}

static void preroll_push(const int16_t *samples, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        s_preroll[s_preroll_write] = samples[i];
        s_preroll_write = (s_preroll_write + 1) % SAVER_PREROLL_SAMPLES;
        if (s_preroll_write == 0) {
            s_preroll_full = true;
        }
    }
}

/* Copy the whole pre-roll, in time order, to the front of the recording buffer (the moment speech starts) */
static size_t preroll_commit(int16_t *dst)
{
    size_t count = s_preroll_full ? SAVER_PREROLL_SAMPLES : s_preroll_write;
    size_t start = s_preroll_full ? s_preroll_write : 0;
    for (size_t i = 0; i < count; i++) {
        dst[i] = s_preroll[(start + i) % SAVER_PREROLL_SAMPLES];
    }
    return count;
}

static void append_pcm(const int16_t *samples, size_t n)
{
    size_t len = atomic_load(&s_rec_len_samples);
    size_t room = SAVER_PCM_MAX_SAMPLES > len ? SAVER_PCM_MAX_SAMPLES - len : 0;
    if (n > room) {
        n = room;
    }
    if (n) {
        memcpy(pcm_region() + len, samples, n * sizeof(int16_t));
        atomic_store(&s_rec_len_samples, len + n);
    }
}

/* Diagnostics: loudness and speech-detection counts every 5 s while listening (no content) */
static volatile unsigned s_diag_frames, s_diag_vad, s_diag_loud;
static unsigned s_loud_run;
static volatile int s_diag_peak;

/* Called from the mic task. Never blocks (processing one VAD frame is light) */
static void saver_voice_feed(const int16_t *samples, size_t count)
{
    if (!atomic_load(&s_listening)) {
        return;
    }
    while (count) {
        size_t need = SAVER_VAD_FRAME_SAMPLES - s_carry_used;
        size_t take = count < need ? count : need;
        memcpy(s_carry + s_carry_used, samples, take * sizeof(int16_t));
        s_carry_used += take;
        samples += take;
        count -= take;
        if (s_carry_used < SAVER_VAD_FRAME_SAMPLES) {
            break;
        }
        s_carry_used = 0;
        /* Boost 4x (clip on overflow) + measure loudness */
        int peak = 0;
        uint64_t sq = 0;
        for (int i = 0; i < SAVER_VAD_FRAME_SAMPLES; i++) {
            int v32 = s_carry[i] * SAVER_INPUT_GAIN;
            v32 = v32 > 32767 ? 32767 : (v32 < -32768 ? -32768 : v32);
            s_carry[i] = (int16_t)v32;
            int a = v32 < 0 ? -v32 : v32;
            peak = a > peak ? a : peak;
            sq += (uint64_t)((int64_t)v32 * v32);
        }
        int rms = (int)sqrtf((float)(sq / SAVER_VAD_FRAME_SAMPLES));
        preroll_push(s_carry, SAVER_VAD_FRAME_SAMPLES);
        vad_state_t v = s_vad ? vad_process(s_vad, s_carry, AUDIO_SAMPLE_RATE, SAVER_VAD_FRAME_MS) : VAD_SILENCE;
        bool loud = rms > SAVER_SPEECH_RMS;
        s_loud_run = loud ? s_loud_run + 1 : 0;
        /* Before speech starts, 3 loud chunks in a row are needed; after it starts, one loud chunk counts as speech */
        bool speech = s_endpoint.in_speech ? loud : s_loud_run >= SAVER_START_FRAMES;
        s_diag_frames++;
        s_diag_vad += v == VAD_SPEECH;
        s_diag_loud += rms > SAVER_SPEECH_RMS;
        s_diag_peak = peak > s_diag_peak ? peak : s_diag_peak;
        bool started = false;
        uint32_t t = now_ms();
        saver_endpoint_result_t r = saver_endpoint_feed(&s_endpoint, speech, t, &started);
        if (started) {
            atomic_store(&s_rec_len_samples, 0);
            size_t pre = preroll_commit(pcm_region());
            atomic_store(&s_rec_len_samples, pre);
        } else if (s_endpoint.in_speech) {
            append_pcm(s_carry, SAVER_VAD_FRAME_SAMPLES);
        }
        if (r == SAVER_EP_END_SILENCE || r == SAVER_EP_END_MAXLEN) {
            atomic_store(&s_listening, false);
            saver_utterance_t utt = {.reason = r, .sample_count = atomic_load(&s_rec_len_samples)};
            xQueueOverwrite(s_utterances, &utt);
            saver_endpoint_reset(&s_endpoint);
        }
    }
}

/* ── HTTP common ────────────────────────────────────────────── */

typedef struct {
    char  *buf;
    size_t used, cap;
    bool   truncated;   /* the buffer overflowed and the tail was dropped */
} body_t;

static esp_err_t collect_body(esp_http_client_event_t *evt)
{
    body_t *b = evt->user_data;
    if (evt->event_id == HTTP_EVENT_ON_DATA && b && b->buf) {
        if (b->used + (size_t)evt->data_len < b->cap) {
            memcpy(b->buf + b->used, evt->data, evt->data_len);
            b->used += evt->data_len;
        } else {
            b->truncated = true;
        }
    }
    return ESP_OK;
}

static void set_auth(esp_http_client_handle_t client, const char *key)
{
    char auth[560];
    snprintf(auth, sizeof(auth), "Bearer %s", key);
    esp_http_client_set_header(client, "Authorization", auth);
    memset(auth, 0, sizeof(auth));
}

/* Gemini: a key in the URL (?key=) can end up in access logs and proxies, so send it in a header (request 7) */
static void set_gemini_auth(esp_http_client_handle_t client, const char *key)
{
    esp_http_client_set_header(client, "x-goog-api-key", key);
}

/* Is the current ai_provider setting gemini? Read directly for the same reason as read_voice_choice() in live_voice.c
 * (can't REQUIRE assistant, see the saver_voice.h header). If unreadable, false (OpenAI, safe default) */
static bool provider_is_gemini(void)
{
    size_t len = 4096;
    char *buf = heap_caps_malloc(len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    bool gemini = false;
    if (buf && settings_get_str("assistant", "settings", buf, &len) == ESP_OK) {
        cJSON *s = cJSON_Parse(buf);
        const cJSON *p = cJSON_GetObjectItemCaseSensitive(s, "ai_provider");
        gemini = cJSON_IsString(p) && !strcmp(p->valuestring, "gemini");
        cJSON_Delete(s);
    }
    free(buf);
    return gemini;
}

/* ── Transcription (multipart, POST the pre-laid-out buffer as is) ── */

static void put_le32(uint8_t *p, uint32_t v) { p[0]=v; p[1]=v>>8; p[2]=v>>16; p[3]=v>>24; }
static void put_le16(uint8_t *p, uint16_t v) { p[0]=v; p[1]=v>>8; }

static void build_wav_header(uint8_t *h, uint32_t pcm_bytes)
{
    uint32_t byte_rate = AUDIO_SAMPLE_RATE * 2;
    memcpy(h, "RIFF", 4);
    put_le32(h + 4, 36 + pcm_bytes);
    memcpy(h + 8, "WAVE", 4);
    memcpy(h + 12, "fmt ", 4);
    put_le32(h + 16, 16);
    put_le16(h + 20, 1);
    put_le16(h + 22, 1);
    put_le32(h + 24, AUDIO_SAMPLE_RATE);
    put_le32(h + 28, byte_rate);
    put_le16(h + 32, 2);
    put_le16(h + 34, 16);
    memcpy(h + 36, "data", 4);
    put_le32(h + 40, pcm_bytes);
}

/* On success text_out holds the transcript (NUL-terminated); false on failure. text_out[0]='\0' means an empty result */
static bool stt_transcribe(const char *key, size_t sample_count, char *text_out, size_t text_cap)
{
    text_out[0] = '\0';
    size_t pcm_bytes = sample_count * sizeof(int16_t);
    memcpy(s_rec_buf, STT_PREAMBLE, STT_PREAMBLE_LEN);
    build_wav_header(s_rec_buf + STT_PREAMBLE_LEN, (uint32_t)pcm_bytes);
    memcpy(s_rec_buf + STT_PREAMBLE_LEN + WAV_HEADER_LEN + pcm_bytes, STT_TAIL, STT_TAIL_LEN);
    size_t total = STT_PREAMBLE_LEN + WAV_HEADER_LEN + pcm_bytes + STT_TAIL_LEN;

    char *resp = heap_caps_malloc(STT_RESPONSE_CAP, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!resp) {
        return false;
    }
    body_t body = {.buf = resp, .cap = STT_RESPONSE_CAP};
    char content_type[80];
    snprintf(content_type, sizeof(content_type), "multipart/form-data; boundary=%s", STT_BOUNDARY);
    const esp_http_client_config_t cfg = {
        .url = SAVER_STT_URL,
        .method = HTTP_METHOD_POST,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 15000,
        .event_handler = collect_body,
        .user_data = &body,
        .buffer_size = 2048,
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    bool ok = false;
    if (client) {
        set_auth(client, key);
        esp_http_client_set_header(client, "Content-Type", content_type);
        esp_http_client_set_post_field(client, (const char *)s_rec_buf, (int)total);
        if (esp_http_client_perform(client) == ESP_OK && esp_http_client_get_status_code(client) == 200) {
            ok = true;
        } else {
            ESP_LOGW(TAG, "stt http %d", esp_http_client_get_status_code(client));
        }
        esp_http_client_cleanup(client);
    }
    if (ok && body.used) {
        body.buf[body.used] = '\0';
        cJSON *j = cJSON_Parse(body.buf);
        const cJSON *text = cJSON_GetObjectItemCaseSensitive(j, "text");
        if (cJSON_IsString(text)) {
            snprintf(text_out, text_cap, "%s", text->valuestring);
        } else {
            ok = false;
        }
        cJSON_Delete(j);
    }
    free(resp);
    return ok;
}

/* ── Text model (Responses, tool loop) ───────────────────────── */

static void history_reset(void)
{
    s_history_count = 0;
    s_history_next = 0;
}

static void history_add(bool is_user, const char *text)
{
    if (!s_history) {
        return;
    }
    saver_turn_t *t = &s_history[s_history_next];
    t->is_user = is_user;
    snprintf(t->text, sizeof(t->text), "%s", text);
    s_history_next = (s_history_next + 1) % HISTORY_MAX_TURNS;
    if (s_history_count < HISTORY_MAX_TURNS) {
        s_history_count++;
    }
}

static void history_append_input(cJSON *input)
{
    int start = s_history_count < HISTORY_MAX_TURNS ? 0 : s_history_next;
    for (int i = 0; i < s_history_count; i++) {
        saver_turn_t *t = &s_history[(start + i) % HISTORY_MAX_TURNS];
        cJSON *item = cJSON_CreateObject();
        cJSON_AddStringToObject(item, "role", t->is_user ? "user" : "assistant");
        cJSON *content = cJSON_AddArrayToObject(item, "content");
        cJSON *part = cJSON_CreateObject();
        cJSON_AddStringToObject(part, "type", t->is_user ? "input_text" : "output_text");
        cJSON_AddStringToObject(part, "text", t->text);
        cJSON_AddItemToArray(content, part);
        cJSON_AddItemToArray(input, item);
    }
}

/* Collect function_calls and the final text from the output[] array. Caller does cJSON_Delete on calls */
static cJSON *scan_output(const cJSON *output, char *text_out, size_t text_cap)
{
    cJSON *calls = cJSON_CreateArray();
    size_t used = 0;
    text_out[0] = '\0';
    const cJSON *item;
    cJSON_ArrayForEach(item, output) {
        const cJSON *type = cJSON_GetObjectItemCaseSensitive(item, "type");
        if (!cJSON_IsString(type)) {
            continue;
        }
        if (!strcmp(type->valuestring, "function_call")) {
            cJSON_AddItemToArray(calls, cJSON_Duplicate(item, true));
        } else if (!strcmp(type->valuestring, "message")) {
            const cJSON *content = cJSON_GetObjectItemCaseSensitive(item, "content");
            const cJSON *part;
            cJSON_ArrayForEach(part, content) {
                const cJSON *t = cJSON_GetObjectItemCaseSensitive(part, "text");
                if (cJSON_IsString(t) && used < text_cap - 1) {
                    size_t n = strlen(t->valuestring);
                    if (n > text_cap - 1 - used) {
                        n = text_cap - 1 - used;
                    }
                    memcpy(text_out + used, t->valuestring, n);
                    used += n;
                    text_out[used] = '\0';
                }
            }
        }
    }
    return calls;
}

/*
 * One whole turn (one thing the user said): up to TOOL_MAX_ROUNDS round trips including tool calls.
 * Returns: the final text to speak (text_out, may be empty). tools_used gets the number of tools run this turn.
 */
static bool llm_turn(const char *key, const char *instructions, const cJSON *tools, const char *user_text,
                     char *text_out, size_t text_cap, int *tools_used)
{
    const live_voice_handlers_t *h = voice_shared_handlers();
    *tools_used = 0;
    text_out[0] = '\0';
    cJSON *input = cJSON_CreateArray();
    history_append_input(input);
    cJSON *first = cJSON_CreateObject();
    cJSON_AddStringToObject(first, "role", "user");
    cJSON *fc = cJSON_AddArrayToObject(first, "content");
    cJSON *fp = cJSON_CreateObject();
    cJSON_AddStringToObject(fp, "type", "input_text");
    cJSON_AddStringToObject(fp, "text", user_text);
    cJSON_AddItemToArray(fc, fp);
    cJSON_AddItemToArray(input, first);

    bool ok = false;
    for (int round = 0; round < TOOL_MAX_ROUNDS; round++) {
        cJSON *req = cJSON_CreateObject();
        cJSON_AddStringToObject(req, "model", APP_BACKEND_MODEL_DEFAULT);
        cJSON_AddBoolToObject(req, "store", false);
        cJSON_AddStringToObject(req, "instructions", instructions);
        cJSON_AddItemToObject(req, "input", cJSON_Duplicate(input, true));
        if (tools && cJSON_GetArraySize(tools)) {
            cJSON_AddItemToObject(req, "tools", cJSON_Duplicate(tools, true));
            cJSON_AddStringToObject(req, "tool_choice", "auto");
            cJSON_AddBoolToObject(req, "parallel_tool_calls", false);
        }
        char *body_text = cJSON_PrintUnformatted(req);
        cJSON_Delete(req);
        if (!body_text) {
            break;
        }

        char *resp = heap_caps_malloc(LLM_RESPONSE_CAP, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        body_t body = {.buf = resp, .cap = LLM_RESPONSE_CAP};
        const esp_http_client_config_t cfg = {
            .url = SAVER_LLM_URL,
            .method = HTTP_METHOD_POST,
            .crt_bundle_attach = esp_crt_bundle_attach,
            .timeout_ms = 20000,
            .event_handler = collect_body,
            .user_data = &body,
            .buffer_size = 2048,
        };
        esp_http_client_handle_t client = resp ? esp_http_client_init(&cfg) : NULL;
        bool http_ok = false;
        if (client) {
            set_auth(client, key);
            esp_http_client_set_header(client, "Content-Type", "application/json");
            esp_http_client_set_post_field(client, body_text, (int)strlen(body_text));
            http_ok = esp_http_client_perform(client) == ESP_OK && esp_http_client_get_status_code(client) == 200;
            if (!http_ok) {
                ESP_LOGW(TAG, "responses http %d", esp_http_client_get_status_code(client));
            }
            esp_http_client_cleanup(client);
        }
        free(body_text);
        if (!http_ok || !resp || !body.used) {
            free(resp);
            cJSON_Delete(input);
            return false;
        }
        resp[body.used] = '\0';
        cJSON *j = cJSON_Parse(resp);
        free(resp);
        const cJSON *output = cJSON_GetObjectItemCaseSensitive(j, "output");
        if (body.truncated || !j || !cJSON_IsArray(output)) {
            /* size and status only, no content */
            ESP_LOGW(TAG, "ai response unusable: %u B%s%s", (unsigned)body.used, body.truncated ? ", truncated" : "",
                     !j ? ", parse failed" : (!cJSON_IsArray(output) ? ", no output" : ""));
        }
        char round_text[TURN_TEXT_MAX];
        cJSON *calls = scan_output(output, round_text, sizeof(round_text));
        cJSON_Delete(j);

        int n_calls = cJSON_GetArraySize(calls);
        if (n_calls == 0) {
            snprintf(text_out, text_cap, "%s", round_text);
            cJSON_Delete(calls);
            ok = true;
            break;
        }
        /* Append tool results to the input and ask again (up to TOOL_MAX_ROUNDS times) */
        cJSON *call;
        cJSON_ArrayForEach(call, calls) {
            cJSON_AddItemToArray(input, cJSON_Duplicate(call, true));
            const cJSON *name = cJSON_GetObjectItemCaseSensitive(call, "name");
            const cJSON *args = cJSON_GetObjectItemCaseSensitive(call, "arguments");
            const cJSON *call_id = cJSON_GetObjectItemCaseSensitive(call, "call_id");
            cJSON *result = h && h->execute_tool && cJSON_IsString(name) && cJSON_IsString(args)
                                ? h->execute_tool(name->valuestring, args->valuestring)
                                : NULL;
            char *result_text = result ? cJSON_PrintUnformatted(result) : NULL;
            cJSON_Delete(result);
            cJSON *out_item = cJSON_CreateObject();
            cJSON_AddStringToObject(out_item, "type", "function_call_output");
            cJSON_AddItemToObject(out_item, "call_id", cJSON_Duplicate(call_id, true));
            cJSON_AddStringToObject(out_item, "output", result_text ? result_text : "{\"ok\":false}");
            free(result_text);
            cJSON_AddItemToArray(input, out_item);
            (*tools_used)++;
        }
        cJSON_Delete(calls);
    }
    cJSON_Delete(input);
    return ok;
}

/* ── Gemini: understanding + reply + tools in one go (docs/design-voice-saver-mode.md stage 2) ──
 *
 * Puts the audio (WAV, base64 inlineData) straight into generateContent (model gemini-3.1-flash-lite). Instead of a separate
 * transcription like OpenAI, the first round forces a call to report_transcript only (toolConfig
 * mode ANY + allowedFunctionNames) to get the transcript too, because the hang-up phrases, TLG-14 guard, and noise filter
 * need the transcript. (Structured output responseSchema can't be combined with function calling, checked at ai.google.dev 2026-10.)
 * Later rounds (up to TOOL_MAX_ROUNDS) are normal tool calls (AUTO), shaped like llm_turn().
 *
 * One contents array is filled by two functions in turn (gemini_transcribe_turn -> gemini_tool_turn), serving the same role as
 * llm_turn()'s input array: the model turn (function calls, including thoughtSignature if present) is returned as is in the next
 * request. The received parts are copied whole without editing, so any thoughtSignature
 * is preserved.
 */

static void gemini_add_decl(cJSON *decls, const char *json)
{
    cJSON *decl = cJSON_Parse(json);
    if (decl) {
        cJSON_AddItemToArray(decls, decl);
    }
}

static bool gemini_post(const char *key, const char *model, const cJSON *req, size_t response_cap, int timeout_ms,
                        cJSON **out)
{
    *out = NULL;
    char *body_text = cJSON_PrintUnformatted(req);
    if (!body_text) {
        return false;
    }
    char *resp = heap_caps_malloc(response_cap, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    body_t body = {.buf = resp, .cap = response_cap};
    char url[160];
    snprintf(url, sizeof(url), GEMINI_URL_FMT, model);
    const esp_http_client_config_t cfg = {
        .url = url,
        .method = HTTP_METHOD_POST,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = timeout_ms,
        .event_handler = collect_body,
        .user_data = &body,
        .buffer_size = 2048,
    };
    esp_http_client_handle_t client = resp ? esp_http_client_init(&cfg) : NULL;
    bool http_ok = false;
    if (client) {
        set_gemini_auth(client, key);
        esp_http_client_set_header(client, "Content-Type", "application/json");
        esp_http_client_set_post_field(client, body_text, (int)strlen(body_text));
        http_ok = esp_http_client_perform(client) == ESP_OK && esp_http_client_get_status_code(client) == 200;
        if (!http_ok) {
            ESP_LOGW(TAG, "gemini http %d", esp_http_client_get_status_code(client));
        }
        esp_http_client_cleanup(client);
    }
    free(body_text);
    if (!http_ok || !resp || !body.used) {
        free(resp);
        return false;
    }
    resp[body.used < response_cap ? body.used : response_cap - 1] = '\0';
    cJSON *j = cJSON_Parse(resp);
    if (body.truncated || !j) {
        ESP_LOGW(TAG, "gemini response unusable: %u B%s", (unsigned)body.used,
                 body.truncated ? ", truncated" : ", parse failed");
    }
    free(resp);
    if (!j) {
        return false;
    }
    *out = j;
    return true;
}

static const cJSON *gemini_response_parts(const cJSON *resp)
{
    const cJSON *candidates = cJSON_GetObjectItemCaseSensitive(resp, "candidates");
    const cJSON *first = cJSON_GetArrayItem(candidates, 0);
    const cJSON *content = cJSON_GetObjectItemCaseSensitive(first, "content");
    return cJSON_GetObjectItemCaseSensitive(content, "parts");
}

static void gemini_add_system_instruction(cJSON *req, const char *instructions)
{
    cJSON *sys = cJSON_AddObjectToObject(req, "systemInstruction");
    cJSON *parts = cJSON_AddArrayToObject(sys, "parts");
    cJSON *part = cJSON_CreateObject();
    cJSON_AddStringToObject(part, "text", instructions);
    cJSON_AddItemToArray(parts, part);
}

/* Put the recording buffer's WAV (header + PCM, reusing the spot laid out for STT) into contents as a base64 user turn.
 * Uploading the whole utterance (up to 30 s) costs too much PSRAM and time, so it is cut to 15 s (memory note, request 1) */
static void gemini_append_user_audio(cJSON *contents, size_t sample_count)
{
    size_t capped = sample_count > GEMINI_MAX_AUDIO_SAMPLES ? GEMINI_MAX_AUDIO_SAMPLES : sample_count;
    if (capped < sample_count) {
        ESP_LOGW(TAG, "gemini: utterance %u s capped to %u s for upload",
                 (unsigned)(sample_count / AUDIO_SAMPLE_RATE), (unsigned)(capped / AUDIO_SAMPLE_RATE));
    }
    size_t pcm_bytes = capped * sizeof(int16_t);
    uint8_t *wav = s_rec_buf + STT_PREAMBLE_LEN;   /* reuse the header + PCM spot laid out for the STT multipart */
    build_wav_header(wav, (uint32_t)pcm_bytes);
    size_t wav_len = WAV_HEADER_LEN + pcm_bytes;

    cJSON *turn = cJSON_CreateObject();
    cJSON_AddStringToObject(turn, "role", "user");
    cJSON *parts = cJSON_AddArrayToObject(turn, "parts");
    cJSON *part = cJSON_CreateObject();
    cJSON *inline_data = cJSON_AddObjectToObject(part, "inlineData");
    cJSON_AddStringToObject(inline_data, "mimeType", "audio/wav");
    size_t b64_cap = gemini_base64_encoded_len(wav_len) + 1;
    char *b64 = heap_caps_malloc(b64_cap, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (b64) {
        size_t n = gemini_base64_encode(wav, wav_len, b64, b64_cap);
        b64[n] = '\0';
        cJSON_AddStringToObject(inline_data, "data", b64);
        free(b64);
    } else {
        cJSON_AddStringToObject(inline_data, "data", "");
    }
    cJSON_AddItemToArray(parts, part);
    cJSON_AddItemToArray(contents, turn);
}

/* History (same place as OpenAI's history_append_input, in Gemini shape) */
static void gemini_append_history(cJSON *contents)
{
    int start = s_history_count < HISTORY_MAX_TURNS ? 0 : s_history_next;
    for (int i = 0; i < s_history_count; i++) {
        saver_turn_t *t = &s_history[(start + i) % HISTORY_MAX_TURNS];
        cJSON *turn = cJSON_CreateObject();
        cJSON_AddStringToObject(turn, "role", t->is_user ? "user" : "model");
        cJSON *parts = cJSON_AddArrayToObject(turn, "parts");
        cJSON *part = cJSON_CreateObject();
        cJSON_AddStringToObject(part, "text", t->text);
        cJSON_AddItemToArray(parts, part);
        cJSON_AddItemToArray(contents, turn);
    }
}

/*
 * Round 0: force a call to report_transcript only (mode ANY). On success, append to contents the model turn (function call,
 * with thoughtSignature as is) and its result (simple ack) turn, so gemini_tool_turn() can be called
 * right after. If the model doesn't call report_transcript (including network failure), it counts as a failure (treated like
 * a transcription failure, counted toward CONSECUTIVE_FAIL_MAX).
 */
static bool gemini_transcribe_turn(const char *key, const char *instructions, cJSON *contents, char *transcript_out,
                                   size_t cap)
{
    transcript_out[0] = '\0';
    cJSON *req = cJSON_CreateObject();
    gemini_add_system_instruction(req, instructions);
    cJSON_AddItemToObject(req, "contents", cJSON_Duplicate(contents, true));
    cJSON *tools = cJSON_AddArrayToObject(req, "tools");
    cJSON *tool_entry = cJSON_CreateObject();
    cJSON *decls = cJSON_AddArrayToObject(tool_entry, "functionDeclarations");
    gemini_add_decl(decls,
        "{\"name\":\"report_transcript\",\"description\":\"Call this exactly once, before anything else, with a "
        "verbatim transcript of what the user just said in the attached audio, in the language actually spoken. "
        "Use an empty string if the audio is silence or unintelligible noise.\",\"parameters\":{\"type\":\"OBJECT\","
        "\"properties\":{\"transcript\":{\"type\":\"STRING\"}},\"required\":[\"transcript\"]}}");
    cJSON_AddItemToArray(tools, tool_entry);
    cJSON *tool_config = cJSON_AddObjectToObject(req, "toolConfig");
    cJSON *fcc = cJSON_AddObjectToObject(tool_config, "functionCallingConfig");
    cJSON_AddStringToObject(fcc, "mode", "ANY");
    cJSON *allowed = cJSON_AddArrayToObject(fcc, "allowedFunctionNames");
    cJSON_AddItemToArray(allowed, cJSON_CreateString("report_transcript"));

    cJSON *resp = NULL;
    bool got = gemini_post(key, APP_GEMINI_MODEL_DEFAULT, req, GEMINI_RESPONSE_CAP, GEMINI_TRANSCRIBE_TIMEOUT_MS,
                           &resp);
    cJSON_Delete(req);
    if (!got) {
        return false;
    }
    const cJSON *parts = gemini_response_parts(resp);
    const cJSON *call = NULL, *p;
    cJSON_ArrayForEach(p, parts) {
        const cJSON *fc = cJSON_GetObjectItemCaseSensitive(p, "functionCall");
        if (cJSON_IsObject(fc)) {
            call = fc;
            break;
        }
    }
    if (call) {
        const cJSON *args = cJSON_GetObjectItemCaseSensitive(call, "args");
        const cJSON *t = args ? cJSON_GetObjectItemCaseSensitive(args, "transcript") : NULL;
        if (cJSON_IsString(t)) {
            snprintf(transcript_out, cap, "%s", t->valuestring);
        }
        /* Append the model turn (received parts as is, including thoughtSignature) and acknowledge it with a dummy result */
        cJSON *model_turn = cJSON_CreateObject();
        cJSON_AddStringToObject(model_turn, "role", "model");
        cJSON_AddItemToObject(model_turn, "parts", cJSON_Duplicate(parts, true));
        cJSON_AddItemToArray(contents, model_turn);
        cJSON *fr_turn = cJSON_CreateObject();
        cJSON_AddStringToObject(fr_turn, "role", "user");
        cJSON *fr_parts = cJSON_AddArrayToObject(fr_turn, "parts");
        cJSON *fr_part = cJSON_CreateObject();
        cJSON *fr = cJSON_AddObjectToObject(fr_part, "functionResponse");
        cJSON_AddStringToObject(fr, "name", "report_transcript");
        const cJSON *id = cJSON_GetObjectItemCaseSensitive(call, "id");
        if (cJSON_IsString(id)) {
            cJSON_AddStringToObject(fr, "id", id->valuestring);
        }
        cJSON *fr_response = cJSON_AddObjectToObject(fr, "response");
        cJSON_AddStringToObject(fr_response, "result", "ok");
        cJSON_AddItemToArray(fr_parts, fr_part);
        cJSON_AddItemToArray(contents, fr_turn);
    }
    cJSON_Delete(resp);
    return call != NULL;
}

/* Rounds 1..TOOL_MAX_ROUNDS: normal tool calls (AUTO), shaped like llm_turn() */
static bool gemini_tool_turn(const char *key, const char *instructions, const cJSON *gemini_tools, cJSON *contents,
                            char *reply_out, size_t reply_cap, int *tools_used)
{
    const live_voice_handlers_t *h = voice_shared_handlers();
    *tools_used = 0;
    reply_out[0] = '\0';
    bool ok = false;
    for (int round = 0; round < TOOL_MAX_ROUNDS; round++) {
        cJSON *req = cJSON_CreateObject();
        gemini_add_system_instruction(req, instructions);
        cJSON_AddItemToObject(req, "contents", cJSON_Duplicate(contents, true));
        if (gemini_tools && cJSON_GetArraySize(gemini_tools)) {
            cJSON *tools = cJSON_AddArrayToObject(req, "tools");
            cJSON *tool_entry = cJSON_CreateObject();
            cJSON_AddItemToObject(tool_entry, "functionDeclarations", cJSON_Duplicate(gemini_tools, true));
            cJSON_AddItemToArray(tools, tool_entry);
        }
        cJSON *resp = NULL;
        bool got = gemini_post(key, APP_GEMINI_MODEL_DEFAULT, req, GEMINI_RESPONSE_CAP, GEMINI_TOOL_TIMEOUT_MS, &resp);
        cJSON_Delete(req);
        if (!got) {
            return false;
        }
        const cJSON *parts = gemini_response_parts(resp);
        char round_text[TURN_TEXT_MAX];
        round_text[0] = '\0';
        size_t used = 0;
        cJSON *calls = cJSON_CreateArray();
        const cJSON *p;
        cJSON_ArrayForEach(p, parts) {
            const cJSON *fc = cJSON_GetObjectItemCaseSensitive(p, "functionCall");
            const cJSON *txt = cJSON_GetObjectItemCaseSensitive(p, "text");
            if (cJSON_IsObject(fc)) {
                cJSON_AddItemToArray(calls, cJSON_Duplicate(fc, true));
            } else if (cJSON_IsString(txt) && used < sizeof(round_text) - 1) {
                size_t n = strlen(txt->valuestring);
                if (n > sizeof(round_text) - 1 - used) {
                    n = sizeof(round_text) - 1 - used;
                }
                memcpy(round_text + used, txt->valuestring, n);
                used += n;
                round_text[used] = '\0';
            }
        }
        int n_calls = cJSON_GetArraySize(calls);
        if (n_calls == 0) {
            snprintf(reply_out, reply_cap, "%s", round_text);
            cJSON_Delete(calls);
            cJSON_Delete(resp);
            ok = true;
            break;
        }
        cJSON *model_turn = cJSON_CreateObject();
        cJSON_AddStringToObject(model_turn, "role", "model");
        cJSON_AddItemToObject(model_turn, "parts", cJSON_Duplicate(parts, true));
        cJSON_AddItemToArray(contents, model_turn);
        cJSON *fr_turn = cJSON_CreateObject();
        cJSON_AddStringToObject(fr_turn, "role", "user");
        cJSON *fr_parts = cJSON_AddArrayToObject(fr_turn, "parts");
        const cJSON *call;
        cJSON_ArrayForEach(call, calls) {
            const cJSON *name = cJSON_GetObjectItemCaseSensitive(call, "name");
            const cJSON *args = cJSON_GetObjectItemCaseSensitive(call, "args");
            const cJSON *id = cJSON_GetObjectItemCaseSensitive(call, "id");
            cJSON *result = NULL;
            if (h && h->execute_tool && cJSON_IsString(name)) {
                char *args_text = args ? cJSON_PrintUnformatted(args) : NULL;
                result = h->execute_tool(name->valuestring, args_text ? args_text : "{}");
                free(args_text);
                (*tools_used)++;
            }
            cJSON *fr_part = cJSON_CreateObject();
            cJSON *fr = cJSON_AddObjectToObject(fr_part, "functionResponse");
            cJSON_AddStringToObject(fr, "name", cJSON_IsString(name) ? name->valuestring : "");
            if (cJSON_IsString(id)) {
                cJSON_AddStringToObject(fr, "id", id->valuestring);
            }
            cJSON_AddItemToObject(fr, "response", result ? result : cJSON_Parse("{\"ok\":false}"));
            cJSON_AddItemToArray(fr_parts, fr_part);
        }
        cJSON_AddItemToArray(contents, fr_turn);
        cJSON_Delete(calls);
        cJSON_Delete(resp);
    }
    return ok;
}

/* Map the voice name from assistant settings to a Gemini TTS prebuilt voice. No names overlap, so it almost always falls back to
 * Kore (the Gemini version of "same name if it exists, otherwise the default" from design doc Sections 5.5, 11.6). gemini_live.c
 * uses the same table (exported via saver_voice.h; stage 3: Gemini Live's speechConfig.voiceConfig uses the same names) */
const char *gemini_tts_voice(const char *voice)
{
    static const char *const GEMINI_VOICES[] = {
        "Achernar", "Achird", "Algenib", "Algieba", "Alnilam", "Aoede", "Autonoe", "Callirrhoe", "Charon",
        "Despina", "Enceladus", "Erinome", "Fenrir", "Gacrux", "Iapetus", "Kore", "Laomedeia", "Leda", "Orus",
        "Pulcherrima", "Puck", "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Sulafat", "Umbriel", "Zephyr",
        "Zubenelgenubi", "Vindemiatrix",
    };
    for (size_t i = 0; voice && i < sizeof(GEMINI_VOICES) / sizeof(GEMINI_VOICES[0]); i++) {
        if (!strcasecmp(voice, GEMINI_VOICES[i])) {
            return GEMINI_VOICES[i];
        }
    }
    return "Kore";
}

/* Synthesize one sentence with Gemini TTS and play it. No streaming (request 6: the response is a JSON envelope, so chunk parsing
 * gets complicated, "non-streaming is fine"). The full response is received, decoded, converted 24k->16k, and queued for playback.
 * So barge-in may respond a beat later than the OpenAI path (raw PCM stream) (known limitation, documented) */
static bool gemini_tts_speak(const char *key, const char *voice, const char *sentence, size_t len)
{
    char *text = malloc(len + 1);
    if (!text) {
        return false;
    }
    memcpy(text, sentence, len);
    text[len] = '\0';

    cJSON *req = cJSON_CreateObject();
    gemini_add_system_instruction(req,
        "Speak only the given text verbatim, nothing else. Speak slowly and clearly, in a warm tone.");
    cJSON *contents = cJSON_AddArrayToObject(req, "contents");
    cJSON *turn = cJSON_CreateObject();
    cJSON_AddStringToObject(turn, "role", "user");
    cJSON *parts = cJSON_AddArrayToObject(turn, "parts");
    cJSON *part = cJSON_CreateObject();
    cJSON_AddStringToObject(part, "text", text);
    cJSON_AddItemToArray(parts, part);
    cJSON_AddItemToArray(contents, turn);
    free(text);
    cJSON *gen = cJSON_AddObjectToObject(req, "generationConfig");
    cJSON *modalities = cJSON_AddArrayToObject(gen, "responseModalities");
    cJSON_AddItemToArray(modalities, cJSON_CreateString("AUDIO"));
    cJSON *speech = cJSON_AddObjectToObject(gen, "speechConfig");
    cJSON *vc = cJSON_AddObjectToObject(speech, "voiceConfig");
    cJSON *pvc = cJSON_AddObjectToObject(vc, "prebuiltVoiceConfig");
    cJSON_AddStringToObject(pvc, "voiceName", gemini_tts_voice(voice));

    cJSON *resp = NULL;
    bool got = gemini_post(key, APP_GEMINI_TTS_MODEL_DEFAULT, req, GEMINI_TTS_RESPONSE_CAP, GEMINI_TTS_TIMEOUT_MS,
                           &resp);
    cJSON_Delete(req);
    if (!got) {
        return false;
    }
    const cJSON *parts_out = gemini_response_parts(resp);
    const cJSON *p;
    const char *b64 = NULL;
    cJSON_ArrayForEach(p, parts_out) {
        const cJSON *inline_data = cJSON_GetObjectItemCaseSensitive(p, "inlineData");
        const cJSON *data = inline_data ? cJSON_GetObjectItemCaseSensitive(inline_data, "data") : NULL;
        if (cJSON_IsString(data)) {
            b64 = data->valuestring;
            break;
        }
    }
    if (!b64) {
        ESP_LOGW(TAG, "gemini tts: no audio in response");
        cJSON_Delete(resp);
        return false;
    }
    bool played = false;
    size_t b64_len = strlen(b64);
    uint8_t *pcm = heap_caps_malloc(b64_len, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);   /* decoded result <= length */
    size_t pcm_len = pcm ? gemini_base64_decode(b64, b64_len, pcm, b64_len) : SIZE_MAX;
    if (pcm && pcm_len != SIZE_MAX) {
        /* Expects 24kHz s16le (per request and design). If it comes in a WAV container (RIFF/WAVE), skip the 44-byte
         * header (assumed to be standard PCM WAV like our build_wav_header). Needs checking on real hardware */
        size_t offset = (pcm_len >= 44 && !memcmp(pcm, "RIFF", 4) && !memcmp(pcm + 8, "WAVE", 4)) ? 44 : 0;
        saver_resample_t resampler;
        saver_resample_reset(&resampler);
        const int16_t *pcm24 = (const int16_t *)(pcm + offset);
        size_t samples24 = (pcm_len - offset) / sizeof(int16_t);
        for (size_t i = 0; i < samples24 && !atomic_load(&s_barge) && !voice_shared_stopping(); i += 1024) {
            size_t n = samples24 - i < 1024 ? samples24 - i : 1024;
            int16_t pcm16[700];
            size_t out_n = saver_resample_24to16(&resampler, pcm24 + i, n, pcm16, sizeof(pcm16) / sizeof(pcm16[0]));
            audio_core_voice_enqueue(pcm16, out_n);
        }
        played = true;
    }
    free(pcm);
    cJSON_Delete(resp);
    return played;
}

/* ── Speech synthesis (per sentence, converted to 16kHz as it arrives and queued for playback) ─── */

typedef struct {
    saver_resample_t resampler;
    uint8_t          odd_byte;
    bool             has_odd;
} tts_stream_t;

static esp_err_t tts_event(esp_http_client_event_t *evt)
{
    if (evt->event_id != HTTP_EVENT_ON_DATA || !evt->data_len) {
        return ESP_OK;
    }
    if (atomic_load(&s_barge) || voice_shared_stopping()) {
        return ESP_FAIL;   /* abort the transfer (Key2 barge-in or session end) */
    }
    tts_stream_t *s = evt->user_data;
    const uint8_t *bytes = evt->data;
    int len = evt->data_len;
    int16_t pcm24[1024];
    size_t pcm24_n = 0;
    int i = 0;
    if (s->has_odd && len) {
        int16_t sample = (int16_t)(s->odd_byte | (bytes[0] << 8));
        pcm24[pcm24_n++] = sample;
        i = 1;
        s->has_odd = false;
    }
    for (; i + 1 < len; i += 2) {
        if (pcm24_n >= sizeof(pcm24) / sizeof(pcm24[0])) {
            int16_t pcm16[700];
            size_t n = saver_resample_24to16(&s->resampler, pcm24, pcm24_n, pcm16, sizeof(pcm16) / sizeof(pcm16[0]));
            audio_core_voice_enqueue(pcm16, n);
            pcm24_n = 0;
        }
        pcm24[pcm24_n++] = (int16_t)(bytes[i] | (bytes[i + 1] << 8));
    }
    if (i < len) {
        s->odd_byte = bytes[i];
        s->has_odd = true;
    }
    if (pcm24_n) {
        int16_t pcm16[700];
        size_t n = saver_resample_24to16(&s->resampler, pcm24, pcm24_n, pcm16, sizeof(pcm16) / sizeof(pcm16[0]));
        audio_core_voice_enqueue(pcm16, n);
    }
    return ESP_OK;
}

/*
 * Map the voice from assistant settings (a Live gpt-live voice name) to a speech synthesis (TTS) voice.
 * Sending a name TTS doesn't have gives a 400 and no sound, so use the same name if it exists, otherwise marin.
 */
static const char *tts_voice(const char *voice)
{
    static const char *const TTS_VOICES[] = {"alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx",
                                             "sage", "shimmer", "verse", "marin", "cedar"};
    for (size_t i = 0; voice && i < sizeof(TTS_VOICES) / sizeof(TTS_VOICES[0]); i++) {
        if (!strcmp(voice, TTS_VOICES[i])) {
            return TTS_VOICES[i];
        }
    }
    return "marin";
}

/* Synthesize one sentence and play it. false if stopped midway (barge-in or end) */
static bool tts_speak(const char *key, const char *voice, const char *sentence, size_t len)
{
    char *text = malloc(len + 1);
    if (!text) {
        return false;
    }
    memcpy(text, sentence, len);
    text[len] = '\0';

    cJSON *req = cJSON_CreateObject();
    cJSON_AddStringToObject(req, "model", SAVER_TTS_MODEL);
    cJSON_AddStringToObject(req, "input", text);
    cJSON_AddStringToObject(req, "voice", tts_voice(voice));
    cJSON_AddStringToObject(req, "response_format", "pcm");
    cJSON_AddStringToObject(req, "instructions", "Speak slowly and clearly, warm tone.");
    char *body_text = cJSON_PrintUnformatted(req);
    cJSON_Delete(req);
    free(text);
    if (!body_text) {
        return false;
    }

    tts_stream_t stream = {0};
    saver_resample_reset(&stream.resampler);
    const esp_http_client_config_t cfg = {
        .url = SAVER_TTS_URL,
        .method = HTTP_METHOD_POST,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 20000,
        .event_handler = tts_event,
        .user_data = &stream,
        .buffer_size = 2048,
    };
    esp_http_client_handle_t client = esp_http_client_init(&cfg);
    bool ok = false;
    if (client) {
        set_auth(client, key);
        esp_http_client_set_header(client, "Content-Type", "application/json");
        esp_http_client_set_post_field(client, body_text, (int)strlen(body_text));
        esp_err_t err = esp_http_client_perform(client);
        ok = err == ESP_OK && esp_http_client_get_status_code(client) == 200;
        if (!ok && err != ESP_OK) {
            ESP_LOGW(TAG, "tts aborted or failed: %s", esp_err_to_name(err));
        }
        esp_http_client_cleanup(client);
    }
    free(body_text);
    return ok;
}

/* Split text into sentences and synthesize them in order. Stops midway on barge-in or end */
typedef struct {
    const char *key;
    const char *voice;
    bool        gemini;
    bool        stopped;
} speak_ctx_t;

static void speak_sentence_cb(const char *sentence, size_t len, void *ctx)
{
    speak_ctx_t *c = ctx;
    if (c->stopped || atomic_load(&s_barge) || voice_shared_stopping()) {
        c->stopped = true;
        return;
    }
    bool ok = c->gemini ? gemini_tts_speak(c->key, c->voice, sentence, len) : tts_speak(c->key, c->voice, sentence, len);
    if (!ok) {
        c->stopped = true;
    }
}

static void speak_text(const char *key, const char *voice, bool gemini, const char *text)
{
    speak_ctx_t ctx = {.key = key, .voice = voice, .gemini = gemini, .stopped = false};
    saver_text_split_sentences(text, speak_sentence_cb, &ctx);
}

/* ── Session ─────────────────────────────────────────────────── */

static void touch_activity(uint32_t *activity_ms)
{
    *activity_ms = now_ms();
}

static void saver_voice_run(void)
{
    const live_voice_handlers_t *h = voice_shared_handlers();
    bool gemini = provider_is_gemini();    /* docs/design-voice-saver-mode.md stage 2: same frame, only the network steps differ */
    voice_shared_set_status("Connecting Wi-Fi");
    history_reset();
    atomic_store(&s_rec_len_samples, 0);
    s_preroll_write = 0;
    s_preroll_full = false;
    s_carry_used = 0;
    saver_endpoint_reset(&s_endpoint);
    atomic_store(&s_barge, false);
    xQueueReset(s_utterances);
    xSemaphoreTake(s_pending_lock, portMAX_DELAY);
    free(s_pending_text);
    s_pending_text = NULL;
    xSemaphoreGive(s_pending_lock);

    if (h->on_session_start) {
        h->on_session_start();
    }
    if (!wake_pause()) {
        voice_shared_set_status("Wake detector did not release memory");
        app_error_t code = APP_ERR_VOICE_INTERNAL;
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
        voice_shared_end(true);
        return;
    }
    voice_shared_reserve_release();
    net_set_power_save(false);
    bool had_error = false;
    if (!net_wait_connected(WIFI_WAIT_MS)) {
        voice_shared_set_status("Wi-Fi unavailable");
        app_error_t code = APP_ERR_WIFI;
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
        had_error = true;
    }
    for (uint32_t w = 0; !had_error && w < CLOCK_WAIT_MS && !net_time_valid() && !voice_shared_stopping(); w += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!had_error && !net_time_valid()) {
        voice_shared_set_status("Clock sync failed");
        app_error_t code = APP_ERR_CLOCK;
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
        had_error = true;
    }
    char key[513];
    size_t key_len = sizeof(key) - 1;
    secret_id_t key_id = gemini ? SECRET_GEMINI_KEY : SECRET_OPENAI_KEY;
    if (!had_error && (secret_get(key_id, key, &key_len) != ESP_OK || key_len == 0)) {
        voice_shared_set_status(gemini ? "Gemini API key not set" : "OpenAI API key not set");
        app_error_t code = APP_ERR_NO_API_KEY;
        app_events_post(APP_EVT_ERROR, &code, sizeof(code), 0);
        had_error = true;
    }
    if (had_error) {
        voice_shared_reserve_take();
        wake_resume();
        net_set_power_save(true);
        voice_shared_end(true);
        return;
    }
    key[key_len] = '\0';

    char voice[32] = "marin";
    char *instructions =
        h->build_saver_instructions ? h->build_saver_instructions(gemini, voice, sizeof(voice)) : NULL;
    cJSON *tools = h->build_saver_tools ? h->build_saver_tools() : NULL;
    /* Gemini: convert the same tools to functionDeclarations shape (gemini_schema.c). Non-function tools such as
     * web_search drop out automatically during conversion (Section 2.5: Gemini Saver mode gets no search tool) */
    cJSON *gemini_tools = gemini ? gemini_schema_convert_tools(tools) : NULL;
    if (!instructions) {
        instructions = strdup("Answer briefly for speech.");
    }

    hangup_phrase_t hangup;
    hangup_phrase_reset(&hangup);
    uint32_t began = now_ms(), activity = began, max_ms, idle_ms;
    voice_shared_take_next_limits(&max_ms, &idle_ms);
    max_ms = max_ms ? max_ms : APP_VOICE_MAX_SESSION_MS;
    idle_ms = idle_ms ? idle_ms : APP_VOICE_IDLE_TIMEOUT_MS;
    ESP_LOGI(TAG, "limits: idle %u s, max %u s", (unsigned)(idle_ms / 1000), (unsigned)(max_ms / 1000));

    uint32_t diag_ms = now_ms();
    atomic_store(&s_session_active, true);
    voice_shared_set_ready(true);
    voice_shared_set_state(VOICE_LIVE);
    audio_core_tone();

    int consecutive_fail = 0;
    const char *end_reason = NULL;
    app_error_t end_code = APP_ERR_NONE;

    while (!voice_shared_stopping()) {
        uint32_t now = now_ms();
        if (now - began > max_ms) {
            end_reason = "Conversation limit reached";
            break;
        }
        if (s_endpoint.in_speech) {
            activity = now;     /* the idle timer doesn't count while the person is speaking */
        }
        if ((int32_t)(now - activity) > (int32_t)idle_ms) {
            end_reason = "Idle timeout";
            break;
        }

        /* Reminder sentences (reminders, Section 11.7): synthesize as is without the AI, then back to listening */
        xSemaphoreTake(s_pending_lock, portMAX_DELAY);
        char *pending = s_pending_text;
        s_pending_text = NULL;
        xSemaphoreGive(s_pending_lock);
        if (pending) {
            atomic_store(&s_barge, false);
            speak_text(key, voice, gemini, pending);
            free(pending);
            touch_activity(&activity);
            continue;
        }

        if (h->on_tick) {
            h->on_tick();
        }
        atomic_store(&s_listening, true);
        if (now_ms() - diag_ms >= 5000) {
            diag_ms = now_ms();
            ESP_LOGI(TAG, "listen 5 s: frames %u, vad speech %u, loud %u, peak %d (x%d)%s", s_diag_frames, s_diag_vad,
                     s_diag_loud, s_diag_peak, SAVER_INPUT_GAIN, s_vad ? "" : " [no VAD]");
            s_diag_frames = s_diag_vad = s_diag_loud = 0;
            s_diag_peak = 0;
        }
        saver_utterance_t utt;
        if (xQueueReceive(s_utterances, &utt, pdMS_TO_TICKS(100)) != pdTRUE) {
            continue;
        }
        atomic_store(&s_listening, false);
        s_carry_used = 0;   /* don't mix a partial frame into the next listening start */
        if (utt.sample_count == 0) {
            continue;
        }
        unsigned speech_ms = (unsigned)((uint64_t)utt.sample_count * 1000 / AUDIO_SAMPLE_RATE);

        char transcript[TURN_TEXT_MAX];
        cJSON *gcontents = NULL;
        uint32_t t_stt0 = now_ms();
        bool stt_ok;
        if (gemini) {
            /* Gemini: no separate transcription step (Section 2.5). The audio goes straight into generateContent, and the model
             * first calls report_transcript so we get the transcript too. contents is then used for the tool rounds */
            gcontents = cJSON_CreateArray();
            gemini_append_history(gcontents);
            gemini_append_user_audio(gcontents, utt.sample_count);
            stt_ok = gemini_transcribe_turn(key, instructions, gcontents, transcript, sizeof(transcript));
        } else {
            stt_ok = stt_transcribe(key, utt.sample_count, transcript, sizeof(transcript));
        }
        uint32_t t_stt1 = now_ms();
        if (!stt_ok) {
            cJSON_Delete(gcontents);
            consecutive_fail++;
            ESP_LOGW(TAG, "%s failed (%d/%d)", gemini ? "ai" : "stt", consecutive_fail, CONSECUTIVE_FAIL_MAX);
            if (consecutive_fail >= CONSECUTIVE_FAIL_MAX) {
                end_reason = "Voice dropped";
                end_code = APP_ERR_VOICE_DROPPED;
                break;
            }
            audio_core_tone();
            continue;
        }
        if (saver_text_is_noise(transcript)) {
            cJSON_Delete(gcontents);
            continue;   /* noise or empty result: avoids cost and off-target replies, and doesn't reset the idle timer. Gemini has already
                         * made one call (Section 2.5 limitation, documented), but still runs no tools and stops here */
        }
        consecutive_fail = 0;
        touch_activity(&activity);
        hangup_phrase_feed(&hangup, transcript, now_ms());
        if (h->on_user_input) {
            h->on_user_input();     /* guard_user_input + notes_reminder_acked (4.9/4.10, TLG-14) */
        }
        if (hangup_phrase_ready(&hangup, now_ms())) {
            cJSON_Delete(gcontents);
            end_reason = "Hangup phrase heard";
            break;
        }

        char reply[TURN_TEXT_MAX];
        int tools_used = 0;
        uint32_t t_ai0 = now_ms();
        bool ai_ok = gemini ? gemini_tool_turn(key, instructions, gemini_tools, gcontents, reply, sizeof(reply),
                                               &tools_used)
                            : llm_turn(key, instructions, tools, transcript, reply, sizeof(reply), &tools_used);
        uint32_t t_ai1 = now_ms();
        cJSON_Delete(gcontents);
        if (!ai_ok) {
            consecutive_fail++;
            ESP_LOGW(TAG, "ai failed (%d/%d)", consecutive_fail, CONSECUTIVE_FAIL_MAX);
            if (consecutive_fail >= CONSECUTIVE_FAIL_MAX) {
                end_reason = "Voice dropped";
                end_code = APP_ERR_VOICE_DROPPED;
                break;
            }
            audio_core_tone();
            continue;
        }
        consecutive_fail = 0;
        history_add(true, transcript);
        if (reply[0]) {
            history_add(false, reply);
        } else {
            /* Don't pass silently when the reply text is empty (the user would think it's broken) */
            ESP_LOGW(TAG, "ai returned no text (tools %d)", tools_used);
            snprintf(reply, sizeof(reply), "%s", "Sorry, I didn't catch that. Could you say it again?");
        }

        uint32_t t_audio0 = now_ms();
        atomic_store(&s_barge, false);
        if (reply[0]) {
            speak_text(key, voice, gemini, reply);
        }
        uint32_t t_audio1 = now_ms();
        touch_activity(&activity);

        if (gemini) {
            ESP_LOGI(TAG, "gemini speech %u.%u s -> ai %u.%u s (tools %d) -> tts %u.%u s", speech_ms / 1000,
                     (speech_ms % 1000) / 100, (unsigned)(t_ai1 - t_stt0) / 1000,
                     ((unsigned)(t_ai1 - t_stt0) % 1000) / 100, tools_used, (unsigned)(t_audio1 - t_audio0) / 1000,
                     ((unsigned)(t_audio1 - t_audio0) % 1000) / 100);
        } else {
            ESP_LOGI(TAG, "speech %u.%u s -> stt %u.%u s -> ai %u.%u s (tools %d) -> tts %u.%u s",
                     speech_ms / 1000, (speech_ms % 1000) / 100, (unsigned)(t_stt1 - t_stt0) / 1000,
                     ((unsigned)(t_stt1 - t_stt0) % 1000) / 100, (unsigned)(t_ai1 - t_ai0) / 1000,
                     ((unsigned)(t_ai1 - t_ai0) % 1000) / 100, tools_used, (unsigned)(t_audio1 - t_audio0) / 1000,
                     ((unsigned)(t_audio1 - t_audio0) % 1000) / 100);
        }
    }

    if (!end_reason) {
        end_reason = "Stopped";
    }
    ESP_LOGI(TAG, "session ended: %s", end_reason);
    voice_shared_set_status(end_reason);
    if (end_code != APP_ERR_NONE) {
        app_events_post(APP_EVT_ERROR, &end_code, sizeof(end_code), 0);
    }
    atomic_store(&s_listening, false);
    atomic_store(&s_session_active, false);
    audio_core_voice_clear();
    memset(key, 0, sizeof(key));
    free(instructions);
    cJSON_Delete(tools);
    cJSON_Delete(gemini_tools);
    if (h->on_session_end) {
        h->on_session_end();
    }
    voice_shared_reserve_take();   /* before reloading the wake-word model (same order as the Live engine) */
    wake_resume();
    net_set_power_save(true);
    voice_shared_end(true);    /* status was already set just above (don't overwrite the end reason with "Ready") */
}

void saver_voice_task_entry(void *arg)
{
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        saver_voice_run();
    }
}

void saver_voice_barge_in(void)
{
    if (!atomic_load(&s_session_active)) {
        return;
    }
    atomic_store(&s_barge, true);
    audio_core_voice_clear();
}

esp_err_t saver_voice_text(const char *text)
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
    return ESP_OK;
}

unsigned saver_voice_selftest(void)
{
    unsigned passed = 0;
    if (saver_endpoint_selftest()) {
        passed |= 1;
    }
    if (saver_text_selftest()) {
        passed |= 2;
    }
    if (saver_resample_selftest()) {
        passed |= 4;
    }
    if (gemini_schema_selftest()) {
        passed |= 8;
    }
    if (gemini_base64_selftest()) {
        passed |= 16;
    }
    if (gemini_live_proto_selftest()) {    /* stage 3: building and reading Gemini Live messages (used by gemini_live.c) */
        passed |= 32;
    }
    return passed;
}

esp_err_t saver_voice_init(void)
{
    s_rec_capacity = STT_PREAMBLE_LEN + WAV_HEADER_LEN + SAVER_PCM_MAX_BYTES + STT_TAIL_LEN;
    s_rec_buf = heap_caps_malloc(s_rec_capacity, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_preroll = heap_caps_malloc(SAVER_PREROLL_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_history = heap_caps_malloc(HISTORY_MAX_TURNS * sizeof(saver_turn_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_rec_buf || !s_preroll || !s_history) {
        return ESP_ERR_NO_MEM;
    }
    s_utterances = xQueueCreate(1, sizeof(saver_utterance_t));
    s_pending_lock = xSemaphoreCreateMutex();
    if (!s_utterances || !s_pending_lock) {
        return ESP_ERR_NO_MEM;
    }
    s_vad = vad_create_with_param(SAVER_VAD_MODE, AUDIO_SAMPLE_RATE, SAVER_VAD_FRAME_MS, 0, 0);
    if (!s_vad) {
        ESP_LOGW(TAG, "VAD init failed; saver mode will not hear speech (needs real-device check)");
    }
    ESP_ERROR_CHECK(audio_core_add_mic_sink(saver_voice_feed));
    return ESP_OK;
}
