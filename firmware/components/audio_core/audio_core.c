/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * Audio core. Moves speaker_task, mic_task and the playback queue, which lived in main.c of
 * the existing firmware (waveshare-ai-speaker-assistant), into a module. Proven values are kept as is:
 * 16kHz, two 32-bit slots, DMA block = 20ms (320 frames), AEC(16000, 4, 1, VOIP_HIGH_PERF),
 * playback prefill 160ms, capacity 15 s, final partial frame flushed after 240ms.
 */
#include "audio_core.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include "app_config.h"
#include "app_events.h"
#include "board.h"
#include "board_config.h"
#include "driver/i2s_std.h"
#include "esp_aec.h"
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec_default.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "settings.h"

static const char *TAG = "AUDIO";

#define MAX_SINKS          4
/* 15 s (about 480KB of PSRAM). Gemini Live sends long replies all at once, several times faster than real time,
 * so the 3.2 s queue overflowed and "Speaker backlog" cut the conversation (Chapter 18, Failure D) */
#define PLAYBACK_FRAMES    750
#define PLAYBACK_PREFILL   8        /* 160ms */
#define PLAYBACK_WAIT_MS   160
#define PARTIAL_FLUSH_MS   240
#define TONE_FRAMES        15       /* 0.3 s */

typedef struct {
    int16_t samples[AUDIO_FRAME_SAMPLES];
} audio_frame_t;

static i2s_chan_handle_t s_tx, s_rx;

/* Playback */
static QueueHandle_t s_playback;
static SemaphoreHandle_t s_playback_lock;
static audio_frame_t s_partial;
static size_t s_partial_samples;
static atomic_uint s_playback_epoch, s_last_enqueue_ms, s_last_signal_ms, s_generation;
/* Last time the assistant's voice actually went out audibly. The server keeps sending silent audio chunks after speech ends (2026-10-04) */
static atomic_uint s_voice_signal_ms;
#define VOICE_AUDIBLE_PEAK 200
#define VOICE_PLAYING_HOLD_MS 600
static atomic_int s_tone_frames;
static atomic_int s_volume;

/* Alert clip (boot sound). startup_sound.c owns the clip memory */
static const int16_t *volatile s_clip;
static volatile size_t s_clip_len, s_clip_pos;

/* Music */
/* Internet radio arrives at an uneven rate. A 1 s buffer caused dropouts, so 4 s (128KB of PSRAM, real board 2026-10-03) */
#define MUSIC_BUFFER_MS    4000
#define MUSIC_PREFILL_MS   750      /* after running empty, collect this much before playing again */
#define DUCK_DOWN_FRAMES   10       /* 200ms */
#define DUCK_UP_FRAMES     25       /* 500ms */
#define MUSIC_BUFFER_BYTES (AUDIO_SAMPLE_RATE * MUSIC_BUFFER_MS / 1000 * sizeof(int16_t))
static StreamBufferHandle_t s_music;
static atomic_bool s_music_flush, s_duck;
static atomic_uint s_music_underruns;   /* times playback cut out because the buffer ran empty (diagnostic) */
static atomic_int s_duck_db = 20;

/* Mic */
static audio_mic_sink_t s_sinks[MAX_SINKS];
static atomic_int s_sink_count;
static _Atomic(audio_mic_processor_t) s_processor;
static _Atomic(audio_mic_sink_t) s_wake_sink;
/*
 * Suspending AEC (BLE window): AEC uses about 91KB of internal RAM, and bringing up the BLE controller after a long uptime
 * ran out of internal RAM (real board 2026-10-03: BLE_INIT Malloc failed, nimble init ESP_ERR_NO_MEM).
 * The request is s_aec_want_off; the state the mic task actually applied is s_aec_off.
 */
static atomic_bool s_aec_want_off, s_aec_off;
static atomic_int s_wake_src = AUDIO_WAKE_SRC_AUTO;
#define REF_ACTIVE      300     /* reference (ch0) amplitude above this means the speaker is playing (about 20 when quiet) */
#define REF_HANGOVER_MS 500     /* keep using AEC output while reverb lingers after sound stops */

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

/* ── Public API ───────────────────────────────────────────── */

esp_err_t audio_core_add_mic_sink(audio_mic_sink_t sink)
{
    int n = atomic_load(&s_sink_count);
    if (n >= MAX_SINKS) {
        return ESP_ERR_NO_MEM;
    }
    s_sinks[n] = sink;
    atomic_store(&s_sink_count, n + 1);     /* write the value first, then bump the count */
    return ESP_OK;
}

