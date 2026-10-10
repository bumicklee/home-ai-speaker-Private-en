#include "board.h"

#include "board_config.h"
#include "driver/i2c_master.h"
#include "esp_io_expander_tca95xx_16bit.h"
#include "esp_log.h"

static const char *TAG = "BOARD";

static i2c_master_bus_handle_t s_bus;
static esp_io_expander_handle_t s_expander;

#define PIN(n) (1ULL << (n))

void *board_i2c_bus(void)
{
    return s_bus;
}

void *board_io_expander(void)
{
    return s_expander;
}

static esp_err_t expander_init(void)
{
    esp_err_t err = esp_io_expander_new_i2c_tca95xx_16bit(s_bus, BOARD_I2C_ADDR_TCA9555, &s_expander);
    if (err != ESP_OK) {
        return err;
    }
    /*
     * On creation the driver sets all 16 pins to input and the output register to 0xFFFF (HIGH).
     * Just switching EXIO8 to output as is turns the amp on for an instant. And the public API
     * esp_io_expander_set_level() refuses to write to a pin that is an input. So first write
     * the EXIO8 bit of the output register to 0 directly, then change the direction (Section 2.19).
     * The other pins are inputs, so the output register value doesn't affect them.
     */
    err = s_expander->write_output_reg(s_expander, 0xFFFF & ~PIN(BOARD_EXIO_PA_EN));
    if (err == ESP_OK) {
        err = esp_io_expander_set_dir(s_expander, PIN(BOARD_EXIO_PA_EN), IO_EXPANDER_OUTPUT);
    }
    /* the 3 buttons are inputs. The rest (EXIO 0–7, 12–15) stay at the driver default (input) */
    if (err == ESP_OK) {
        err = esp_io_expander_set_dir(s_expander,
                                      PIN(BOARD_EXIO_KEY1) | PIN(BOARD_EXIO_KEY2) | PIN(BOARD_EXIO_KEY3),
                                      IO_EXPANDER_INPUT);
    }
    return err;
}

esp_err_t board_init(void)
{
    /* the LED doesn't go through the expander chip, so turn it on first to start the boot display */
    if (led_ring_init() != ESP_OK) {
        ESP_LOGW(TAG, "LED ring unavailable; continuing without it");
    }

    const i2c_master_bus_config_t bus_cfg = {
        .i2c_port = BOARD_I2C_PORT,
        .sda_io_num = BOARD_I2C_SDA_GPIO,
        .scl_io_num = BOARD_I2C_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus_cfg, &s_bus);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "I2C bus init failed: %s", esp_err_to_name(err));
        return err;
    }

    err = expander_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "TCA9555 init failed: %s", esp_err_to_name(err));
        return err;
    }

    struct tm now;
    ESP_LOGI(TAG, "board ready (RTC %s)", board_rtc_read(&now) ? "valid" : "not set");
    return ESP_OK;
}

esp_err_t board_amp_enable(bool on)
{
    if (!s_expander) {
        return ESP_ERR_INVALID_STATE;
    }
    return esp_io_expander_set_level(s_expander, PIN(BOARD_EXIO_PA_EN), on ? 1 : 0);
}
