/**
 * @file saver_voice.h
 * @brief Private internal contract between live_voice.c and saver_voice.c (docs/design-voice-saver-mode.md 11.5, 11.6)
 *
 * Visible only inside components/live_voice (PRIV_INCLUDE_DIRS "." in CMakeLists). Other components don't know
 * this file. live_voice.c holds the shared session state (busy, state, ready, status, generation, stop request), and saver_voice.c
 * touches it only through these small pass-through functions. The existing static variables of the Live (openai.live) path stay as they are.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "app_events.h"
#include "cJSON.h"
#include "esp_err.h"
#include "live_voice.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── implemented by live_voice.c, called by saver_voice.c ─────────────── */

void     voice_shared_set_state(voice_state_t state);
void     voice_shared_set_ready(bool ready);
/** Fixed strings only (never content or keys) */
void     voice_shared_set_status(const char *text);
bool     voice_shared_stopping(void);
/** Common session wrap-up: ready=false, (status="Ready" unless failed), busy=false, VOICE_IDLE */
void     voice_shared_end(bool had_error);
/** Releases the internal RAM spot (about 12KB) the Live engine reserved for the conversation, and reserves it again afterward */
void     voice_shared_reserve_release(void);
void     voice_shared_reserve_take(void);
/** Registered handlers (set by assistant_init via live_voice_set_handlers). Fixed before the session starts */
const live_voice_handlers_t *voice_shared_handlers(void);
/** Takes the values set by live_voice_set_next_limits() once (if 0, applying the default is up to the caller) */
void     voice_shared_take_next_limits(uint32_t *max_ms, uint32_t *idle_ms);

/* ── implemented by saver_voice.c, called by live_voice.c ─────────────── */

/** Once at boot: create the session task (stack in PSRAM) */
esp_err_t saver_voice_init(void);
/** Task entry point used when live_voice_start() wakes the session task (ulTaskNotifyTake loop) */
void      saver_voice_task_entry(void *arg);
/** Key2 short press: stop current playback only and go back to listening. Does nothing without a Saver session */
void      saver_voice_barge_in(void);
/**
 * Text passed by live_voice_text() while a saver session is active (currently reminder sentences only, Section 11.7). Synthesized
 * as is without the AI, then back to listening. ESP_ERR_INVALID_STATE unless live_voice_ready() is true
 */
esp_err_t saver_voice_text(const char *text);

/**
 * Maps the voice name from assistant settings to a Gemini TTS/Live prebuilt voice name (same name if it exists,
 * otherwise "Kore"). Used by both saver_voice.c (Saver mode synthesis) and gemini_live.c (stage 3, speechConfig).
 */
const char *gemini_tts_voice(const char *voice);

#ifdef __cplusplus
}
#endif
