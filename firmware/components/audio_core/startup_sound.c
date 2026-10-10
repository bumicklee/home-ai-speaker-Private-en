/*
 * Decodes the short sounds embedded in the firmware (16kHz mono MP3) once into PSRAM with esp_audio_codec and hands them to the playback task.
 * - startup.mp3: boot sound (about 11KB)
 * - ready.mp3: ready announcement (about 7KB, a user-supplied WAV converted to 16kHz mono. 2026-10-03)
 */
#include "audio_core.h"

#include <stdlib.h>
#include <string.h>
#include "esp_audio_dec_default.h"
#include "esp_audio_simple_dec.h"
#include "esp_audio_simple_dec_default.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"

static const char *TAG = "STARTUP";

extern const uint8_t startup_mp3_start[] asm("_binary_startup_mp3_start");
extern const uint8_t startup_mp3_end[] asm("_binary_startup_mp3_end");
extern const uint8_t ready_mp3_start[] asm("_binary_ready_mp3_start");
extern const uint8_t ready_mp3_end[] asm("_binary_ready_mp3_end");

void audio_core_play_clip(const int16_t *pcm, size_t samples);

#define MAX_SECONDS   4
#define WAIT_QUIET_MS 15000     /* max time to wait for other sound (boot sound etc.) to finish */

typedef struct {
    const char *name;
    const uint8_t *mp3;
    const uint8_t *mp3_end;
    bool wait_quiet;            /* wait for the current sound to finish instead of cutting it off */
    int16_t *pcm;
    size_t samples;
} clip_t;

static clip_t s_startup = {.name = "startup", .mp3 = startup_mp3_start, .mp3_end = startup_mp3_end};
static clip_t s_ready = {.name = "ready", .mp3 = ready_mp3_start, .mp3_end = ready_mp3_end, .wait_quiet = true};

static esp_err_t decode(clip_t *c)
{
    esp_audio_simple_dec_cfg_t cfg = {.dec_type = ESP_AUDIO_SIMPLE_DEC_TYPE_MP3};
    esp_audio_simple_dec_handle_t dec = NULL;
    if (esp_audio_simple_dec_open(&cfg, &dec) != ESP_AUDIO_ERR_OK) {
        return ESP_FAIL;
    }

    const size_t capacity = AUDIO_SAMPLE_RATE * MAX_SECONDS;
    c->pcm = heap_caps_malloc(capacity * sizeof(int16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    uint32_t out_size = 4608;   /* one MP3 frame (1152 samples × 2 channels × 2 bytes) */
    uint8_t *out_buf = malloc(out_size);
    esp_err_t result = (c->pcm && out_buf) ? ESP_OK : ESP_ERR_NO_MEM;

    esp_audio_simple_dec_raw_t raw = {
        .buffer = (uint8_t *)c->mp3,
        .len = c->mp3_end - c->mp3,
        .eos = true,
    };
    while (result == ESP_OK && raw.len > 0) {
        esp_audio_simple_dec_out_t out = {.buffer = out_buf, .len = out_size};
        esp_audio_err_t ret = esp_audio_simple_dec_process(dec, &raw, &out);
        if (ret == ESP_AUDIO_ERR_BUFF_NOT_ENOUGH) {
            uint8_t *bigger = realloc(out_buf, out.needed_size);
            if (!bigger) {
                result = ESP_ERR_NO_MEM;
                break;
            }
            out_buf = bigger;
            out_size = out.needed_size;
            continue;
        }
        if (ret != ESP_AUDIO_ERR_OK) {
            result = ESP_FAIL;
            break;
        }
        raw.buffer += raw.consumed;
        raw.len -= raw.consumed;
        if (out.decoded_size == 0) {
            if (raw.consumed == 0) {
                break;
            }
            continue;
        }
        esp_audio_simple_dec_info_t info = {0};
        esp_audio_simple_dec_get_info(dec, &info);
        if (info.sample_rate != AUDIO_SAMPLE_RATE || info.bits_per_sample != 16) {
            /* The resampler comes in Phase 3. For now only 16kHz files play */
            ESP_LOGW(TAG, "unsupported format %lu Hz / %u bit", (unsigned long)info.sample_rate, info.bits_per_sample);
            result = ESP_ERR_NOT_SUPPORTED;
            break;
        }
        const int16_t *pcm = (const int16_t *)out_buf;
        size_t frames = out.decoded_size / sizeof(int16_t) / (info.channel ? info.channel : 1);
        if (c->samples + frames > capacity) {
            ESP_LOGW(TAG, "clip longer than %d s, truncated", MAX_SECONDS);
            frames = capacity - c->samples;
            raw.len = 0;
        }
        for (size_t i = 0; i < frames; i++) {
            /* Mix stereo down to mono */
            c->pcm[c->samples++] = info.channel == 2 ? (int16_t)((pcm[2 * i] + pcm[2 * i + 1]) / 2) : pcm[i];
        }
    }
    free(out_buf);
    esp_audio_simple_dec_close(dec);
    if (result == ESP_OK && c->samples == 0) {
        result = ESP_FAIL;
    }
    return result;
}

static void clip_task(void *arg)
{
    clip_t *c = arg;
    if (!c->samples) {
        esp_err_t err = decode(c);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "%s: decode failed: %s", c->name, esp_err_to_name(err));
            free(c->pcm);
            c->pcm = NULL;
            c->samples = 0;
            vTaskDeleteWithCaps(NULL);     /* task created WithCaps */
            return;
        }
        ESP_LOGI(TAG, "%s: decoded %u ms", c->name, (unsigned)(c->samples * 1000 / AUDIO_SAMPLE_RATE));
    }
    /* audio_core_play_clip replaces the clip that is playing, so wait for quiet when needed */
    for (int waited = 0; c->wait_quiet && audio_core_is_playing() && waited < WAIT_QUIET_MS; waited += 100) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    audio_core_play_clip(c->pcm, c->samples);
    vTaskDeleteWithCaps(NULL);
}

static esp_err_t play(clip_t *c)
{
    return xTaskCreatePinnedToCoreWithCaps(clip_task, "clip_snd", 8192, c, 3, NULL, 0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) == pdPASS
               ? ESP_OK : ESP_ERR_NO_MEM;
}

esp_err_t audio_core_play_startup(void)
{
    return play(&s_startup);
}

esp_err_t audio_core_play_ready(void)
{
    return play(&s_ready);
}
