#include "app_events.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

static const char *TAG = "APP_EVT";

ESP_EVENT_DEFINE_BASE(APP_EVENT);

#define READY_BIT BIT0

static esp_event_loop_handle_t s_loop;
static EventGroupHandle_t s_flags;

esp_err_t app_events_init(void)
{
    if (s_loop) {
        return ESP_OK;
    }
    s_flags = xEventGroupCreate();
    if (!s_flags) {
        return ESP_ERR_NO_MEM;
    }
    const esp_event_loop_args_t args = {
        .queue_size = 32,
        .task_name = "app_evt",
        .task_priority = 5,
        .task_stack_size = 6144,     /* handlers write NVS and create tasks */
        .task_core_id = 0,
    };
    esp_err_t err = esp_event_loop_create(&args, &s_loop);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "event loop create failed: %s", esp_err_to_name(err));
    }
    return err;
}

esp_err_t app_events_post(app_event_id_t id, const void *data, size_t len, uint32_t timeout_ms)
{
    if (!s_loop) {
        return ESP_ERR_INVALID_STATE;
    }
    return esp_event_post_to(s_loop, APP_EVENT, id, data, len, pdMS_TO_TICKS(timeout_ms));
}

esp_err_t app_events_subscribe(app_event_id_t id, esp_event_handler_t handler, void *arg)
{
    if (!s_loop) {
        return ESP_ERR_INVALID_STATE;
    }
    return esp_event_handler_instance_register_with(s_loop, APP_EVENT, id, handler, arg, NULL);
}

void app_events_set_ready(void)
{
    xEventGroupSetBits(s_flags, READY_BIT);
}

bool app_events_wait_ready(uint32_t timeout_ms)
{
    EventBits_t bits = xEventGroupWaitBits(s_flags, READY_BIT, pdFALSE, pdTRUE, pdMS_TO_TICKS(timeout_ms));
    return (bits & READY_BIT) != 0;
}
