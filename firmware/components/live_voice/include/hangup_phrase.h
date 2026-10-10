/**
 * @file hangup_phrase.h
 * @brief Hang-up phrase matcher ("Goodbye Computer"/"잘가 컴퓨터", "Goodbye Alexa"/"잘가 알렉사", "Goodbye Jarvis"/"잘가 자비스", "End conversation"/"대화 종료")
 *
 * Joins input transcript fragments and, once no further word arrives for 0.6 seconds,
 * checks whether a hang-up phrase is present on word boundaries. Hangul UTF-8 bytes are left as they are.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    char text[128];
    unsigned used;
    uint32_t last_ms;
} hangup_phrase_t;

void hangup_phrase_reset(hangup_phrase_t *p);
void hangup_phrase_feed(hangup_phrase_t *p, const char *delta, uint32_t now_ms);
bool hangup_phrase_ready(const hangup_phrase_t *p, uint32_t now_ms);
bool hangup_phrase_selftest(void);
