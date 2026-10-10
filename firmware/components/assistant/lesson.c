/*
 * English tutor (see lesson.h). New on 2026-10-03.
 *
 * Flow
 *   App "Start free talking" → lesson_start → STARTING → live_voice_start
 *   → assistant_start_event calls lesson_start_event → ACTIVE (tutor instructions, lesson length limit)
 *   → collects transcript fragments and extracts corrected expressions every 45 seconds (tool worker, HTTPS)
 *   → session ends (time, button, hang-up phrase, app) → SUMMARIZING → final summary → DONE, saved to /storage/lesson.json
 *   A voice request ("영어 공부하자", let's study English) waits in WAITING, then goes to STARTING when the current conversation ends.
 *
 * Transcripts and summaries are never logged (design document 2.2, Coding Rules). The state struct and transcript buffer are in PSRAM.
 */
#include "lesson.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "app_config.h"
#include "app_events.h"
#include "assistant.h"
#include "audio_core.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "live_voice.h"
#include "nvs.h"
#include "secret_store.h"

static const char *TAG = "LESSON";

#define TRANSCRIPT_MAX     (24 * 1024)
#define MAX_CORRECTIONS    20
#define MAX_PRONUNCIATION  12
#define EXTRACT_EVERY_MS   45000
#define EXTRACT_MIN_NEW    120     /* extract only once this many new transcript bytes have piled up */
#define WINDOW_OVERLAP     400
#define WINDOW_MAX         6000
#define FINAL_WINDOW_MAX   12000
#define RESPONSE_MAX       (16 * 1024)
#define IDLE_MS            (60 * 1000)       /* wait a full minute even if speech pauses for thinking (lessons are at most 5 minutes, so 2 minutes → 1 minute) */
#define WRAP_UP_MS         60000             /* tell the tutor to wrap up 1 minute before the end */
#define LESSON_FILE        "/storage/lesson.json"
#define RESPONSES_URL      "https://api.openai.com/v1/responses"

typedef enum { ST_IDLE, ST_WAITING, ST_STARTING, ST_ACTIVE, ST_SUMMARIZING, ST_DONE } lesson_state_t;
static const char *const STATE_NAMES[] = {"idle", "waiting", "starting", "active", "summarizing", "done"};
static const char *const COURSE_IDS[LESSON_COURSE_COUNT] = {"pron", "basic", "daily", "biz", "adv"};

typedef struct {
    char original[160];
    char better[160];
    char note[120];
} correction_t;

typedef struct {
    char word[40];
    char tip[120];
} pronunciation_t;

typedef struct {
    lesson_state_t state;
    lesson_cfg_t cfg;
    uint32_t started_ms, ended_ms;
    bool warned, extracting;
    char topic[96];
    char next_topic[96];
    correction_t corrections[MAX_CORRECTIONS];
    int n_corrections;
    pronunciation_t pronunciation[MAX_PRONUNCIATION];
    int n_pronunciation;
    char *text;             /* "\nLearner: …\nTeacher: …" */
    size_t text_len, extracted_upto;
    int last_speaker;       /* -1 none, 0 tutor, 1 learner */
    uint32_t last_extract_ms;
} lesson_t;

static lesson_t *L;
static SemaphoreHandle_t s_lock;
static bool s_record_loaded;    /* the last summary file is loaded on the first read after /storage is mounted */
static void load_record(void);
static lesson_cfg_t s_defaults = {.course = LESSON_BASIC, .explain_korean = true, .slow = true, .minutes = 5};

#define LOCK()   xSemaphoreTake(s_lock, portMAX_DELAY)
#define UNLOCK() xSemaphoreGive(s_lock)

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void notify(void)
{
    app_events_post(APP_EVT_LESSON, NULL, 0, 0);
}

static void copy_str(char *dst, size_t cap, const char *src)
{
    snprintf(dst, cap, "%s", src ? src : "");
}

/* ── Settings ───────────────────────────────────────────── */

