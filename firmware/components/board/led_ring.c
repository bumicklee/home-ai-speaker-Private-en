/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * LED ring display (design document, Section 2.15 priority table).
 * Every 33ms the display task draws one frame of the highest-priority display for the current state.
 * State-change functions may be called from any task (they only change a value and return right away).
 */
#include "led_ring.h"

#include <math.h>
#include <stdatomic.h>
#include "board_config.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "led_strip.h"

static const char *TAG = "LED";

#define FRAME_MS        33
#define WAKE_FLASH_MS   800
#define ERROR_MS        3000

typedef struct {
    uint8_t r, g, b;
} rgb_t;

static led_strip_handle_t s_strip;
static atomic_uint s_brightness = 60;
static atomic_bool s_booting = true;
static atomic_int s_key2_stage = LED_KEY2_NONE;
static atomic_uint s_key2_since;
static atomic_uint s_error_until;
static atomic_bool s_ble_window;
static atomic_bool s_wifi_connecting;
static atomic_uint s_wake_until;
static atomic_int s_voice = VOICE_IDLE;
static atomic_bool s_wake_armed;
static atomic_bool s_unread;
static atomic_bool s_reminder;
static atomic_int s_media = MEDIA_STOPPED;
static atomic_uint s_level_peak;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static bool before(uint32_t until, uint32_t now)
{
    return until && (int32_t)(until - now) > 0;
}

void led_ring_set_brightness(uint8_t percent) { atomic_store(&s_brightness, percent > 100 ? 100 : percent); }
void led_ring_set_booting(bool on) { atomic_store(&s_booting, on); }
void led_ring_show_error(void) { atomic_store(&s_error_until, now_ms() + ERROR_MS); }
void led_ring_set_ble_window(bool on) { atomic_store(&s_ble_window, on); }
void led_ring_set_wifi_connecting(bool on) { atomic_store(&s_wifi_connecting, on); }
void led_ring_flash_wake(void) { atomic_store(&s_wake_until, now_ms() + WAKE_FLASH_MS); }
void led_ring_set_voice(voice_state_t state) { atomic_store(&s_voice, state); }
void led_ring_set_wake_armed(bool on) { atomic_store(&s_wake_armed, on); }
void led_ring_set_unread(bool on) { atomic_store(&s_unread, on); }
void led_ring_set_reminder(bool on) { atomic_store(&s_reminder, on); }
void led_ring_set_media(media_play_state_t state) { atomic_store(&s_media, state); }

void led_ring_set_key2_stage(led_key2_stage_t stage)
{
    atomic_store(&s_key2_since, now_ms());
    atomic_store(&s_key2_stage, stage);
}

void led_ring_feed_level(int16_t peak)
{
    unsigned v = peak < 0 ? -(int)peak : peak;
    unsigned prev = atomic_load(&s_level_peak);
    while (v > prev && !atomic_compare_exchange_weak(&s_level_peak, &prev, v)) {
    }
}

static void fill(rgb_t *px, rgb_t c)
{
    for (int i = 0; i < BOARD_LED_COUNT; i++) {
        px[i] = c;
    }
}

/* Priorities 1–3 (shown even at brightness 0). true if drawn */
static bool render_critical(rgb_t *px, uint32_t now)
{
    int stage = atomic_load(&s_key2_stage);
    if (stage == LED_KEY2_FACTORY) {
        if ((now / 100) % 2 == 0) {
            fill(px, (rgb_t){60, 0, 0});        /* fast red blink */
        }
        return true;
    }
    if (stage == LED_KEY2_WARN) {
        /* red fills up one LED at a time over the 3 s from 7 s to 10 s */
        uint32_t elapsed = now - atomic_load(&s_key2_since);
        int lit = 1 + (int)(elapsed * BOARD_LED_COUNT / 3000);
        for (int i = 0; i < BOARD_LED_COUNT && i < lit; i++) {
            px[i] = (rgb_t){50, 0, 0};
        }
        return true;
    }
    /* 2: OTA progress display is Phase 6 */
    if (before(atomic_load(&s_error_until), now)) {
        if ((now / 500) % 2 == 0) {
            fill(px, (rgb_t){40, 0, 0});        /* error: blink every 0.5 s */
        }
        return true;
    }
    return false;
}

