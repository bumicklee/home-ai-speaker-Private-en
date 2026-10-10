/**
 * @file settings.h
 * @brief General settings store (design document Section 2.12, led-app nvs_storage style)
 *
 * Each item has typed get/set functions. If nothing is stored or the value is out of range,
 * the default is returned. Secrets use secret_store.h.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int  volume;            /* 0–80, default 40 */
    int  mic_gain;          /* 0–36 dB, default 36 (on the real board, 30 or below can't hear the wake word) */
    bool auto_gain;         /* default false */
    int  duck_db;           /* 0–40, default 20 */
    bool sp_pause_voice;    /* default false */
} settings_audio_t;

typedef struct {
    bool    enabled;        /* default true */
    uint8_t phrase;         /* 0 Alexa (2026-10-04, previously Jarvis), 1 Computer */
    uint8_t sensitivity;    /* 0–100, default 50 */
    uint8_t gain_db;        /* wake word input digital gain 0–24 dB, default 12 (input was quiet on the real board) */
} settings_wake_t;

/**
 * Initializes the nvs and secrets partitions. nvs_flash_init()-family calls happen only in this function.
 */
esp_err_t settings_init(void);

/* Provisioning */
bool      settings_is_provisioned(void);
esp_err_t settings_set_provisioned(bool provisioned);

/* Wi-Fi (same keys as led-app) */
bool      settings_has_wifi(void);
esp_err_t settings_get_wifi(char ssid[33], char password[65]);
esp_err_t settings_set_wifi(const char *ssid, const char *password);

/* Audio */
void      settings_get_audio(settings_audio_t *out);
esp_err_t settings_set_audio(const settings_audio_t *in);

/* Wake word */
void      settings_get_wake(settings_wake_t *out);
esp_err_t settings_set_wake(const settings_wake_t *in);

/* LED brightness 0–100, default 60 */
uint8_t   settings_get_led_brightness(void);
esp_err_t settings_set_led_brightness(uint8_t brightness);

/* String values (assistant settings JSON, etc.). Pass the buffer size in out_len; on success it holds the actual length (including the NUL) */
esp_err_t settings_get_str(const char *ns, const char *key, char *out, size_t *out_len);
esp_err_t settings_set_str(const char *ns, const char *key, const char *value);

/** Factory reset: erases the nvs and secrets partitions. The caller does the reboot. */
esp_err_t settings_factory_reset(void);

#ifdef __cplusplus
}
#endif
