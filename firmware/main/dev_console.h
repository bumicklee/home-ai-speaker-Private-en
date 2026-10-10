/**
 * @file dev_console.h
 * @brief Development USB console (CONFIG_APP_DEV_CONSOLE)
 */
#pragma once

#include "esp_err.h"

/** Registers the commands and starts the USB-Serial-JTAG line input task */
esp_err_t dev_console_start(void);
