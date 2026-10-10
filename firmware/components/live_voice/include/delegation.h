/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/**
 * @file delegation.h
 * @brief Collect completed function_call items from delegation (Responses) events (original firmware delegation.c)
 *
 * Used only by the response-receiving task. Reset only after that task has stopped.
 */
#pragma once

#include "cJSON.h"

void     delegation_reset(void);
/** Array of completed function_call items (owned by the caller), or NULL */
cJSON   *delegation_event(const cJSON *envelope);
unsigned delegation_selftest(void);     /* 0x1F on pass */