void audio_core_set_wake_sink(audio_mic_sink_t sink)
{
    atomic_store(&s_wake_sink, sink);
}

void audio_core_set_wake_source(audio_wake_src_t src)
{
    atomic_store(&s_wake_src, src);
}

audio_wake_src_t audio_core_get_wake_source(void)
{
    return (audio_wake_src_t)atomic_load(&s_wake_src);
}

void audio_core_set_mic_processor(audio_mic_processor_t processor)
{
    atomic_store(&s_processor, processor);
}

void audio_core_tone(void)
{
    atomic_store(&s_tone_frames, TONE_FRAMES);
}

bool audio_core_is_playing(void)
{
    return uxQueueMessagesWaiting(s_playback) > 0 || s_clip ||
           now_ms() - atomic_load(&s_last_signal_ms) < 500;
}

bool audio_core_voice_playing(void)
{
    /* Assistant voice only, not music (radio). Even with an empty queue, count as speaking while the last chunk plays out (about 0.3 s) */
    /* Silent chunks piling up in the queue don't count as "speaking". A short pause between sentences (up to 0.6 s) does */
    return now_ms() - atomic_load(&s_voice_signal_ms) < VOICE_PLAYING_HOLD_MS;
}

unsigned audio_core_output_generation(void)
{
    return atomic_load(&s_generation);
}

void audio_core_voice_clear(void)
{
    xSemaphoreTake(s_playback_lock, portMAX_DELAY);
    xQueueReset(s_playback);
    s_partial_samples = 0;
    atomic_fetch_add(&s_playback_epoch, 1);
    xSemaphoreGive(s_playback_lock);
}

bool audio_core_voice_enqueue(const int16_t *samples, size_t count)
{
    bool ok = true;
    xSemaphoreTake(s_playback_lock, portMAX_DELAY);
    atomic_store(&s_last_enqueue_ms, now_ms());
    while (count) {
        size_t take = AUDIO_FRAME_SAMPLES - s_partial_samples;
        if (take > count) {
            take = count;
        }
        memcpy(s_partial.samples + s_partial_samples, samples, take * sizeof(int16_t));
        s_partial_samples += take;
        samples += take;
        count -= take;
        if (s_partial_samples == AUDIO_FRAME_SAMPLES) {
            s_partial_samples = 0;
            if (xQueueSend(s_playback, &s_partial, pdMS_TO_TICKS(30)) != pdTRUE) {
                ok = false;     /* backed up more than 15 s */
                break;
            }
        }
    }
    xSemaphoreGive(s_playback_lock);
    return ok;
}

esp_err_t audio_core_set_volume(int volume)
{
    if (volume < 0 || volume > APP_VOLUME_MAX) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_err_t err = board_codec_set_volume(volume);
    if (err != ESP_OK) {
        return err;
    }
    atomic_store(&s_volume, volume);
    settings_audio_t a;
    settings_get_audio(&a);
    a.volume = volume;
    err = settings_set_audio(&a);
    const app_setting_t key = APP_SETTING_VOLUME;
    app_events_post(APP_EVT_SETTINGS_CHANGED, &key, sizeof(key), 0);
    return err;
}

int audio_core_get_volume(void)
{
    return atomic_load(&s_volume);
}

esp_err_t audio_core_set_mic_gain(int db)
{
    return board_codec_set_mic_gain((float)db);
}

size_t audio_core_music_write(const int16_t *samples, size_t count, uint32_t timeout_ms)
{
    if (!s_music || atomic_load(&s_music_flush)) {
        return 0;
    }
    return xStreamBufferSend(s_music, samples, count * sizeof(int16_t), pdMS_TO_TICKS(timeout_ms)) / sizeof(int16_t);
}

void audio_core_music_flush(void)
{
    /* The reader (playback task) empties the buffer. A stream buffer can't be reset while the writer is waiting on it */
    atomic_store(&s_music_flush, true);
}

void audio_core_music_duck(bool duck)
{
    if (duck) {
        settings_audio_t a;
        settings_get_audio(&a);     /* pick up the ducking depth changed in the app every time */
        atomic_store(&s_duck_db, a.duck_db);
    }
    atomic_store(&s_duck, duck);
}

