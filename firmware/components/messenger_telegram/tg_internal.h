/* messenger_telegram internals */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "messenger_telegram.h"

esp_err_t tg_store_init(void);
bool      tg_chat_registered(int64_t chat_id, char alias_out[TG_ALIAS_MAX + 1]);
/** Register a new chat (update if the chat_id exists). ESP_ERR_NO_MEM when all 10 are used */
esp_err_t tg_chat_add(int64_t chat_id, const char *title, const char *type);
/** Group → supergroup migration (TLG-05) */
void      tg_chat_migrate(int64_t old_id, int64_t new_id);

int64_t tg_last_update_id(void);
void    tg_save_last_update_id(int64_t id, bool force);
