/**
 * @file lesson.h
 * @brief Korean tutor: pick a course and start free talking with the speaker in Korean (2026-10-03 user request, app design "Korean Tutor")
 *
 * - A lesson session is the same live_voice session as a normal conversation, but starts with tutor instructions (course, explanation language, speed, length).
 * - The tutor corrects you aloud while talking. About every 45 seconds the speaker collects the transcript and sends it separately to OpenAI (Responses API)
 *   to extract "corrected expressions, pronunciation, topic" and sends them to the app (WS `lesson`). When the lesson ends, it extracts a full summary once more and saves it.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LESSON_PRON,    /* pronunciation correction */
    LESSON_BASIC,   /* basic Korean conversation */
    LESSON_DAILY,   /* everyday Korean conversation */
    LESSON_BIZ,     /* business Korean conversation */
    LESSON_ADV,     /* advanced Korean conversation */
    LESSON_COURSE_COUNT,
} lesson_course_t;

typedef struct {
    lesson_course_t course;
    bool explain_english;   /* true: explain in English when stuck, false: Korean only */
    bool slow;              /* slowly and clearly */
    uint8_t minutes;        /* 3, 5 (max 5 minutes because of cost, 2026-10-04) */
} lesson_cfg_t;

esp_err_t lesson_init(void);

/** API body or tool arguments → settings. Missing keys keep the last value used. false if the format is wrong */
bool lesson_parse_cfg(const cJSON *j, lesson_cfg_t *out);

/** App: start a lesson now. ESP_ERR_INVALID_STATE during a conversation or while the BLE window is open */
esp_err_t lesson_start(const lesson_cfg_t *cfg);
/** Voice ("Let's study Korean"): start the lesson when the current conversation ends */
esp_err_t lesson_start_after_session(const lesson_cfg_t *cfg);
/** End the lesson (the summary is made after the session ends) */
void      lesson_stop(void);
/** Switch to another topic. false if no lesson is running */
bool      lesson_change_topic(void);
/** Current (or last) lesson state and summary. Caller must cJSON_Delete */
cJSON    *lesson_json(void);

/** true while a lesson is waiting, running, or being summarized (so auto-read doesn't cut in) */
bool      lesson_busy(void);

/* ── Called by assistant from the live_voice handlers ── */
bool  lesson_wants_session(void);
char *lesson_start_event(const char *voice);
void  lesson_on_transcript(bool from_user, const char *delta);
void  lesson_tick(void);
void  lesson_on_session_end(void);

#ifdef __cplusplus
}
#endif
