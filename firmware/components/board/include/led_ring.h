/**
 * @file led_ring.h
 * @brief WS2812B × 7 LED ring display (design document, Section 2.15)
 *
 * State flags decide what is shown; a higher-priority display hides a lower one.
 * The state machine in main sets the state from events (the LED module knows nothing about other modules).
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "app_events.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LED_KEY2_NONE,
    LED_KEY2_BLE,       /* reached 3 s: sky-blue ring */
    LED_KEY2_WARN,      /* reached 7 s: red ring fills up */
    LED_KEY2_FACTORY,   /* reached 10 s: fast red blink */
} led_key2_stage_t;

/** Creates the RMT device and starts the display task. The boot display (yellow blink) starts right away */
esp_err_t led_ring_init(void);

void led_ring_set_brightness(uint8_t percent);      /* 0–100. At 0 only priorities 1–3 are shown */
void led_ring_set_booting(bool on);
void led_ring_set_key2_stage(led_key2_stage_t stage);
void led_ring_show_error(void);                      /* red blink for 3 s */
void led_ring_set_ble_window(bool on);
void led_ring_set_wifi_connecting(bool on);
void led_ring_flash_wake(void);                      /* green flash */
void led_ring_set_voice(voice_state_t state);
void led_ring_set_wake_armed(bool on);
void led_ring_set_unread(bool on);
/** a schedule reminder couldn't be delivered as a conversation (no internet or API key): orange display. Turns off when the next conversation starts */
void led_ring_set_reminder(bool on);
/** Music: buffering = slow white blink, playing = soft white level meter (RAD-07) */
void led_ring_set_media(media_play_state_t state);

/** Peak amplitude of the sound being played (0–32767). The audio task feeds it every 20ms */
void led_ring_feed_level(int16_t peak);

#ifdef __cplusplus
}
#endif
