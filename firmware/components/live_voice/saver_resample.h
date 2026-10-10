/**
 * @file saver_resample.h
 * @brief Simple linear-interpolation resampler, 24kHz -> 16kHz (docs/design-voice-saver-mode.md 11.6/5.5)
 *
 * Fits gpt-4o-mini-tts pcm output (24kHz) to the current voice playback queue (16kHz). Instead of the
 * esp_audio_effects resampler it deliberately uses simple linear interpolation (to keep the port small; stage 1 TODO: replace if quality falls short).
 * It keeps the phase and previous sample between streaming calls, so output stays continuous whatever size the HTTP chunks are.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double  next_in_pos;    /* input position, relative to the whole stream, needed by the next output sample (in samples) */
    double  consumed_in;    /* input samples consumed from this stream so far (= absolute position of this call's in[0]) */
    int16_t prev_last;      /* last input sample of the previous call (for boundary interpolation) */
    bool    have_prev;
} saver_resample_t;

void saver_resample_reset(saver_resample_t *r);

/**
 * Fills out at 16kHz from in (count_in samples, 24kHz), up to out_capacity. out holds as many samples as returned.
 * Stays continuous across multiple calls (with the same r).
 */
size_t saver_resample_24to16(saver_resample_t *r, const int16_t *in, size_t count_in, int16_t *out,
                              size_t out_capacity);

bool saver_resample_selftest(void);

#ifdef __cplusplus
}
#endif
