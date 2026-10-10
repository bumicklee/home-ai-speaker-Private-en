#include "secret_store.h"

#include "app_config.h"
#include "esp_log.h"
#include "nvs.h"

static const char *TAG = "SECRET";
static const char *NAMESPACE = "sec";

/* Same order as secret_id_t. NVS keys are 15 characters or fewer */
static const char *const KEYS[SECRET_COUNT] = {
    [SECRET_OPENAI_KEY]      = "openai_key",
    [SECRET_TG_BOT_TOKEN]    = "tg_bot_token",
    [SECRET_SP_CLIENT_ID]    = "sp_client_id",
    [SECRET_SP_REFRESH]      = "sp_refresh",
    [SECRET_SP_CONNECT_BLOB] = "sp_connect_blob",
    [SECRET_STOCK_KEY]       = "stock_key",
    [SECRET_GEMINI_KEY]      = "gemini_key",
};

static esp_err_t open_ns(nvs_open_mode_t mode, nvs_handle_t *h)
{
    return nvs_open_from_partition(APP_PART_SECRETS, NAMESPACE, mode, h);
}

esp_err_t secret_set(secret_id_t id, const void *value, size_t len)
{
    if (id >= SECRET_COUNT || (!value && len)) {
        return ESP_ERR_INVALID_ARG;
    }
    nvs_handle_t h;
    esp_err_t err = open_ns(NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_blob(h, KEYS[id], value, len);
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    ESP_LOGI(TAG, "set %s (%u bytes): %s", KEYS[id], (unsigned)len, esp_err_to_name(err));
    return err;
}

esp_err_t secret_get(secret_id_t id, void *out, size_t *len)
{
    if (id >= SECRET_COUNT || !len) {
        return ESP_ERR_INVALID_ARG;
    }
    nvs_handle_t h;
    esp_err_t err = open_ns(NVS_READONLY, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_get_blob(h, KEYS[id], out, len);
    nvs_close(h);
    return err;
}

bool secret_exists(secret_id_t id)
{
    size_t len = 0;
    return secret_get(id, NULL, &len) == ESP_OK && len > 0;
}

esp_err_t secret_erase(secret_id_t id)
{
    if (id >= SECRET_COUNT) {
        return ESP_ERR_INVALID_ARG;
    }
    nvs_handle_t h;
    esp_err_t err = open_ns(NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_erase_key(h, KEYS[id]);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        err = ESP_OK;
    }
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    ESP_LOGI(TAG, "erase %s: %s", KEYS[id], esp_err_to_name(err));
    return err;
}