esp_err_t audio_core_aec_suspend(bool suspend, uint32_t timeout_ms)
{
    atomic_store(&s_aec_want_off, suspend);
    for (uint32_t waited = 0; atomic_load(&s_aec_off) != suspend; waited += 10) {
        if (waited >= timeout_ms) {
            return ESP_ERR_TIMEOUT;
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    return ESP_OK;
}

bool audio_core_aec_suspended(void)
{
    return atomic_load(&s_aec_want_off) || atomic_load(&s_aec_off);
}

unsigned audio_core_music_underruns(void)
{
    return atomic_load(&s_music_underruns);
}

uint32_t audio_core_music_buffered_ms(void)
{
    return s_music ? xStreamBufferBytesAvailable(s_music) / sizeof(int16_t) * 1000 / AUDIO_SAMPLE_RATE : 0;
}

/* Read one music frame, apply gain and add it to frame */
/* When music resumes after a break (buffer empty, channel change), ramp it up over 10ms. An abrupt start makes a "click" */
#define MUSIC_FADE_IN_SAMPLES (AUDIO_SAMPLE_RATE / 100)

static void mix_music(audio_frame_t *frame, float *gain, bool *primed)
{
    static int16_t music[AUDIO_FRAME_SAMPLES];
    static float fade = 0.0f;   /* fade-in on restart (0 → 1) */
    if (atomic_load(&s_music_flush)) {
        while (xStreamBufferReceive(s_music, music, sizeof(music), 0) > 0) {
        }
        *primed = false;
        fade = 0.0f;
        atomic_store(&s_music_flush, false);
        return;
    }
    size_t avail = xStreamBufferBytesAvailable(s_music);
    if (!*primed) {
        if (avail < AUDIO_SAMPLE_RATE * MUSIC_PREFILL_MS / 1000 * sizeof(int16_t)) {
            return;     /* buffering: mix nothing in (silence) */
        }
        *primed = true;
        fade = 0.0f;
    }
    size_t got = xStreamBufferReceive(s_music, music, sizeof(music), 0) / sizeof(int16_t);
    bool underrun = got < AUDIO_FRAME_SAMPLES;
    if (underrun) {
        *primed = false;    /* ran short: collect again */
        atomic_fetch_add(&s_music_underruns, 1);
    }

    /* Ducking: move toward the target gain a little each frame */
    int duck_db = atomic_load(&s_duck_db);
    float target = atomic_load(&s_duck) ? powf(10.0f, -duck_db / 20.0f) : 1.0f;
    float step = (1.0f - powf(10.0f, -duck_db / 20.0f)) / (target < *gain ? DUCK_DOWN_FRAMES : DUCK_UP_FRAMES);
    float g0 = *gain;
    if (*gain > target) {
        *gain = fmaxf(target, *gain - step);
    } else if (*gain < target) {
        *gain = fminf(target, *gain + step);
    }
    /* Change the gain a little per sample within the frame. Changing it all at once at frame boundaries makes a step every 20ms
     * and caused "crackling" while ducking (Chapter 14, Bug 6) */
    float dg = (*gain - g0) / AUDIO_FRAME_SAMPLES;
    for (size_t i = 0; i < got; i++) {
        float g = g0 + dg * (float)(i + 1);
        if (fade < 1.0f) {
            fade = fminf(1.0f, fade + 1.0f / MUSIC_FADE_IN_SAMPLES);
            g *= fade;
        }
        if (underrun) {
            g *= (float)(got - i) / (float)got;     /* data ran short: scale the remaining piece down to 0 (prevents the "click") */
        }
        int v = frame->samples[i] + (int)(music[i] * g);
        frame->samples[i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
    }
}

/* Alert chime: 660Hz → 880Hz, 150ms each, with a soft decay. Built once on first call */
#define CHIME_NOTE_MS 150
static int16_t *s_chime;
static size_t s_chime_len;

void audio_core_play_clip(const int16_t *pcm, size_t samples);

void audio_core_chime(void)
{
    if (!s_chime) {
        size_t note = AUDIO_SAMPLE_RATE * CHIME_NOTE_MS / 1000;
        int16_t *buf = heap_caps_malloc(note * 2 * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        if (!buf) {
            return;
        }
        const float freqs[2] = {660.0f, 880.0f};
        for (int n = 0; n < 2; n++) {
            for (size_t i = 0; i < note; i++) {
                float env = 1.0f - (float)i / note;     /* decay */
                buf[n * note + i] = (int16_t)(2200 * env * sinf(2 * 3.14159265f * freqs[n] * i / AUDIO_SAMPLE_RATE));
            }
        }
        s_chime_len = note * 2;
        s_chime = buf;
    }
    audio_core_play_clip(s_chime, s_chime_len);
}

/* Called from startup_sound.c */
void audio_core_play_clip(const int16_t *pcm, size_t samples)
{
    s_clip = NULL;
    s_clip_pos = 0;
    s_clip_len = samples;
    s_clip = pcm;
}

/* ── Playback task ────────────────────────────────────────── */

static void flush_partial_if_stale(uint32_t now)
{
    /* Pad the last short frame with zeros and send it instead of holding it (so the last syllable isn't cut off) */
    if (xSemaphoreTake(s_playback_lock, 0) != pdTRUE) {
        return;
    }
    if (s_partial_samples && (int32_t)(now - atomic_load(&s_last_enqueue_ms)) >= PARTIAL_FLUSH_MS) {
        memset(s_partial.samples + s_partial_samples, 0,
               (AUDIO_FRAME_SAMPLES - s_partial_samples) * sizeof(int16_t));
        if (xQueueSend(s_playback, &s_partial, 0) == pdTRUE) {
            s_partial_samples = 0;
        }
    }
    xSemaphoreGive(s_playback_lock);
}

static void speaker_task(void *arg)
{
    audio_frame_t frame;
    static int32_t stereo[AUDIO_FRAME_SAMPLES * 2];
    unsigned phase = 0, epoch = 0;
    uint32_t first_wait = 0;
    bool playing = false;
    float music_gain = 1.0f;
    bool music_primed = false;

    for (;;) {
        uint32_t now = now_ms();
        unsigned current_epoch = atomic_load(&s_playback_epoch);
        if (epoch != current_epoch) {
            epoch = current_epoch;
            playing = false;
            first_wait = 0;
        }
        flush_partial_if_stale(now);
        memset(&frame, 0, sizeof(frame));

        if (atomic_load(&s_tone_frames) > 0) {
            for (int i = 0; i < AUDIO_FRAME_SAMPLES; i++) {
                frame.samples[i] = (int16_t)(1800 * sinf(2 * 3.14159265f * 440 * phase++ / AUDIO_SAMPLE_RATE));
            }
            atomic_fetch_sub(&s_tone_frames, 1);
        } else {
            /* Collect 160ms before starting playback to absorb network jitter */
            unsigned depth = uxQueueMessagesWaiting(s_playback);
            if (!playing && depth) {
                if (!first_wait) {
                    first_wait = now;
                }
                if (depth >= PLAYBACK_PREFILL || now - first_wait >= PLAYBACK_WAIT_MS) {
                    playing = true;
                    first_wait = 0;
                }
            }
            if (playing && xQueueReceive(s_playback, &frame, 0) != pdTRUE) {
                playing = false;
            } else if (playing) {
                for (int i = 0; i < AUDIO_FRAME_SAMPLES; i++) {
                    if (frame.samples[i] > VOICE_AUDIBLE_PEAK || frame.samples[i] < -VOICE_AUDIBLE_PEAK) {
                        atomic_store(&s_voice_signal_ms, now);
                        break;
                    }
                }
            }
        }

        mix_music(&frame, &music_gain, &music_primed);

        /* Mix in the alert clip */
        const int16_t *clip = s_clip;
        if (clip) {
            for (int i = 0; i < AUDIO_FRAME_SAMPLES && s_clip_pos < s_clip_len; i++) {
                int v = frame.samples[i] + clip[s_clip_pos++];
                frame.samples[i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
            }
            if (s_clip_pos >= s_clip_len) {
                s_clip = NULL;
            }
        }

        int16_t peak = 0;
        for (int i = 0; i < AUDIO_FRAME_SAMPLES; i++) {
            int16_t s = frame.samples[i];
            int16_t a = s < 0 ? -s : s;
            if (a > peak) {
                peak = a;
            }
            /* Mono speaker: put the same value in both slots (upper 16 bits) */
            stereo[2 * i] = stereo[2 * i + 1] = (int32_t)s * 65536;
        }
        if (peak > 8) {
            atomic_store(&s_last_signal_ms, now);
            atomic_fetch_add(&s_generation, 1);
        }
        led_ring_feed_level(peak);
        /* Keep writing silence even with nothing to play (stopping and restarting causes noise, Section 2.19) */
        board_codec_write(stereo, sizeof(stereo));
    }
}

/* ── Mic task ─────────────────────────────────────────────── */

static void mic_task(void *arg)
{
    static int16_t raw[AUDIO_FRAME_SAMPLES * 4];
    size_t before = heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    aec_handle_t *aec = aec_create(AUDIO_SAMPLE_RATE, 4, 1, AEC_MODE_VOIP_HIGH_PERF);
    configASSERT(aec);
    uint32_t aec_retry_ms = 0;
    ESP_LOGI(TAG, "AEC uses %u B internal RAM",
             (unsigned)(before - heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)));
    int chunk = aec_get_chunksize(aec), filled = 0;
    int16_t *mic = heap_caps_aligned_alloc(16, chunk * sizeof(int16_t), MALLOC_CAP_8BIT);
    int16_t *ref = heap_caps_aligned_alloc(16, chunk * sizeof(int16_t), MALLOC_CAP_8BIT);
    int16_t *clean = heap_caps_aligned_alloc(16, chunk * sizeof(int16_t), MALLOC_CAP_8BIT);
    configASSERT(mic && ref && clean);
    ESP_LOGI(TAG, "AEC chunk %d samples", chunk);

    /* Diagnostics: peak amplitude of the 4 channels before AEC and after AEC (to tell which channel is mic or reference, Chapter 5, Section 5.2) */
    int ch_peak[4] = {0}, clean_peak = 0;
    uint32_t diag_since = now_ms();
    uint32_t ref_active_ms = 0;     /* last time the reference had sound */
    unsigned raw_chunks = 0, aec_chunks = 0;

    for (;;) {
        if (board_codec_read(raw, sizeof(raw)) != ESP_OK) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }
        /* Suspend/resume AEC (only this task touches aec). While suspended, just drain I2S and pass no audio on */
        if (atomic_load(&s_aec_want_off)) {
            if (aec) {
                aec_destroy(aec);
                aec = NULL;
                filled = 0;
                atomic_store(&s_aec_off, true);
                ESP_LOGI(TAG, "AEC suspended (internal free %u)",
                         (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
            }
            continue;
        }
        if (!aec) {
            if (now_ms() < aec_retry_ms) {
                continue;
            }
            aec = aec_create(AUDIO_SAMPLE_RATE, 4, 1, AEC_MODE_VOIP_HIGH_PERF);
            if (!aec) {
                ESP_LOGE(TAG, "AEC re-create failed (internal free %u), retrying",
                         (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
                aec_retry_ms = now_ms() + 1000;
                continue;
            }
            atomic_store(&s_aec_off, false);
            ESP_LOGI(TAG, "AEC resumed");
        }
        for (int i = 0; i < AUDIO_FRAME_SAMPLES * 4; i++) {
            int a = raw[i] < 0 ? -raw[i] : raw[i];
            if (a > ch_peak[i & 3]) {
                ch_peak[i & 3] = a;
            }
        }
        if (now_ms() - diag_since >= 60000) {     /* every minute (for tuning) */
            ESP_LOGI(TAG, "levels: ch0 %d  ch1 %d  ch2 %d  ch3 %d  | aec out %d  (mic=ch1, ref=ch0) | wake input raw %u%%",
                     ch_peak[0], ch_peak[1], ch_peak[2], ch_peak[3], clean_peak,
                     raw_chunks + aec_chunks ? raw_chunks * 100 / (raw_chunks + aec_chunks) : 0);
            raw_chunks = aec_chunks = 0;
            memset(ch_peak, 0, sizeof(ch_peak));
            clean_peak = 0;
            diag_since = now_ms();
        }
        for (int i = 0; i < AUDIO_FRAME_SAMPLES; i++) {
            /* Measured channel layout (16kHz): [0]=reference, [1]=mic 1, [3]=mic 2 (Section 2.7) */
            mic[filled] = raw[4 * i + 1];
            ref[filled++] = raw[4 * i];
            if (filled < chunk) {
                continue;
            }
            filled = 0;
            int ref_peak = 0;
            for (int k = 0; k < chunk; k++) {
                int a = ref[k] < 0 ? -ref[k] : ref[k];
                ref_peak = a > ref_peak ? a : ref_peak;
            }
            uint32_t t = now_ms();
            if (ref_peak > REF_ACTIVE) {
                ref_active_ms = t;
            }
            aec_process(aec, mic, ref, clean);
            for (int k = 0; k < chunk; k++) {
                int a = clean[k] < 0 ? -clean[k] : clean[k];
                if (a > clean_peak) {
                    clean_peak = a;
                }
            }
            audio_mic_processor_t proc = atomic_load(&s_processor);
            if (proc) {
                proc(clean, mic, chunk);
            }
            int n = atomic_load(&s_sink_count);
            for (int s = 0; s < n; s++) {
                s_sinks[s](clean, chunk);
            }
            audio_mic_sink_t wake = atomic_load(&s_wake_sink);
            if (wake) {
                int src = atomic_load(&s_wake_src);
                bool quiet = t - ref_active_ms > REF_HANGOVER_MS;
                bool use_raw = src == AUDIO_WAKE_SRC_RAW || (src == AUDIO_WAKE_SRC_AUTO && quiet);
                use_raw ? raw_chunks++ : aec_chunks++;
                wake(use_raw ? mic : clean, chunk);
            }
        }
    }
}

/* ── Initialization ───────────────────────────────────────── */

static esp_err_t i2s_init(void)
{
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(BOARD_I2S_PORT, I2S_ROLE_MASTER);
    /* One DMA block = one 20ms frame. With the default (511), writes come in bursts and stall */
    chan_cfg.dma_frame_num = AUDIO_FRAME_SAMPLES;
    chan_cfg.auto_clear = true;
    esp_err_t err = i2s_new_channel(&chan_cfg, &s_tx, &s_rx);
    if (err != ESP_OK) {
        return err;
    }
    const i2s_std_config_t std_cfg = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO),
        .gpio_cfg = {
            .mclk = BOARD_I2S_MCLK_GPIO,
            .bclk = BOARD_I2S_BCLK_GPIO,
            .ws = BOARD_I2S_LRCK_GPIO,
            .dout = BOARD_I2S_DOUT_GPIO,
            .din = BOARD_I2S_DIN_GPIO,
        },
    };
    ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_tx, &std_cfg), TAG, "tx init");
    ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_rx, &std_cfg), TAG, "rx init");
    /* MCLK must be running first for codec register writes to take effect */
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_tx), TAG, "tx enable");
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_rx), TAG, "rx enable");
    return ESP_OK;
}

