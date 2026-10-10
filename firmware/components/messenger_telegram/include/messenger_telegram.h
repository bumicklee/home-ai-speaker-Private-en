/**
 * @file messenger_telegram.h
 * @brief Telegram Bot API (design document Section 2.11, features TLG-02–09, 12–14)
 *
 * The speaker fetches messages itself with getUpdates long polling (no webhook, no public address).
 * Only messages from registered chats (up to 10) go into the PSRAM ring buffer (20 slots); the rest are ignored.
 * The bot token is part of every URL, so URLs are never logged.
 *
 * Message text is external input. This module doesn't interpret it or use it as instructions.
 * Protection at the tool level (TLG-14) is done by assistant.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TG_MAX_CHATS     10
#define TG_ALIAS_MAX     32
#define TG_TEXT_MAX      1000   /* send limit (design document tool table) */
#define TG_RING_SIZE     20

typedef enum {
    TG_OFF,             /* no token */
    TG_CONNECTING,
    TG_OK,
    TG_CONFLICT,        /* 409: the same bot is polled elsewhere, or a webhook is set (TLG-13) */
    TG_TOKEN_INVALID,   /* 401 */
} tg_state_t;

esp_err_t telegram_init(void);
/** Starts polling once Wi-Fi is up. With no token, waits until one is saved */
esp_err_t telegram_start(void);
/**
 * Pauses polling during a conversation or OTA (TLG-12). Stops once the long poll in progress (up to 25 s) finishes.
 * Telegram keeps messages for 24 hours, so none are lost.
 */
void telegram_pause(bool paused);

tg_state_t  telegram_state(void);
const char *telegram_state_name(tg_state_t state);
const char *telegram_bot_username(void);
int         telegram_unread(void);

/**
 * Reads recent messages and marks them read. target is an alias (case-insensitive, partial match) or NULL (all).
 * Result: {"untrusted": true, "messages": [{"from","chat","minutes_ago","text"}]}
 */
cJSON *telegram_read(const char *target, int count);

/** Sends to a registered chat (blocking, HTTPS). Called from the tool worker */
esp_err_t telegram_send(int64_t chat_id, const char *text);

/** 6-digit pairing code (5 minutes, single use, invalid after 5 wrong tries) (TLG-03) */
esp_err_t telegram_begin_pairing(char code[7]);

/* ── Chats (tg_store.c) ───────────────────────────────────── */

/** [{chat_id, alias, title, type}] */
cJSON    *telegram_chats(void);
/** Finds by alias (case-insensitive, partial match) */
bool      telegram_find_chat(const char *alias, int64_t *chat_id, char alias_out[TG_ALIAS_MAX + 1]);
esp_err_t telegram_chat_rename(int64_t chat_id, const char *alias);
esp_err_t telegram_chat_remove(int64_t chat_id);

/** {auto_read, quiet_start, quiet_end}. Quiet hours are in hours (0–23); start equal to end means none */
cJSON    *telegram_options(void);
esp_err_t telegram_options_set(const cJSON *value);
/** true if auto-read is on and it isn't quiet hours now (TLG-10) */
bool      telegram_auto_read_now(void);

#ifdef __cplusplus
}
#endif
