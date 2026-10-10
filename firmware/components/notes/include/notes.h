/**
 * @file notes.h
 * @brief Voice notes and events + event reminders (design document docs/design-notes-schedule.md, second edition, Sections 4, 5, and 8)
 *
 * The original lives on the speaker (/storage/notes.jsonl); family phones keep a full copy in sync over the LAN API (by rev).
 * All data lives in PSRAM (internal RAM has very little headroom). No new task is created:
 * for reminder checks, main.c's 30 s esp_timer → APP_EVT_NOTES_TICK calls this module's notes_tick().
 *
 * Titles, content, and search terms never go into any log. Logs show only id, rev, and counts.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Loads /storage/notes.jsonl and notes.meta into PSRAM, and reads the reminder settings from NVS "notes"/"cfg" */
esp_err_t notes_init(void);

/* ── LAN API (local_api.c) ────────────────────────────────────────────── */

/**
 * JSON body text holding the items changed after since (including deletion records, rev ascending) + the current rev.
 * PSRAM buffer (the caller frees it). NULL if out of memory.
 */
char *notes_api_since_text(uint32_t since);

/** Create. ESP_OK (fills note_out) | ESP_ERR_INVALID_ARG | ESP_ERR_INVALID_SIZE (over 1,000 items, FULL) */
esp_err_t notes_api_create(const cJSON *body, cJSON **note_out);

/**
 * Edit. ESP_OK | ESP_ERR_NOT_FOUND (missing or gone) | ESP_ERR_INVALID_ARG
 * | ESP_ERR_INVALID_STATE (409 CONFLICT, fills conflict_out with the latest item)
 */
esp_err_t notes_api_update(const char *id, const cJSON *body, cJSON **note_out, cJSON **conflict_out);

/** Permanently delete the original (gone). ESP_OK (result_out = {"id","rev","state":"gone"}) | ESP_ERR_NOT_FOUND */
esp_err_t notes_api_delete(const char *id, cJSON **result_out);

/** Restore from the trash. ESP_OK | ESP_ERR_NOT_FOUND (missing or gone) */
esp_err_t notes_api_restore(const char *id, cJSON **note_out);

/** Reminder settings (the caller calls cJSON_Delete) */
cJSON    *notes_settings_get(void);
/** Partial update. ESP_OK | ESP_ERR_INVALID_ARG */
esp_err_t notes_settings_set(const cJSON *body);

/* ── Assistant tools (assistant.c) ────────────────────────────────────── */
/* All of them: return an error message for the model if something is wrong, NULL on success (the result goes into out) */
const char *notes_tool_add(const cJSON *args, cJSON *out);
const char *notes_tool_search(const cJSON *args, cJSON *out);
const char *notes_tool_update(const cJSON *args, cJSON *out);
const char *notes_tool_delete(const cJSON *args, cJSON *out);
const char *notes_tool_snooze(const cJSON *args, cJSON *out);

/* ── Reminder engine ──────────────────────────────────────────────────── */

/** Every 30 s (main.c APP_EVT_NOTES_TICK): works out what to announce and what was missed. Skips if the clock is not valid */
void notes_tick(void);
/** A batch is waiting to be announced (not yet committed) */
bool notes_reminder_pending(void);
/**
 * Once, when the conversation is ready: commits the batch as "sent" (rev bump, WS notes and reminder events) and returns the text to speak
 * (600 bytes or less, the caller frees it). NULL if nothing is waiting.
 */
char *notes_reminder_build_text(void);
/** Call once when the user first speaks during a reminder conversation (not an echo). Marks the committed batch "acknowledged" */
void notes_reminder_acked(void);
/** When the reminder conversation ends: items not yet acknowledged are settled as "no answer" and the batch is cleared */
void notes_reminder_session_end(void);
/** When a conversation can't be opened (no internet, no API key): records the batch as "missed" and clears it (won't ring again) */
void notes_reminder_unreachable(void);

/* The pure-logic self-test (dates, UTF-8, search, id) is notes_selftest() in notes_logic.h (compiles with cc even without ESP-IDF) */

/**
 * Self-test for notes.c's reminder state transitions (computing missed times, pre-filling reminders already past at creation as reminded, over 30 minutes → missed).
 * It doesn't touch flash, but it depends on ESP-IDF (heap_caps etc.), so it runs only on the device.
 */
bool notes_state_selftest(void);

#ifdef __cplusplus
}
#endif