esp_err_t audio_core_init(void)
{
    s_playback_lock = xSemaphoreCreateMutex();
    static StaticQueue_t queue_ctrl;
    uint8_t *storage = heap_caps_malloc(PLAYBACK_FRAMES * sizeof(audio_frame_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_playback_lock || !storage) {
        return ESP_ERR_NO_MEM;
    }
    s_playback = xQueueCreateStatic(PLAYBACK_FRAMES, sizeof(audio_frame_t), storage, &queue_ctrl);
    static StaticStreamBuffer_t music_ctrl;
    uint8_t *music_storage = heap_caps_malloc(MUSIC_BUFFER_BYTES + 1, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!music_storage) {
        return ESP_ERR_NO_MEM;
    }
    s_music = xStreamBufferCreateStatic(MUSIC_BUFFER_BYTES, sizeof(int16_t), music_storage, &music_ctrl);

    /* Register the MP3/AAC decoders only once (shared by the boot sound and the radio) */
    esp_audio_dec_register_default();
    esp_audio_simple_dec_register_default();

    esp_err_t err = i2s_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "I2S init failed: %s", esp_err_to_name(err));
        return err;
    }
    err = board_codec_open(s_tx, s_rx, AUDIO_SAMPLE_RATE);
    if (err != ESP_OK) {
        return err;
    }

    /* Apply saved values right after esp_codec_dev_open() (lesson from an ESPHome bug, Section 2.7) */
    settings_audio_t a;
    settings_get_audio(&a);
    board_codec_set_volume(a.volume);
    board_codec_set_mic_gain((float)a.mic_gain);
    atomic_store(&s_volume, a.volume);

    /* Start silence output first, then turn on the amp 50ms later */
    if (xTaskCreatePinnedToCore(speaker_task, "i2s_tx", 8192, NULL, 8, NULL, 1) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    vTaskDelay(pdMS_TO_TICKS(APP_AMP_ON_DELAY_MS));
    err = board_amp_enable(true);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "amp enable failed: %s", esp_err_to_name(err));
    }

    if (xTaskCreatePinnedToCore(mic_task, "i2s_rx", 16384, NULL, 7, NULL, 1) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "audio ready: %d Hz, volume %d, mic gain %d dB", AUDIO_SAMPLE_RATE, a.volume, a.mic_gain);
    return ESP_OK;
}
