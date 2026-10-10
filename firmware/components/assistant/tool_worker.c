/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * Tool worker (design document 2.8, "Running tools asynchronously").
 * In the existing firmware the session task ran tools itself, so mic upload stopped during a long tool.
 * Here the response-parsing task only puts calls on the queue; this task runs them and
 * returns the results with live_voice_submit_tool_outputs(). radio_play's station search uses HTTPS here
 * (TLS handshake + JSON parsing) → 12KB stack, tune after measuring
 */
#include "assistant.h"

#include <stdlib.h>
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"
#include "live_voice.h"

static const char *TAG = "TOOLS";

typedef struct {
    cJSON *calls;
    unsigned generation;
    void (*fn)(void *arg);      /* general work (instead of calls) */
    void *arg;
} tool_job_t;

static QueueHandle_t s_jobs;

void assistant_queue_tool_calls(cJSON *calls, unsigned generation)
{
    tool_job_t job = {.calls = calls, .generation = generation};
    if (!s_jobs || xQueueSend(s_jobs, &job, 0) != pdTRUE) {
        ESP_LOGW(TAG, "tool queue full, dropping %d call(s)", cJSON_GetArraySize(calls));
        cJSON_Delete(calls);
    }
}

bool assistant_queue_work(void (*fn)(void *arg), void *arg)
{
    tool_job_t job = {.fn = fn, .arg = arg};
    return s_jobs && xQueueSend(s_jobs, &job, 0) == pdTRUE;
}

static void tool_worker(void *arg)
{
    for (;;) {
        tool_job_t job;
        if (xQueueReceive(s_jobs, &job, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        if (job.fn) {
            job.fn(job.arg);
            continue;
        }
        cJSON *outputs = cJSON_CreateArray();
        const cJSON *call;
        cJSON_ArrayForEach(call, job.calls) {
            /* If the conversation ended (hang-up phrase, button, timeout) or a new session started, don't run the remaining tools.
             * Same as the stopping check in the existing firmware's run_tools() */
            if (job.generation != live_voice_generation() || !live_voice_ready()) {
                break;
            }
            const cJSON *name = cJSON_GetObjectItem(call, "name");
            const cJSON *args = cJSON_GetObjectItem(call, "arguments");
            const cJSON *id = cJSON_GetObjectItem(call, "call_id");
            if (!cJSON_IsString(name) || !cJSON_IsString(args) || !cJSON_IsString(id)) {
                continue;
            }
            /* Log only the tool name (the arguments may be user information) */
            ESP_LOGI(TAG, "run %s", name->valuestring);
            cJSON *result = assistant_execute(name->valuestring, args->valuestring);
            /* Error messages are fixed sentences made by the device, so logging them is fine */
            const cJSON *error = cJSON_GetObjectItem(result, "error");
            if (cJSON_IsString(error)) {
                ESP_LOGW(TAG, "%s failed: %s", name->valuestring, error->valuestring);
            } else {
                ESP_LOGI(TAG, "%s ok", name->valuestring);
            }
            char *text = cJSON_PrintUnformatted(result);
            cJSON_Delete(result);
            if (!text) {
                continue;
            }
            cJSON *out = cJSON_CreateObject();
            cJSON_AddStringToObject(out, "call_id", id->valuestring);
            cJSON_AddStringToObject(out, "output", text);
            free(text);
            cJSON_AddItemToArray(outputs, out);
        }
        cJSON_Delete(job.calls);
        ESP_LOGI(TAG, "stack free min %u B", (unsigned)uxTaskGetStackHighWaterMark(NULL));
        if (cJSON_GetArraySize(outputs) > 0 && job.generation == live_voice_generation()) {
            assistant_note_device_turn();
            live_voice_submit_tool_outputs(outputs, job.generation);
        } else {
            cJSON_Delete(outputs);
        }
    }
}

esp_err_t assistant_tool_worker_start(void)
{
    s_jobs = xQueueCreate(6, sizeof(tool_job_t));
    if (!s_jobs) {
        return ESP_ERR_NO_MEM;
    }
    /* The stack is in PSRAM (NVS works thanks to XIP; Chapter 7, Section 7.3) */
    return xTaskCreatePinnedToCoreWithCaps(tool_worker, "tool_worker", 12288, NULL, 4, NULL, 0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT) == pdPASS ? ESP_OK
                                                                                                 : ESP_ERR_NO_MEM;
}