static void save_defaults(void)
{
    nvs_handle_t h;
    if (nvs_open("lesson", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_blob(h, "cfg", &s_defaults, sizeof(s_defaults));
        nvs_commit(h);
        nvs_close(h);
    }
}

static void load_defaults(void)
{
    nvs_handle_t h;
    lesson_cfg_t c;
    size_t len = sizeof(c);
    if (nvs_open("lesson", NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_blob(h, "cfg", &c, &len) == ESP_OK && len == sizeof(c) && c.course < LESSON_COURSE_COUNT) {
            /* Max 5 minutes because of cost (2026-10-04). Previously saved 10, 20, 30 minutes become 5 */
            if (c.minutes != 3 && c.minutes != 5) {
                c.minutes = 5;
            }
            s_defaults = c;
        }
        nvs_close(h);
    }
}

bool lesson_parse_cfg(const cJSON *j, lesson_cfg_t *out)
{
    *out = s_defaults;
    if (!j) {
        return true;
    }
    if (!cJSON_IsObject(j)) {
        return false;
    }
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(j, "course");
    if (v) {
        int found = -1;
        for (int i = 0; cJSON_IsString(v) && i < LESSON_COURSE_COUNT; i++) {
            if (!strcmp(v->valuestring, COURSE_IDS[i])) {
                found = i;
            }
        }
        if (found < 0) {
            return false;
        }
        out->course = (lesson_course_t)found;
    }
    v = cJSON_GetObjectItemCaseSensitive(j, "explain");
    if (v) {
        if (!cJSON_IsString(v) || (strcmp(v->valuestring, "ko") && strcmp(v->valuestring, "en"))) {
            return false;
        }
        out->explain_korean = !strcmp(v->valuestring, "ko");
    }
    v = cJSON_GetObjectItemCaseSensitive(j, "speed");
    if (v) {
        if (!cJSON_IsString(v) || (strcmp(v->valuestring, "slow") && strcmp(v->valuestring, "normal"))) {
            return false;
        }
        out->slow = !strcmp(v->valuestring, "slow");
    }
    v = cJSON_GetObjectItemCaseSensitive(j, "minutes");
    if (v) {
        if (!cJSON_IsNumber(v) || (v->valueint != 3 && v->valueint != 5)) {
            return false;
        }
        out->minutes = (uint8_t)v->valueint;
    }
    return true;
}

/* ── Start and end ──────────────────────────────────────── */

static void reset_record(const lesson_cfg_t *cfg)
{
    L->cfg = *cfg;
    L->started_ms = L->ended_ms = 0;
    L->warned = L->extracting = false;
    L->topic[0] = L->next_topic[0] = '\0';
    L->n_corrections = L->n_pronunciation = 0;
    L->text_len = L->extracted_upto = 0;
    L->text[0] = '\0';
    L->last_speaker = -1;
    L->last_extract_ms = 0;
}

static bool busy_state(lesson_state_t s)
{
    return s == ST_WAITING || s == ST_STARTING || s == ST_ACTIVE || s == ST_SUMMARIZING;
}

/* Opens the lesson session: sets the time limit and starts live_voice */
static esp_err_t begin_session(void)
{
    live_voice_set_next_limits((uint32_t)L->cfg.minutes * 60000u, IDLE_MS);
    esp_err_t err = live_voice_start();
    if (err != ESP_OK) {
        live_voice_set_next_limits(0, 0);
        LOCK();
        L->state = ST_IDLE;
        UNLOCK();
        ESP_LOGW(TAG, "could not start the lesson session: %s", esp_err_to_name(err));
    }
    notify();
    return err;
}

esp_err_t lesson_start(const lesson_cfg_t *cfg)
{
    if (!L) {
        return ESP_ERR_INVALID_STATE;
    }
    LOCK();
    if (busy_state(L->state) || live_voice_active()) {
        UNLOCK();
        return ESP_ERR_INVALID_STATE;
    }
    reset_record(cfg);
    L->state = ST_STARTING;
    s_defaults = *cfg;
    UNLOCK();
    save_defaults();
    ESP_LOGI(TAG, "start: %s, %u min", COURSE_IDS[cfg->course], cfg->minutes);
    return begin_session();
}

esp_err_t lesson_start_after_session(const lesson_cfg_t *cfg)
{
    if (!L) {
        return ESP_ERR_INVALID_STATE;
    }
    LOCK();
    if (busy_state(L->state)) {
        UNLOCK();
        return ESP_ERR_INVALID_STATE;
    }
    reset_record(cfg);
    L->state = ST_WAITING;
    s_defaults = *cfg;
    UNLOCK();
    save_defaults();
    ESP_LOGI(TAG, "start after this conversation: %s, %u min", COURSE_IDS[cfg->course], cfg->minutes);
    notify();
    return ESP_OK;
}

void lesson_stop(void)
{
    if (L && (L->state == ST_ACTIVE || L->state == ST_STARTING)) {
        live_voice_stop();
    }
}

bool lesson_change_topic(void)
{
    if (!L || L->state != ST_ACTIVE) {
        return false;
    }
    return live_voice_instruction("The learner asked for a different topic. Briefly suggest a new topic that suits this course "
                                  "and ask an opening question about it, then continue the conversation.");
}

/* A lesson requested by voice: open it after the current conversation has fully ended (tool worker) */
static void begin_after_job(void *arg)
{
    for (int i = 0; i < 50 && live_voice_active(); i++) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    LOCK();
    bool go = L->state == ST_WAITING;
    if (go) {
        L->state = ST_STARTING;
    }
    UNLOCK();
    if (go) {
        begin_session();
    }
}

/* ── Tutor instructions ─────────────────────────────────── */

static const char *course_focus(lesson_course_t c)
{
    switch (c) {
    case LESSON_PRON:
        return "Course: pronunciation. Keep topics light and everyday. When the learner mispronounces a word, say the word clearly, "
               "describe the mouth or tongue position in one short sentence, and invite one more try, then move on.";
    case LESSON_BASIC:
        return "Course: basic conversation for a beginner. Use very simple words and short sentences. Topics: greetings, family, "
               "food, weather, shopping, hobbies, daily routine. Accept simple answers and correct only the most important mistake.";
    case LESSON_DAILY:
        return "Course: everyday English. Practice real situations as role-play (travel, restaurant, hotel, hospital, shopping, "
               "phone calls, small talk): set up the situation, play the other person, and keep it realistic.";
    case LESSON_BIZ:
        return "Course: business English. Talk about meetings, phone calls, negotiations, presentations and emails. "
               "Teach polite, professional phrasing and natural business expressions.";
    case LESSON_ADV:
    default:
        return "Course: advanced conversation. Discuss current events, opinions, culture and ideas in depth. Ask challenging "
               "follow-up questions, use natural idioms, and refine the learner's sentences so they sound native.";
    }
}

char *lesson_start_event(const char *voice)
{
    LOCK();
    lesson_cfg_t cfg = L->cfg;
    L->state = ST_ACTIVE;
    L->started_ms = now_ms();
    UNLOCK();
    notify();

    char *instructions = malloc(3072);
    cJSON *root = cJSON_CreateObject();
    char *text = NULL;
    if (!instructions || !root) {
        goto done;
    }
    snprintf(instructions, 3072,
             "You are a friendly, patient English conversation teacher talking with a Korean learner through a home speaker. "
             "This is free talking: start right away by greeting the learner in English and opening a topic that suits the course. "
             "Then keep a natural conversation going with short turns (one to three sentences) and one question at a time; let the learner talk more than you. "
             "When the learner makes a mistake, briefly say the more natural way to put it, one correction at a time, prioritizing mistakes "
             "that change the meaning, then continue the conversation. Do not correct every sentence. Praise good attempts. "
             "%s %s %s "
             "The lesson lasts about %u minutes. When you are told that time is almost up, wrap up warmly. "
             "Speak naturally without markdown or lists. Stay in the lesson; if the learner asks for something unrelated, answer briefly and return to English practice.",
             course_focus(cfg.course),
             cfg.explain_korean ? "If the learner seems stuck or asks, explain briefly in Korean, then return to English."
                                : "Use English only; if the learner is stuck, rephrase with simpler English.",
             cfg.slow ? "Speak slowly and clearly, with small pauses." : "Speak at a natural pace.", cfg.minutes);

    cJSON_AddStringToObject(root, "type", "session.start");
    cJSON *session = cJSON_AddObjectToObject(root, "session");
    cJSON_AddStringToObject(session, "model", APP_LIVE_MODEL_DEFAULT);
    cJSON *audio = cJSON_AddObjectToObject(session, "audio");
    cJSON *format = cJSON_AddObjectToObject(audio, "format");
    cJSON_AddStringToObject(format, "type", "audio/pcm");
    cJSON_AddNumberToObject(format, "rate", AUDIO_SAMPLE_RATE);
    cJSON *output = cJSON_AddObjectToObject(audio, "output");
    cJSON_AddStringToObject(output, "voice", voice && voice[0] ? voice : "marin");
    cJSON_AddStringToObject(session, "instructions", instructions);
    cJSON *delegation = cJSON_AddObjectToObject(session, "delegation");
    cJSON_AddStringToObject(delegation, "type", "responses");
    cJSON *backend = cJSON_AddObjectToObject(delegation, "responses");
    cJSON_AddStringToObject(backend, "model", APP_BACKEND_MODEL_DEFAULT);
    cJSON_AddStringToObject(backend, "instructions",
                            "You support an English conversation teacher. Answer the teacher's questions about English usage, "
                            "word meanings and pronunciation briefly and accurately. Do not change device settings.");
    cJSON_AddArrayToObject(backend, "tools");
    text = cJSON_PrintUnformatted(root);
done:
    cJSON_Delete(root);
    free(instructions);
    return text;
}

/* ── Collecting the transcript ──────────────────────────── */

static void append_locked(const char *s, size_t n)
{
    if (n >= TRANSCRIPT_MAX / 2) {
        return;
    }
    if (L->text_len + n + 1 > TRANSCRIPT_MAX) {
        /* Drop the first half (long lesson). If the not-yet-extracted part shifts too, adjust the extracted position */
        size_t drop = TRANSCRIPT_MAX / 2;
        memmove(L->text, L->text + drop, L->text_len - drop);
        L->text_len -= drop;
        L->extracted_upto = L->extracted_upto > drop ? L->extracted_upto - drop : 0;
    }
    memcpy(L->text + L->text_len, s, n);
    L->text_len += n;
    L->text[L->text_len] = '\0';
}

void lesson_on_transcript(bool from_user, const char *delta)
{
    if (!L || L->state != ST_ACTIVE || !delta) {
        return;
    }
    LOCK();
    int speaker = from_user ? 1 : 0;
    if (speaker != L->last_speaker) {
        const char *label = from_user ? "\nLearner: " : "\nTeacher: ";
        append_locked(label, strlen(label));
        L->last_speaker = speaker;
    }
    append_locked(delta, strlen(delta));
    UNLOCK();
}

/* ── Extracting corrected expressions (Responses API) ───── */

typedef struct {
    char *buf;
    size_t used;
} body_t;

static esp_err_t on_http(esp_http_client_event_t *evt)
{
    body_t *b = evt->user_data;
    if (evt->event_id == HTTP_EVENT_ON_DATA && b->used + evt->data_len < RESPONSE_MAX) {
        memcpy(b->buf + b->used, evt->data, evt->data_len);
        b->used += evt->data_len;
    }
    return ESP_OK;
}

static const char SCHEMA[] =
    "{\"type\":\"object\",\"properties\":{"
    "\"topic\":{\"type\":\"string\"},"
    "\"corrections\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{"
    "\"original\":{\"type\":\"string\"},\"better\":{\"type\":\"string\"},\"note\":{\"type\":\"string\"}},"
    "\"required\":[\"original\",\"better\",\"note\"],\"additionalProperties\":false}},"
    "\"pronunciation\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{"
    "\"word\":{\"type\":\"string\"},\"tip\":{\"type\":\"string\"}},"
    "\"required\":[\"word\",\"tip\"],\"additionalProperties\":false}},"
    "\"next_topic\":{\"type\":\"string\"}},"
    "\"required\":[\"topic\",\"corrections\",\"pronunciation\",\"next_topic\"],\"additionalProperties\":false}";

/* Finds output_text in the response JSON and returns the JSON inside it */
static cJSON *output_json(const char *body)
{
    cJSON *root = cJSON_Parse(body);
    cJSON *result = NULL;
    const cJSON *item;
    cJSON_ArrayForEach(item, cJSON_GetObjectItem(root, "output")) {
        const cJSON *part;
        cJSON_ArrayForEach(part, cJSON_GetObjectItem(item, "content")) {
            const cJSON *type = cJSON_GetObjectItem(part, "type");
            const cJSON *text = cJSON_GetObjectItem(part, "text");
            if (!result && cJSON_IsString(type) && !strcmp(type->valuestring, "output_text") && cJSON_IsString(text)) {
                result = cJSON_Parse(text->valuestring);
            }
        }
    }
    cJSON_Delete(root);
    return result;
}

static cJSON *call_responses(const char *system, const char *user)
{
    char key[256];
    size_t key_len = sizeof(key) - 1;
    if (secret_get(SECRET_OPENAI_KEY, key, &key_len) != ESP_OK || key_len == 0) {
        return NULL;
    }
    key[key_len] = '\0';
    char auth[300];
    snprintf(auth, sizeof(auth), "Bearer %s", key);
    memset(key, 0, sizeof(key));

    cJSON *req = cJSON_CreateObject();
    cJSON_AddStringToObject(req, "model", APP_BACKEND_MODEL_DEFAULT);
    cJSON_AddBoolToObject(req, "store", false);
    cJSON *input = cJSON_AddArrayToObject(req, "input");
    cJSON *sys = cJSON_CreateObject();
    cJSON_AddStringToObject(sys, "role", "system");
    cJSON_AddStringToObject(sys, "content", system);
    cJSON_AddItemToArray(input, sys);
    cJSON *usr = cJSON_CreateObject();
    cJSON_AddStringToObject(usr, "role", "user");
    cJSON_AddStringToObject(usr, "content", user);
    cJSON_AddItemToArray(input, usr);
    cJSON *fmt = cJSON_AddObjectToObject(cJSON_AddObjectToObject(req, "text"), "format");
    cJSON_AddStringToObject(fmt, "type", "json_schema");
    cJSON_AddStringToObject(fmt, "name", "lesson_notes");
    cJSON_AddBoolToObject(fmt, "strict", true);
    cJSON_AddItemToObject(fmt, "schema", cJSON_Parse(SCHEMA));
    char *payload = cJSON_PrintUnformatted(req);
    cJSON_Delete(req);

    body_t body = {.buf = heap_caps_malloc(RESPONSE_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)};
    cJSON *result = NULL;
    if (payload && body.buf) {
        const esp_http_client_config_t cfg = {
            .url = RESPONSES_URL,
            .method = HTTP_METHOD_POST,
            .crt_bundle_attach = esp_crt_bundle_attach,
            .timeout_ms = 30000,
            .buffer_size = 2048,
            .buffer_size_tx = 1024,
            .event_handler = on_http,
            .user_data = &body,
        };
        esp_http_client_handle_t client = esp_http_client_init(&cfg);
        if (client) {
            esp_http_client_set_header(client, "Authorization", auth);
            esp_http_client_set_header(client, "Content-Type", "application/json");
            esp_http_client_set_post_field(client, payload, strlen(payload));
            esp_err_t err = esp_http_client_perform(client);
            int status = esp_http_client_get_status_code(client);
            esp_http_client_cleanup(client);
            if (err == ESP_OK && status == 200) {
                body.buf[body.used] = '\0';
                result = output_json(body.buf);
            } else {
                ESP_LOGW(TAG, "notes request failed: %s, HTTP %d", esp_err_to_name(err), status);
            }
        }
    }
    memset(auth, 0, sizeof(auth));
    free(payload);
    free(body.buf);
    return result;
}

static void merge_notes(const cJSON *notes, bool final)
{
    const cJSON *topic = cJSON_GetObjectItem(notes, "topic");
    if (cJSON_IsString(topic) && topic->valuestring[0]) {
        copy_str(L->topic, sizeof(L->topic), topic->valuestring);
    }
    const cJSON *c;
    cJSON_ArrayForEach(c, cJSON_GetObjectItem(notes, "corrections")) {
        const cJSON *o = cJSON_GetObjectItem(c, "original"), *b = cJSON_GetObjectItem(c, "better"),
                    *n = cJSON_GetObjectItem(c, "note");
        if (!cJSON_IsString(o) || !cJSON_IsString(b) || !o->valuestring[0] || !b->valuestring[0] ||
            L->n_corrections >= MAX_CORRECTIONS) {
            continue;
        }
        bool dup = false;
        for (int i = 0; i < L->n_corrections && !dup; i++) {
            dup = !strcasecmp(L->corrections[i].original, o->valuestring) ||
                  !strcasecmp(L->corrections[i].better, b->valuestring);
        }
        if (!dup) {
            correction_t *dst = &L->corrections[L->n_corrections++];
            copy_str(dst->original, sizeof(dst->original), o->valuestring);
            copy_str(dst->better, sizeof(dst->better), b->valuestring);
            copy_str(dst->note, sizeof(dst->note), cJSON_IsString(n) ? n->valuestring : "");
        }
    }
    cJSON_ArrayForEach(c, cJSON_GetObjectItem(notes, "pronunciation")) {
        const cJSON *w = cJSON_GetObjectItem(c, "word"), *t = cJSON_GetObjectItem(c, "tip");
        if (!cJSON_IsString(w) || !w->valuestring[0] || L->n_pronunciation >= MAX_PRONUNCIATION) {
            continue;
        }
        bool dup = false;
        for (int i = 0; i < L->n_pronunciation && !dup; i++) {
            dup = !strcasecmp(L->pronunciation[i].word, w->valuestring);
        }
        if (!dup) {
            pronunciation_t *dst = &L->pronunciation[L->n_pronunciation++];
            copy_str(dst->word, sizeof(dst->word), w->valuestring);
            copy_str(dst->tip, sizeof(dst->tip), cJSON_IsString(t) ? t->valuestring : "");
        }
    }
    const cJSON *next = cJSON_GetObjectItem(notes, "next_topic");
    if (final && cJSON_IsString(next) && next->valuestring[0]) {
        copy_str(L->next_topic, sizeof(L->next_topic), next->valuestring);
    }
}

static void save_record(void)
{
    s_record_loaded = true;     /* a new summary takes priority over the old file */
    cJSON *j = lesson_json();
    char *text = cJSON_PrintUnformatted(j);
    cJSON_Delete(j);
    FILE *f = text ? fopen(LESSON_FILE, "w") : NULL;
    if (f) {
        fputs(text, f);
        fclose(f);
    }
    free(text);
}

/* Runs on the tool worker (final summary if arg != NULL) */
static void extract_job(void *arg)
{
    bool final = arg != NULL;
    LOCK();
    size_t upto = L->text_len;
    size_t from = final ? (upto > FINAL_WINDOW_MAX ? upto - FINAL_WINDOW_MAX : 0)
                        : (L->extracted_upto > WINDOW_OVERLAP ? L->extracted_upto - WINDOW_OVERLAP : 0);
    if (!final && upto - from > WINDOW_MAX) {
        from = upto - WINDOW_MAX;
    }
    size_t cap = (upto - from) + 2048;
    char *user = heap_caps_malloc(cap, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    lesson_cfg_t cfg = L->cfg;
    if (user) {
        int n = snprintf(user, cap, "Course: %s. Already noted (do not repeat):", COURSE_IDS[cfg.course]);
        for (int i = 0; i < L->n_corrections && n < (int)cap - 200; i++) {
            n += snprintf(user + n, cap - n, " [%s]", L->corrections[i].original);
        }
        n += snprintf(user + n, cap - n, "\nTranscript:\n");
        memcpy(user + n, L->text + from, upto - from);
        user[n + (upto - from)] = '\0';
    }
    UNLOCK();

    if (user) {
        char system[1200];
        snprintf(system, sizeof(system),
                 "You read part of a spoken English lesson between a Learner (Korean speaker) and a Teacher. The text comes from speech "
                 "recognition and may contain recognition errors; ignore those. Extract: corrections = phrases the Learner said that the "
                 "Teacher corrected or that clearly needed a more natural form (original = learner's words, better = natural version, "
                 "note = very short reason in %s); pronunciation = words the Teacher gave pronunciation advice on (tip in %s); "
                 "topic = the current conversation topic as a short phrase in Korean; next_topic = %s. Return at most 5 corrections and "
                 "3 pronunciation items, only new ones. Return empty arrays when there is nothing.",
                 cfg.explain_korean ? "Korean" : "English", cfg.explain_korean ? "Korean" : "English",
                 final ? "a short Korean suggestion for the next lesson topic" : "an empty string");
        cJSON *notes = call_responses(system, user);
        free(user);
        if (notes) {
            LOCK();
            merge_notes(notes, final);
            L->extracted_upto = upto > L->text_len ? L->text_len : upto;
            UNLOCK();
            cJSON_Delete(notes);
            notify();
        }
    }
    LOCK();
    L->extracting = false;
    if (final) {
        L->state = ST_DONE;
    }
    UNLOCK();
    if (final) {
        save_record();
        ESP_LOGI(TAG, "lesson summary ready");
        notify();
    }
}

void lesson_tick(void)
{
    if (!L || L->state != ST_ACTIVE) {
        return;
    }
    uint32_t now = now_ms();
    uint32_t length = (uint32_t)L->cfg.minutes * 60000u;
    if (!L->warned && now - L->started_ms + WRAP_UP_MS >= length) {
        L->warned = true;
        live_voice_instruction("About one minute is left in this lesson. Within your next turn or two, wrap up warmly: "
                               "mention one thing the learner did well and one thing to practice, then say goodbye.");
    }
    LOCK();
    bool due = !L->extracting && now - L->last_extract_ms >= EXTRACT_EVERY_MS &&
               L->text_len - L->extracted_upto >= EXTRACT_MIN_NEW;
    if (due) {
        L->extracting = true;
        L->last_extract_ms = now;
    }
    UNLOCK();
    if (due && !assistant_queue_work(extract_job, NULL)) {
        LOCK();
        L->extracting = false;
        UNLOCK();
    }
}

void lesson_on_session_end(void)
{
    if (!L) {
        return;
    }
    LOCK();
    lesson_state_t st = L->state;
    bool summarize = false;
    if (st == ST_WAITING) {
        UNLOCK();
        assistant_queue_work(begin_after_job, NULL);    /* open the lesson after the conversation that just ended */
        return;
    }
    if (st == ST_STARTING) {
        L->state = ST_IDLE;     /* the lesson session didn't open (connection failure, etc.) */
    } else if (st == ST_ACTIVE) {
        L->ended_ms = now_ms();
        bool spoke = strstr(L->text, "Learner:") != NULL;
        L->state = spoke ? ST_SUMMARIZING : ST_IDLE;
        summarize = spoke;
    }
    UNLOCK();
    if (summarize && !assistant_queue_work(extract_job, (void *)1)) {
        LOCK();
        L->state = ST_DONE;
        UNLOCK();
        save_record();
    }
    notify();
}

bool lesson_wants_session(void)
{
    return L && L->state == ST_STARTING;
}

bool lesson_busy(void)
{
    return L && busy_state(L->state);
}

/* ── State ──────────────────────────────────────────────── */

cJSON *lesson_json(void)
{
    cJSON *j = cJSON_CreateObject();
    if (!L) {
        cJSON_AddStringToObject(j, "state", "idle");
        return j;
    }
    if (!s_record_loaded) {
        s_record_loaded = true;
        LOCK();
        if (L->state == ST_IDLE) {
            load_record();
        }
        UNLOCK();
    }
    LOCK();
    cJSON_AddStringToObject(j, "state", STATE_NAMES[L->state]);
    cJSON_AddStringToObject(j, "course", COURSE_IDS[L->cfg.course]);
    cJSON_AddStringToObject(j, "explain", L->cfg.explain_korean ? "ko" : "en");
    cJSON_AddStringToObject(j, "speed", L->cfg.slow ? "slow" : "normal");
    cJSON_AddNumberToObject(j, "minutes", L->cfg.minutes);
    if (L->started_ms) {
        uint32_t end = L->state == ST_ACTIVE ? now_ms() : (L->ended_ms ? L->ended_ms : L->started_ms);
        uint32_t elapsed = (end - L->started_ms) / 1000;
        uint32_t length = (uint32_t)L->cfg.minutes * 60;
        cJSON_AddNumberToObject(j, "elapsed_s", elapsed);
        cJSON_AddNumberToObject(j, "remaining_s", elapsed >= length ? 0 : length - elapsed);
    }
    cJSON_AddStringToObject(j, "topic", L->topic);
    cJSON *arr = cJSON_AddArrayToObject(j, "corrections");
    for (int i = 0; i < L->n_corrections; i++) {
        cJSON *o = cJSON_CreateObject();
        cJSON_AddStringToObject(o, "original", L->corrections[i].original);
        cJSON_AddStringToObject(o, "better", L->corrections[i].better);
        cJSON_AddStringToObject(o, "note", L->corrections[i].note);
        cJSON_AddItemToArray(arr, o);
    }
    arr = cJSON_AddArrayToObject(j, "pronunciation");
    for (int i = 0; i < L->n_pronunciation; i++) {
        cJSON *o = cJSON_CreateObject();
        cJSON_AddStringToObject(o, "word", L->pronunciation[i].word);
        cJSON_AddStringToObject(o, "tip", L->pronunciation[i].tip);
        cJSON_AddItemToArray(arr, o);
    }
    cJSON_AddStringToObject(j, "next_topic", L->next_topic);
    UNLOCK();
    return j;
}

/* Loads the last lesson summary (so the app can see it even after a reboot) */
static void load_record(void)
{
    FILE *f = fopen(LESSON_FILE, "r");
    if (!f) {
        return;
    }
    char *buf = heap_caps_malloc(8192, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    size_t n = buf ? fread(buf, 1, 8191, f) : 0;
    fclose(f);
    if (!buf) {
        return;
    }
    buf[n] = '\0';
    cJSON *j = cJSON_Parse(buf);
    free(buf);
    lesson_cfg_t cfg;
    if (j && lesson_parse_cfg(j, &cfg)) {
        reset_record(&cfg);
        merge_notes(j, true);
        const cJSON *el = cJSON_GetObjectItem(j, "elapsed_s");
        if (cJSON_IsNumber(el)) {
            /* Times are relative to boot, so only the duration is restored */
            L->started_ms = 1;
            L->ended_ms = 1 + (uint32_t)el->valueint * 1000;
        }
        L->state = ST_DONE;
    }
    cJSON_Delete(j);
}

esp_err_t lesson_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    L = heap_caps_calloc(1, sizeof(*L), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    char *text = heap_caps_malloc(TRANSCRIPT_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_lock || !L || !text) {
        free(L);
        free(text);
        L = NULL;
        return ESP_ERR_NO_MEM;
    }
    L->text = text;
    load_defaults();
    reset_record(&s_defaults);
    return ESP_OK;
}
