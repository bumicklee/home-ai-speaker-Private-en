/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/**
 * @file audio_core.h
 * @brief Full-duplex I2S, echo cancellation (AEC), voice playback queue, tones (design document Section 2.7)
 *
 * Phase 1 runs on the 16kHz configuration proven on real hardware (the existing firmware).
 * The 48kHz mixer, resampler and music ducking are added in Phase 3, after the Phase 0 measurement (Q7).
 *
 * Mic path: ES7210 4 channels → (ref=ch0, mic=ch1) → AEC → mic processing hook → sinks
 * Playback path: voice queue + alerts (boot sound, tones) + music (ducked) → volume → ES8311
 *
 * The music channel takes mono at the output rate (AUDIO_SAMPLE_RATE). The producer (media_radio) does the rate conversion.
 * When the output rate moves to 48kHz (Q7), the music side just follows this constant.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AUDIO_SAMPLE_RATE   16000
#define AUDIO_FRAME_SAMPLES 320     /* 20ms */

/** Receives echo-cancelled 16kHz mono mic samples. Called from the mic task, so it must not block */
typedef void (*audio_mic_sink_t)(const int16_t *samples, size_t count);

/** Hook that modifies the AEC output (clean) in place (auto gain, calibration measurement). raw is the mic signal before AEC */
typedef void (*audio_mic_processor_t)(int16_t *clean, const int16_t *raw, size_t count);

/**
 * Initializes in this order: I2S TX/RX → codecs → saved volume and mic gain → start outputting silence
 * → enable amplifier after 50ms → start the mic task.
 */
esp_err_t audio_core_init(void);

/** Decodes and plays the startup.mp3 embedded in the firmware (in the background) */
esp_err_t audio_core_play_startup(void);
/** "The AI speaker is ready" announcement (ready.mp3, recorded in Korean). If other sound is playing, waits until it ends */
esp_err_t audio_core_play_ready(void);

esp_err_t audio_core_add_mic_sink(audio_mic_sink_t sink);

/** Wake word input. AEC (VOIP mode) is call-grade processing that can alter wake word features, so the raw mic is used when the speaker is quiet */
typedef enum {
    AUDIO_WAKE_SRC_AUTO = 0,    /* default: raw when the speaker reference is quiet, AEC output when it's playing */
    AUDIO_WAKE_SRC_AEC,         /* always AEC output (old behavior) */
    AUDIO_WAKE_SRC_RAW,         /* always the raw mic (for testing) */
} audio_wake_src_t;

/** Wake-word-only sink (one). Receives audio chosen by the rule above */
void             audio_core_set_wake_sink(audio_mic_sink_t sink);
void             audio_core_set_wake_source(audio_wake_src_t src);
audio_wake_src_t audio_core_get_wake_source(void);
void      audio_core_set_mic_processor(audio_mic_processor_t processor);

/* Voice (conversation reply) playback queue. 16kHz mono */
bool audio_core_voice_enqueue(const int16_t *samples, size_t count);
void audio_core_voice_clear(void);

/* Music channel (MUSIC). Ring buffer of about 1 s */

/** Writes music samples. If the buffer is full, waits up to timeout_ms (throttles the download). Returns the count written */
size_t audio_core_music_write(const int16_t *samples, size_t count, uint32_t timeout_ms);
/** Discards buffered music (stop, station change) */
void   audio_core_music_flush(void);
/** Lower music during conversation: down by duck_db over 200ms, release over 500ms (Section 2.5) */
void   audio_core_music_duck(bool duck);
/** Amount buffered in the music buffer (ms) */
uint32_t audio_core_music_buffered_ms(void);
/**
 * Suspends or resumes echo cancellation (AEC) (about 91KB of internal RAM). Used while the BLE window is open.
 * While suspended, no mic audio reaches the wake word or conversation. Waits up to timeout_ms for the mic task to act.
 */
esp_err_t audio_core_aec_suspend(bool suspend, uint32_t timeout_ms);
bool      audio_core_aec_suspended(void);
/** Cumulative count of dropouts from the music buffer running empty during playback (diagnostic) */
unsigned audio_core_music_underruns(void);

/** Short ready tone (440Hz, 0.3 s) */
void audio_core_tone(void);
/** Message alert (two-tone chime, about 0.35 s) */
void audio_core_chime(void);

/** true if sound is going out the speaker or did within the last 0.5 s */
bool     audio_core_is_playing(void);
/** The assistant's voice is playing (radio music excluded) */
bool     audio_core_voice_playing(void);
/** Counter that increments whenever sound goes out (lets calibration check "did the prompt play") */
unsigned audio_core_output_generation(void);

/** Volume 0–80. Applies it to the codec and saves it to NVS */
esp_err_t audio_core_set_volume(int volume);
int       audio_core_get_volume(void);
/** Hardware mic gain (dB). Applies only (the caller saves it) */
esp_err_t audio_core_set_mic_gain(int db);

#ifdef __cplusplus
}
#endif
