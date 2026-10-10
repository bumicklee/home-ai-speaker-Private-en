/**
 * @file board.h
 * @brief Waveshare ESP32-S3-AUDIO-Board hardware (design document, Sections 2.0, 2.15, 2.19)
 *
 * I2C bus, TCA9555 expander chip (amp, buttons), codecs (ES8311/ES7210), LED ring, button polling, RTC.
 * The I2C bus is shared by the codecs, expander chip and RTC. The IDF 5.x i2c_master driver serializes
 * transactions per bus, so there is no separate per-task mutex.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>
#include "esp_err.h"
#include "driver/i2s_types.h"
#include "led_ring.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initializes in this order: LED ring (yellow boot blink) → I2C → TCA9555 (amp LOW, button inputs) → RTC.
 * The codecs need I2S channels, so audio_core opens them with board_codec_open().
 */
esp_err_t board_init(void);

/** Speaker amplifier (EXIO8). Enable after codec init, once TX has started outputting silence */
esp_err_t board_amp_enable(bool on);

/* ── Codecs (codec.c) ──────────────────────────────────────── */

/**
 * Opens the ES7210 (mic) and ES8311 (speaker). The I2S channels must already be enabled
 * (MCLK must be running before the codecs can be configured). On failure the ES7210 retries after 50ms, up to 3 times.
 */
esp_err_t board_codec_open(i2s_chan_handle_t tx, i2s_chan_handle_t rx, uint32_t sample_rate);
esp_err_t board_codec_read(void *data, size_t bytes);
esp_err_t board_codec_write(const void *data, size_t bytes);
esp_err_t board_codec_set_volume(int volume);       /* 0–80 */
esp_err_t board_codec_set_mic_gain(float db);       /* 0–37.5 */
esp_err_t board_codec_set_mic_mute(bool mute);

/* ── Buttons (buttons.c) ────────────────────────────────────── */

/**
 * Creates a task that polls the TCA9555 every 20ms. The task starts working after
 * app_events_wait_ready(). Results are sent as APP_EVT_BUTTON events.
 */
esp_err_t board_buttons_start(void);

/* ── RTC (rtc.c, PCF85063) ───────────────────────────────── */

/** true if the time is valid (no oscillator-stop flag, 2026 or later) */
bool      board_rtc_read(struct tm *out);
esp_err_t board_rtc_write(const struct tm *utc);

/* Internal: the other board files use the same I2C bus and expander chip */
void *board_i2c_bus(void);
void *board_io_expander(void);

#ifdef __cplusplus
}
#endif
