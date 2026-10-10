/*
 * PCF85063 RTC. Registers 0x04–0x0A hold seconds, minutes, hours, day, weekday, month, year (BCD).
 * If bit7 (OS) of the seconds register is 1, the oscillator had stopped and the time can't be trusted.
 * The RTC stores UTC.
 */
#include "board.h"

#include "board_config.h"
#include "driver/i2c_master.h"
#include "esp_log.h"

static const char *TAG = "RTC";

#define REG_SECONDS   0x04
#define OS_FLAG       0x80
#define VALID_YEAR    2026
#define I2C_TIMEOUT   100

static i2c_master_dev_handle_t s_dev;

static esp_err_t ensure_dev(void)
{
    if (s_dev) {
        return ESP_OK;
    }
    if (!board_i2c_bus()) {
        return ESP_ERR_INVALID_STATE;
    }
    const i2c_device_config_t cfg = {
        .device_address = BOARD_I2C_ADDR_PCF85063,
        .scl_speed_hz = BOARD_I2C_FREQ_HZ,
    };
    return i2c_master_bus_add_device(board_i2c_bus(), &cfg, &s_dev);
}

static uint8_t bcd2bin(uint8_t v)
{
    return (v >> 4) * 10 + (v & 0x0F);
}

static uint8_t bin2bcd(int v)
{
    return (uint8_t)(((v / 10) << 4) | (v % 10));
}

bool board_rtc_read(struct tm *out)
{
    uint8_t reg = REG_SECONDS, raw[7];
    if (ensure_dev() != ESP_OK ||
        i2c_master_transmit_receive(s_dev, &reg, 1, raw, sizeof(raw), I2C_TIMEOUT) != ESP_OK) {
        ESP_LOGW(TAG, "read failed");
        return false;
    }
    if (raw[0] & OS_FLAG) {
        return false;
    }
    *out = (struct tm){
        .tm_sec = bcd2bin(raw[0] & 0x7F),
        .tm_min = bcd2bin(raw[1] & 0x7F),
        .tm_hour = bcd2bin(raw[2] & 0x3F),
        .tm_mday = bcd2bin(raw[3] & 0x3F),
        .tm_wday = raw[4] & 0x07,
        .tm_mon = bcd2bin(raw[5] & 0x1F) - 1,
        .tm_year = bcd2bin(raw[6]) + 100,
    };
    return out->tm_year + 1900 >= VALID_YEAR;
}

esp_err_t board_rtc_write(const struct tm *utc)
{
    esp_err_t err = ensure_dev();
    if (err != ESP_OK) {
        return err;
    }
    const uint8_t data[8] = {
        REG_SECONDS,
        bin2bcd(utc->tm_sec),       /* also clears the OS flag */
        bin2bcd(utc->tm_min),
        bin2bcd(utc->tm_hour),
        bin2bcd(utc->tm_mday),
        (uint8_t)utc->tm_wday,
        bin2bcd(utc->tm_mon + 1),
        bin2bcd(utc->tm_year % 100),
    };
    err = i2c_master_transmit(s_dev, data, sizeof(data), I2C_TIMEOUT);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "write failed: %s", esp_err_to_name(err));
    }
    return err;
}