static void render_normal(rgb_t *px, uint32_t now, float level)
{
    int stage = atomic_load(&s_key2_stage);
    if (stage == LED_KEY2_BLE) {
        fill(px, (rgb_t){0, 25, 40});           /* reached 3 s: sky-blue ring */
        return;
    }
    if (atomic_load(&s_ble_window)) {
        if ((now / 150) % 2 == 0) {
            fill(px, (rgb_t){0, 25, 40});       /* BLE window: fast sky-blue blink */
        }
        return;
    }
    if (atomic_load(&s_wifi_connecting)) {
        if ((now / 500) % 2 == 0) {
            fill(px, (rgb_t){0, 0, 40});        /* Wi-Fi connecting: blue blink */
        }
        return;
    }
    if (before(atomic_load(&s_wake_until), now)) {
        fill(px, (rgb_t){0, 45, 0});            /* wake word detected: green flash */
        return;
    }
    int voice = atomic_load(&s_voice);
    if (voice == VOICE_WAKE_ACK || voice == VOICE_CONNECTING) {
        px[(now / 140) % BOARD_LED_COUNT] = (rgb_t){35, 14, 0};    /* connecting: orange spin */
        return;
    }
    if (voice == VOICE_LIVE || voice == VOICE_CLOSING) {
        if (level > 0) {
            /* playing reply: blue level meter */
            for (int i = 0; i < BOARD_LED_COUNT; i++) {
                float f = fminf(1.0f, fmaxf(0, level * BOARD_LED_COUNT - i));
                px[i] = (rgb_t){(uint8_t)(8 * f), (uint8_t)(22 * f), (uint8_t)(64 * f)};
            }
        } else {
            fill(px, (rgb_t){0, 8, 12});        /* listening: teal ring */
        }
        return;
    }
    int media = atomic_load(&s_media);
    if (media == MEDIA_BUFFERING) {
        if ((now / 800) % 2 == 0) {
            fill(px, (rgb_t){10, 10, 10});      /* music buffering: slow white blink */
        }
        return;
    }
    if (media == MEDIA_PLAYING && level > 0) {
        for (int i = 0; i < BOARD_LED_COUNT; i++) {
            float f = fminf(1.0f, fmaxf(0, level * BOARD_LED_COUNT - i));
            uint8_t w = (uint8_t)(10 * f);      /* music playing: soft white level meter */
            px[i] = (rgb_t){w, w, w};
        }
        return;
    }
    if (atomic_load(&s_reminder)) {
        if ((now / 600) % 2 == 0) {
            fill(px, (rgb_t){30, 12, 0});        /* schedule reminder not delivered as a conversation: slow orange blink */
        }
        return;
    }
    if (atomic_load(&s_unread)) {
        px[0] = (rgb_t){20, 0, 30};             /* unread Telegram: purple dot */
        return;
    }
    if (atomic_load(&s_wake_armed)) {
        px[0] = (rgb_t){0, 2, 3};               /* waiting for the wake word: one teal dot */
    }
}

static void led_task(void *arg)
{
    rgb_t px[BOARD_LED_COUNT];
    float envelope = 0;
    for (;;) {
        uint32_t now = now_ms();
        fill(px, (rgb_t){0, 0, 0});

        /* playback loudness → 0–1 level. Falls off slowly */
        unsigned peak = atomic_exchange(&s_level_peak, 0);
        float level = peak > 180 ? fminf(1.0f, sqrtf(peak / 18000.0f)) : 0;
        envelope = fmaxf(level, envelope * 0.78f);
        if (envelope < 0.03f) {
            envelope = 0;
        }

        unsigned brightness = atomic_load(&s_brightness);
        float scale = 1.0f;
        if (atomic_load(&s_booting)) {
            if ((now / 300) % 2 == 0) {
                fill(px, (rgb_t){40, 30, 0});   /* boot: yellow blink (shown alone) */
            }
        } else if (!render_critical(px, now) && brightness > 0) {
            render_normal(px, now, envelope);
            /* the color table values assume the default 60% brightness */
            scale = brightness / 60.0f;
        }

        for (int i = 0; i < BOARD_LED_COUNT; i++) {
            /* current limit: channel cap 128 (Section 2.0) */
            uint32_t r = (uint32_t)fminf(BOARD_LED_CHANNEL_MAX, px[i].r * scale);
            uint32_t g = (uint32_t)fminf(BOARD_LED_CHANNEL_MAX, px[i].g * scale);
            uint32_t b = (uint32_t)fminf(BOARD_LED_CHANNEL_MAX, px[i].b * scale);
            led_strip_set_pixel(s_strip, i, r, g, b);
        }
        led_strip_refresh(s_strip);
        vTaskDelay(pdMS_TO_TICKS(FRAME_MS));
    }
}

esp_err_t led_ring_init(void)
{
    const led_strip_config_t strip_cfg = {
        .strip_gpio_num = BOARD_LED_GPIO,
        .max_leds = BOARD_LED_COUNT,
        .led_model = LED_MODEL_WS2812,
        /* The existing firmware, ESPHome and the demo code all use RGB order. Verify by eye with solid red in Phase 1 */
        .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_RGB,
    };
    const led_strip_rmt_config_t rmt_cfg = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = BOARD_LED_RMT_RES_HZ,
        .flags.with_dma = true,
    };
    esp_err_t err = led_strip_new_rmt_device(&strip_cfg, &rmt_cfg, &s_strip);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "RMT device failed: %s", esp_err_to_name(err));
        return err;
    }
    led_strip_clear(s_strip);
    if (xTaskCreatePinnedToCore(led_task, "led_ring", 3072, NULL, 2, NULL, 0) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}
