/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/**
 * @file assistant.h
 * @brief Assistant settings and memories, prompt (session.start) building, tool execution (design document 2.8, Voice Conversation)
 *
 * Moved from the existing firmware's assistant.c. It registers handlers with live_voice
 * to build the session start event, and runs tool calls in the tool worker task.
 */
#pragma once

#include <stdbool.h>
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Reads settings and memories from NVS, starts the tool worker and mic processing, and registers the live_voice handlers */
esp_err_t assistant_init(void);

/** Copy of the current settings (caller must cJSON_Delete) */
cJSON    *assistant_settings(void);
esp_err_t assistant_save(const cJSON *settings);
cJSON    *assistant_memories(void);
/** Array of selectable OpenAI voice names (caller must cJSON_Delete) */
cJSON    *assistant_voice_list(void);
esp_err_t assistant_forget(const char *key);

/** session.start JSON (caller must free) */
char     *assistant_start_event(void);
/**
 * Opens a short conversation that reads out new Telegram messages (TLG-10, auto-read).
 * ESP_ERR_INVALID_STATE or similar during a conversation or English lesson, or if it cannot start
 */
esp_err_t assistant_announce_telegram(int unread);
/**
 * Opens a reminder conversation (main.c calls it while the notes module holds a batch). During a conversation or English lesson,
 * or if it cannot start, ESP_ERR_INVALID_STATE (busy, try again later). Any other failure is treated as an internet or API key problem.
 */
esp_err_t assistant_announce_reminders(void);
/** Runs one tool. Result is {"ok": bool, ...} (caller must cJSON_Delete) */
cJSON    *assistant_execute(const char *name, const char *arguments);

/** The device made the model answer (tool result, auto-read). Input heard while that turn's audio plays is treated as echo */
void      assistant_note_device_turn(void);
/* Tool worker (tool_worker.c) */
esp_err_t assistant_tool_worker_start(void);
void      assistant_queue_tool_calls(cJSON *calls, unsigned generation);
/**
 * Runs blocking work (HTTPS, etc.) on the tool worker, so LAN handlers don't block the web server task.
 * false if the queue is full (fn is not called, so the caller cleans up arg)
 */
bool      assistant_queue_work(void (*fn)(void *arg), void *arg);

/** Self-test for the 13-key settings and migrating old settings (9 or 10 keys). true on pass (docs/design-voice-saver-mode.md 11.9) */
bool      assistant_settings_migration_selftest(void);

#ifdef __cplusplus
}
#endif
