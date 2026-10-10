/*
 * Key1/Key2/Key3 are on TCA9555 EXIO 9/10/11 (active low). The interrupt pin isn't wired,
 * so every 20ms all three buttons are read in one I2C read (design document, Section 2.15).
 * Confirmed after the same value 2 times in a row (40ms debounce).
 */
#include "board.h"

#include "app_config.h"
#include "app_events.h"
#include "board_config.h"
#include "esp_io_expander.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "BUTTONS";

#define KEY_COUNT        3
#define REPEAT_START_MS  500     /* hold a volume key this long and repeat starts */

typedef struct {
    uint32_t mask;
    app_button_t id;
    bool raw_last;
    uint8_t stable_count;
    bool pressed;
    uint32_t pressed_ms;
    uint32_t next_repeat_ms;
    uint8_t key2_stage;      /* stage reached: 0, 3 s, 7 s, 10 s */
} button_key_t;

static button_key_t s_keys[KEY_COUNT] = {
    {.mask = 1u << BOARD_EXIO_KEY1, .id = APP_BUTTON_KEY1},
    {.mask = 1u << BOARD_EXIO_KEY2, .id = APP_BUTTON_KEY2},
    {.mask = 1u << BOARD_EXIO_KEY3, .id = APP_BUTTON_KEY3},
};

static void post(app_button_t id, app_press_t press)
{
    const app_button_event_t evt = {.button = id, .press = press};
    app_events_post(APP_EVT_BUTTON, &evt, sizeof(evt), 10);
}

static void on_held(button_key_t *k, uint32_t now)
{
    uint32_t held = now - k->pressed_ms;
    if (k->id != APP_BUTTON_KEY2) {
        if (held >= REPEAT_START_MS && (int32_t)(now - k->next_repeat_ms) >= 0) {
            post(k->id, APP_PRESS_REPEAT);
            k->next_repeat_ms = now + APP_VOLUME_REPEAT_MS;
        }
        return;
    }
    if (k->key2_stage < 1 && held >= APP_KEY2_BLE_MS) {
        k->key2_stage = 1;
        post(k->id, APP_PRESS_HOLD_3S);
    } else if (k->key2_stage < 2 && held >= APP_KEY2_WARN_MS) {
        k->key2_stage = 2;
        post(k->id, APP_PRESS_HOLD_7S);
    } else if (k->key2_stage < 3 && held >= APP_KEY2_FACTORY_MS) {
        k->key2_stage = 3;
        post(k->id, APP_PRESS_FACTORY);     /* immediately, without waiting for release */
    }
}

static void on_release(button_key_t *k, uint32_t now)
{
    uint32_t held = now - k->pressed_ms;
    if (k->id != APP_BUTTON_KEY2) {
        if (held < REPEAT_START_MS) {
            post(k->id, APP_PRESS_SHORT);
        }
        return;
    }
    switch (k->key2_stage) {
    case 0: post(k->id, APP_PRESS_SHORT); break;
    case 1: post(k->id, APP_PRESS_BLE_WINDOW); break;
    case 2: post(k->id, APP_PRESS_CANCEL); break;
    default: break;                         /* factory reset already sent */
    }
}

static void buttons_task(void *arg)
{
    esp_io_expander_handle_t expander = board_io_expander();
    const uint32_t all = s_keys[0].mask | s_keys[1].mask | s_keys[2].mask;

    /* start once what the buttons call (LED, playback, conversation) is ready (Section 2.19) */
    app_events_wait_ready(portMAX_DELAY);
    ESP_LOGI(TAG, "polling every %d ms", APP_BUTTON_POLL_MS);

    TickType_t wake = xTaskGetTickCount();
    for (;;) {
        vTaskDelayUntil(&wake, pdMS_TO_TICKS(APP_BUTTON_POLL_MS));
        uint32_t levels = 0;
        if (esp_io_expander_get_level(expander, all, &levels) != ESP_OK) {
            continue;       /* on an I2C error, try again next cycle */
        }
        uint32_t now = (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
        for (int i = 0; i < KEY_COUNT; i++) {
            button_key_t *k = &s_keys[i];
            bool down = (levels & k->mask) == 0;    /* active low */
            if (down != k->raw_last) {
                k->raw_last = down;
                k->stable_count = 1;
                continue;
            }
            if (k->stable_count < APP_BUTTON_DEBOUNCE_COUNT) {
                k->stable_count++;
                if (k->stable_count < APP_BUTTON_DEBOUNCE_COUNT) {
                    continue;
                }
            }
            if (down && !k->pressed) {
                k->pressed = true;
                k->pressed_ms = now;
                k->next_repeat_ms = now + REPEAT_START_MS;
                k->key2_stage = 0;
            } else if (!down && k->pressed) {
                k->pressed = false;
                on_release(k, now);
            } else if (down) {
                on_held(k, now);
            }
        }
    }
}

esp_err_t board_buttons_start(void)
{
    if (!board_io_expander()) {
        return ESP_ERR_INVALID_STATE;
    }
    return xTaskCreatePinnedToCore(buttons_task, "buttons", 3072, NULL, 6, NULL, 0) == pdPASS
               ? ESP_OK : ESP_ERR_NO_MEM;
}
