/* media_radio internals */
#pragma once

#include "app_config.h"
#include "esp_err.h"

esp_err_t radio_presets_init(void);

#define RADIO_USER_AGENT "AISpeaker/" APP_FW_VERSION " (ESP32-S3)"
