/**
 * @file saver_endpoint.h
 * @brief Saver mode VAD end-of-speech detection (pure logic, docs/design-voice-saver-mode.md 11.6/5.1)
 *
 * The esp-sr VAD (esp_vad.h) only returns "speech or silence" per frame (20ms). This file takes those results and
 * decides "speech just started / keep listening / ended after 0.7 s of silence / ended at 30 s". It does not depend on
 * esp-sr or FreeRTOS, so it compiles and tests directly on the host (Section E self-test).
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SAVER_EP_SILENCE_END_MS   700    /* 0.7 s of silence ends speech (Section 11.6) */
#define SAVER_EP_MAX_UTTERANCE_MS 30000  /* speech 30 s max */

typedef struct {
    bool     in_speech;
    uint32_t speech_started_ms;
    uint32_t last_speech_ms;
} saver_endpoint_t;

typedef enum {
    SAVER_EP_CONTINUE,      /* continue (listening, or speech hasn't started yet) */
    SAVER_EP_END_SILENCE,   /* 0.7 s of quiet → end of speech */
    SAVER_EP_END_MAXLEN,    /* ended at 30 s (upload only this much) */
} saver_endpoint_result_t;

void saver_endpoint_reset(saver_endpoint_t *ep);

/**
 * Feeds the VAD result of one frame (usually 20ms).
 * @param started_out  If not NULL, set true when speech "just started" on this call (used as the signal to commit the pre-roll)
 */
saver_endpoint_result_t saver_endpoint_feed(saver_endpoint_t *ep, bool frame_is_speech, uint32_t now_ms,
                                            bool *started_out);

/** true on pass. Logs any failed condition (dev console selftest) */
bool saver_endpoint_selftest(void);

#ifdef __cplusplus
}
#endif
