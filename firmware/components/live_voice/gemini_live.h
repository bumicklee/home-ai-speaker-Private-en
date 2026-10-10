/**
 * @file gemini_live.h
 * @brief Private internal contract between live_voice.c ↔ gemini_live.c (docs/design-voice-saver-mode.md stage 3: Gemini Live)
 *
 * Visible only inside components/live_voice (PRIV_INCLUDE_DIRS "." in CMakeLists). live_voice.c holds the shared session
 * state (busy, status, ready, generation, stop request), and gemini_live.c, like saver_voice.c, touches that state
 * only through the voice_shared_* accessor functions in saver_voice.h (reused as is, nothing new). Being live, it
 * uses esp_websocket_client and has its own session task (same structure as gpt-live-1: that task creates another
 * task with an internal RAM stack, so the ws_stack_reserve/release trick is needed;
 * shared via voice_shared_reserve_release/take, only one WebSocket at a time).
 */
#pragma once

#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Once at boot: create the session task (stack in PSRAM; the esp_websocket_client internal task uses internal RAM) */
esp_err_t gemini_live_init(void);
/** Task entry point that live_voice_start() uses to wake the session task (ulTaskNotifyTake loop) */
void      gemini_live_task_entry(void *arg);
/** Is a Gemini Live session listening right now (after setupComplete, before it ends); used to route live_voice_text/instruction */
bool      gemini_live_active(void);
/**
 * Text the device sends: reminder sentences, Telegram auto-read, mic calibration guidance and so on. Sent as clientContent (role user,
 * turnComplete true) (gemini_live_proto.h, request 5: there is no message for appending to the instructions).
 * ESP_ERR_INVALID_STATE if there is no session or it is not ready yet.
 */
esp_err_t gemini_live_text(const char *text);

#ifdef __cplusplus
}
#endif
