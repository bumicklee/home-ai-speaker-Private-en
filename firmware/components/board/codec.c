/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * ES7210 (mic ADC) and ES8311 (speaker DAC) control.
 * The setup follows board_audio.c from the existing firmware (waveshare-ai-speaker-assistant)
 * that worked on the real board: ES7210 with 4 mics selected, ES8311 use_mclk=false, pa_pin=-1.
 */
#include "board.h"

#include "app_config.h"
#include "board_config.h"
#include "esp_codec_dev.h"
#include "esp_codec_dev_defaults.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "CODEC";

static esp_codec_dev_handle_t s_adc;    /* ES7210 */
static esp_codec_dev_handle_t s_dac;    /* ES8311 */

/* esp_codec_dev address constants use 8-bit notation (7-bit 0x40 → 0x80, 0x18 → 0x30) */
_Static_assert(ES7210_CODEC_DEFAULT_ADDR == (BOARD_I2C_ADDR_ES7210 << 1), "ES7210 address mismatch");
_Static_assert(ES8311_CODEC_DEFAULT_ADDR == (BOARD_I2C_ADDR_ES8311 << 1), "ES8311 address mismatch");

static esp_err_t open_adc(i2s_chan_handle_t rx, const esp_codec_dev_sample_info_t *fmt)
{
    audio_codec_i2s_cfg_t data_cfg = {.port = BOARD_I2S_PORT, .rx_handle = rx};
    audio_codec_i2c_cfg_t ctrl_cfg = {.port = BOARD_I2C_PORT, .addr = ES7210_CODEC_DEFAULT_ADDR,
                                      .bus_handle = board_i2c_bus()};
    es7210_codec_cfg_t codec_cfg = {
        .ctrl_if = audio_codec_new_i2c_ctrl(&ctrl_cfg),
        .mic_selected = ES7210_SEL_MIC1 | ES7210_SEL_MIC2 | ES7210_SEL_MIC3 | ES7210_SEL_MIC4,
    };
    if (!codec_cfg.ctrl_if) {
        return ESP_ERR_NO_MEM;
    }
    esp_codec_dev_cfg_t dev_cfg = {
        .codec_if = es7210_codec_new(&codec_cfg),
        .data_if = audio_codec_new_i2s_data(&data_cfg),
        .dev_type = ESP_CODEC_DEV_TYPE_IN,
    };
    s_adc = esp_codec_dev_new(&dev_cfg);
    if (!s_adc) {
        return ESP_ERR_NO_MEM;
    }

    /* there are reports of the mic not coming up on a cold boot, so read a register after opening to confirm (Section 2.19) */
    for (int attempt = 1; attempt <= 3; attempt++) {
        int reg = -1;
        if (esp_codec_dev_open(s_adc, (esp_codec_dev_sample_info_t *)fmt) == ESP_CODEC_DEV_OK &&
            esp_codec_dev_read_reg(s_adc, 0x00, &reg) == ESP_CODEC_DEV_OK) {
            ESP_LOGI(TAG, "ES7210 open (reg00=0x%02x, attempt %d)", reg, attempt);
            return ESP_OK;
        }
        ESP_LOGW(TAG, "ES7210 open failed (attempt %d)", attempt);
        esp_codec_dev_close(s_adc);
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    return ESP_FAIL;
}

static esp_err_t open_dac(i2s_chan_handle_t tx, const esp_codec_dev_sample_info_t *fmt)
{
    audio_codec_i2s_cfg_t data_cfg = {.port = BOARD_I2S_PORT, .tx_handle = tx};
    audio_codec_i2c_cfg_t ctrl_cfg = {.port = BOARD_I2C_PORT, .addr = ES8311_CODEC_DEFAULT_ADDR,
                                      .bus_handle = board_i2c_bus()};
    es8311_codec_cfg_t codec_cfg = {
        .codec_mode = ESP_CODEC_DEV_WORK_MODE_DAC,
        .ctrl_if = audio_codec_new_i2c_ctrl(&ctrl_cfg),
        .gpio_if = audio_codec_new_gpio(),
        .pa_pin = -1,           /* the amp is turned on separately via TCA9555 EXIO8 */
        .use_mclk = false,
    };
    if (!codec_cfg.ctrl_if || !codec_cfg.gpio_if) {
        return ESP_ERR_NO_MEM;
    }
    esp_codec_dev_cfg_t dev_cfg = {
        .codec_if = es8311_codec_new(&codec_cfg),
        .data_if = audio_codec_new_i2s_data(&data_cfg),
        .dev_type = ESP_CODEC_DEV_TYPE_OUT,
    };
    s_dac = esp_codec_dev_new(&dev_cfg);
    if (!s_dac) {
        return ESP_ERR_NO_MEM;
    }
    return esp_codec_dev_open(s_dac, (esp_codec_dev_sample_info_t *)fmt) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}

esp_err_t board_codec_open(i2s_chan_handle_t tx, i2s_chan_handle_t rx, uint32_t sample_rate)
{
    /* two 32-bit slots. The ES7210 packs two 16-bit samples into each slot, giving 4 channels */
    const esp_codec_dev_sample_info_t fmt = {
        .sample_rate = sample_rate,
        .channel = 2,
        .bits_per_sample = 32,
    };
    esp_err_t err = open_adc(rx, &fmt);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ES7210 unavailable");
        return err;
    }
    err = open_dac(tx, &fmt);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ES8311 unavailable");
    }
    return err;
}

esp_err_t board_codec_read(void *data, size_t bytes)
{
    return esp_codec_dev_read(s_adc, data, bytes) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}

esp_err_t board_codec_write(const void *data, size_t bytes)
{
    return esp_codec_dev_write(s_dac, (void *)data, bytes) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}

esp_err_t board_codec_set_volume(int volume)
{
    if (volume < 0) {
        volume = 0;
    }
    if (volume > APP_VOLUME_MAX) {
        volume = APP_VOLUME_MAX;    /* the speaker distorts at high volume (Section 2.19) */
    }
    return esp_codec_dev_set_out_vol(s_dac, volume) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}

esp_err_t board_codec_set_mic_gain(float db)
{
    if (db < 0) {
        db = 0;
    }
    if (db > APP_MIC_GAIN_MAX_DB) {
        db = APP_MIC_GAIN_MAX_DB;
    }
    return esp_codec_dev_set_in_gain(s_adc, db) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}

esp_err_t board_codec_set_mic_mute(bool mute)
{
    /* gain 0 doesn't mute (0dB is unity). Use the codec mute */
    return esp_codec_dev_set_in_mute(s_adc, mute) == ESP_CODEC_DEV_OK ? ESP_OK : ESP_FAIL;
}
