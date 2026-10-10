/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/**
 * @file wake.h
 * @brief WakeNet9 wake-word detection (design document Section 2.7, ported from the original firmware's wake_word.c)
 *
 * On detection it sends APP_EVT_WAKE_DETECTED. Starting the conversation is main's job.
 * During a conversation it unloads the model to free memory for TLS (wake_pause / wake_resume).
 */
#pragma once

#include <stdbool.h>
#include "esp_err.h"
#include "settings.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Reads the saved settings and registers the mic sink. The model is loaded after wake_start() */
esp_err_t wake_init(void);
esp_err_t wake_start(void);
esp_err_t wake_stop(void);

/** Unloads the model and waits up to 5 s for the memory to come back. true on success */
bool wake_pause(void);
void wake_resume(void);

/** Change settings (save + apply immediately) */
esp_err_t wake_set_config(const settings_wake_t *cfg);
void      wake_get_config(settings_wake_t *out);

/** Detection test mode for 60 s: on detection, only sends APP_EVT_WAKE_TEST, no conversation */
esp_err_t wake_test(bool enable);
bool      wake_is_testing(void);

/** true while listening for the wake word right now (standby LED) */
bool wake_is_listening(void);

#ifdef __cplusplus
}
#endif
