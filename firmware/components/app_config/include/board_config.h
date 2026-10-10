/**
 * @file board_config.h
 * @brief Waveshare ESP32-S3-AUDIO-Board pins and I2C addresses (design document, Section 2.0)
 *
 * Every pin number in the firmware comes from this file only. Only verified values go here.
 * GPIOs you must not use: 26–32 (flash), 33–37 (octal PSRAM), 0/3/45/46 (strapping),
 * 19/20 (USB), 43/44 (UART0 console).
 */
#pragma once

#include "driver/gpio.h"
#include "driver/i2c_types.h"
#include "driver/i2s_types.h"

/* ── LED ring (WS2812B × 7, RMT) ────────────────────────────── */
#define BOARD_LED_GPIO              GPIO_NUM_38
#define BOARD_LED_COUNT             7
#define BOARD_LED_RMT_RES_HZ        (10 * 1000 * 1000)
/* current limit: per-channel value cap (USB power + amp in use at the same time) */
#define BOARD_LED_CHANNEL_MAX       128

/* ── I2C (shared by codecs, expander chip and RTC, mutex-protected) ───────────── */
#define BOARD_I2C_PORT              I2C_NUM_0
#define BOARD_I2C_SDA_GPIO          GPIO_NUM_11
#define BOARD_I2C_SCL_GPIO          GPIO_NUM_10
#define BOARD_I2C_FREQ_HZ           100000

#define BOARD_I2C_ADDR_ES8311       0x18
#define BOARD_I2C_ADDR_ES7210       0x40
#define BOARD_I2C_ADDR_TCA9555      0x20
#define BOARD_I2C_ADDR_PCF85063     0x51

/* ── I2S (port 1, full duplex) ──────────────────────────────────── */
#define BOARD_I2S_PORT              I2S_NUM_1
#define BOARD_I2S_MCLK_GPIO         GPIO_NUM_12
#define BOARD_I2S_BCLK_GPIO         GPIO_NUM_13
#define BOARD_I2S_LRCK_GPIO         GPIO_NUM_14
#define BOARD_I2S_DIN_GPIO          GPIO_NUM_15   /* ES7210 → ESP */
#define BOARD_I2S_DOUT_GPIO         GPIO_NUM_16   /* ESP → ES8311 */

/* ── TCA9555 EXIO (interrupt not wired, polling only) ───────────────── */
#define BOARD_EXIO_PA_EN            8    /* amp enable, active high. Turn on after codec init */
#define BOARD_EXIO_KEY1             9    /* volume down, active low */
#define BOARD_EXIO_KEY2             10   /* system button, active low */
#define BOARD_EXIO_KEY3             11   /* volume up, active low */
/* Leave EXIO 6/7 (camera clock, USB mux), 0–5 and 12–15 alone */
