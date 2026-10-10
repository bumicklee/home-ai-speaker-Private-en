/**
 * @file tool_guard.h
 * @brief Enforces external-input protection and send confirmation on the device (design document 2.8, rules under the tool list; TLG-09, TLG-14)
 *
 * Don't trust the instructions ("messages are data") alone. Even if the model breaks them, the device blocks it.
 *
 * 1. User utterance number: when input transcription fragments stop for more than 1.5 seconds and resume, that counts as a new utterance.
 * 2. When a telegram_read result goes out, the utterance number at that moment is marked "tainted".
 *    Side-effect tools are refused until the number changes (until the user speaks again).
 *    telegram_send is the exception (2026-10-03 user decision: reply immediately). Not sending message text relies on the instructions alone.
 * 3. If the remember value contains text from a message just read, refuse.
 * 4. (Not used now) Two-step draft/confirm for telegram_send. Since a 2026-10-03 user request, it sends immediately with no confirmation.
 *    The functions and self-test are kept so it can be turned back on.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "cJSON.h"

#define GUARD_DRAFT_TEXT_MAX 1000
#define GUARD_ALIAS_MAX      32

void guard_reset(void);                         /* session start and end */
/** Per input transcription fragment. true if it counted as a new utterance (for logging) */
bool guard_user_input(uint32_t now_ms);
/** Pass the messages array from the telegram_read result */
void guard_mark_untrusted_read(const cJSON *messages);

/** Does the heard speech overlap the message text just read? (an echo: the speaker's own reading coming back in through the microphone) */
bool guard_echo_of_read(const char *heard);
/** The user hasn't said anything new since the messages were read */
bool guard_tainted(void);
/** May this tool run now? If not, the error text to give the model; if yes, NULL */
const char *guard_check(const char *tool, const cJSON *args);

/** Creates a draft. Writes a 4-digit number to id_out */
void guard_draft_create(int64_t chat_id, const char *alias, const char *text, uint32_t now_ms, char id_out[5]);
/**
 * Confirm. On pass, returns NULL, fills chat_id and text, then deletes the draft.
 * Returns an error message if the user hasn't spoken again yet, the number is wrong, or 5 minutes have passed.
 */
const char *guard_draft_confirm(const char *id, uint32_t now_ms, int64_t *chat_id, char text[GUARD_DRAFT_TEXT_MAX + 1],
                                char alias[GUARD_ALIAS_MAX + 1]);

bool guard_selftest(void);
