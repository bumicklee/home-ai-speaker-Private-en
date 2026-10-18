/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/*
 * Ported from the original firmware's hangup_phrase.c. Changes:
 * - Bytes 0x80 and above (UTF-8) are left as is instead of being replaced with spaces
 * - The default wake word became Computer (2026-10-03), so "goodbye computer" is accepted too.
 *   The Jarvis wake word was replaced by Alexa (2026-10-04). The assistant is still named Jarvis, so the Jarvis phrases stay
 * - English edition: added "bye computer/alexa/jarvis" and "end/stop conversation".
 *   A phrase right after "don't", "not" or "never" does not match ("don't end the conversation")
 * - English edition: English phrases only (the Korean phrases of the Korean edition were removed)
 */
#include "hangup_phrase.h"

#include <stddef.h>
#include <string.h>

static const char *const PHRASES[] = {
    "goodbye jarvis",
    "good bye jarvis",
    "bye jarvis",
    "goodbye alexa",
    "good bye alexa",
    "bye alexa",
    "goodbye computer",
    "good bye computer",
    "bye computer",
    "end conversation",
    "end the conversation",
    "stop conversation",
};

#define SETTLE_MS   600     /* there is no transcript-complete event, so wait after the last fragment */
#define GAP_MS      3000    /* a gap longer than this discards the earlier text */

void hangup_phrase_reset(hangup_phrase_t *p)
{
    memset(p, 0, sizeof(*p));
}

static void drop_first_word(hangup_phrase_t *p)
{
    /* When the buffer is full, drop the leading words whole (so a cut-off tail doesn't become a command) */
    char *space = strchr(p->text, ' ');
    if (space) {
        unsigned n = (unsigned)(space - p->text) + 1;
        memmove(p->text, p->text + n, p->used - n + 1);
        p->used -= n;
    } else {
        p->used = 1;
        p->text[0] = 'x';
        p->text[1] = '\0';
    }
}

void hangup_phrase_feed(hangup_phrase_t *p, const char *delta, uint32_t now)
{
    if (!delta || !*delta) {
        return;
    }
    if ((uint32_t)(now - p->last_ms) > GAP_MS) {
        hangup_phrase_reset(p);
    }
    p->last_ms = now;
    while (*delta) {
        unsigned char c = (unsigned char)*delta++;
        if (c >= 'A' && c <= 'Z') {
            c += 'a' - 'A';
        }
        if (c < 0x80 && !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) {
            c = ' ';
        }
        if (c == ' ' && (!p->used || p->text[p->used - 1] == ' ')) {
            continue;
        }
        if (p->used == sizeof(p->text) - 1) {
            drop_first_word(p);
        }
        p->text[p->used++] = (char)c;
        p->text[p->used] = '\0';
    }
}

/* Is the phrase at s right after a negation word ("don't end the conversation")? The apostrophe became a space */
static bool negated(const char *text, const char *s)
{
    static const char *const NEGATIONS[] = {"don t ", "dont ", "don\xe2\x80\x99t ", "not ", "never "};
    for (unsigned i = 0; i < sizeof(NEGATIONS) / sizeof(NEGATIONS[0]); i++) {
        size_t m = strlen(NEGATIONS[i]);
        if ((size_t)(s - text) >= m && !strncmp(s - m, NEGATIONS[i], m) && (s - m == text || s[-(ptrdiff_t)m - 1] == ' ')) {
            return true;
        }
    }
    return false;
}

bool hangup_phrase_ready(const hangup_phrase_t *p, uint32_t now)
{
    if ((uint32_t)(now - p->last_ms) < SETTLE_MS) {
        return false;
    }
    for (unsigned i = 0; i < sizeof(PHRASES) / sizeof(PHRASES[0]); i++) {
        const char *s = p->text;
        size_t n = strlen(PHRASES[i]);
        while ((s = strstr(s, PHRASES[i]))) {
            if ((s == p->text || s[-1] == ' ') && (s[n] == '\0' || s[n] == ' ') && !negated(p->text, s)) {
                return true;
            }
            s++;
        }
    }
    return false;
}

bool hangup_phrase_selftest(void)
{
    hangup_phrase_t p = {0};
    /* Chunks are joined even when they arrive split. Confirmed only 0.6 s after the last chunk */
    hangup_phrase_feed(&p, "GOOD", 100);
    hangup_phrase_feed(&p, "bye, Jar", 200);
    hangup_phrase_feed(&p, "vis!", 300);
    if (hangup_phrase_ready(&p, 500) || !hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* Word boundaries must match */
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "goodbye Jarvison", 100);
    if (hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* A gap of more than 3 s is not joined */
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "goodbye", 100);
    hangup_phrase_feed(&p, " Jarvis", 4000);
    if (hangup_phrase_ready(&p, 5000)) {
        return false;
    }
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "Good-bye, JARVIS.", 100);
    if (!hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* Match on word boundaries even if the phrase is not at the end (keeps the original behavior) */
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "hello Jarvis goodbye", 100);
    if (hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* Wake word Alexa (2026-10-04) */
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "Goodbye, Alexa.", 100);
    if (!hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* Computer (default wake word) */
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "Goodbye, Computer.", 100);
    if (!hangup_phrase_ready(&p, 900)) {
        return false;
    }
    hangup_phrase_reset(&p);
    hangup_phrase_feed(&p, "goodbye computers", 100);
    if (hangup_phrase_ready(&p, 900)) {
        return false;
    }
    /* Case and punctuation don't matter, the phrase may come after other words, a negation in front does not hang up */
    static const char *const EN_YES[] = {"Bye, Computer!", "bye jarvis", "Goodbye Alexa", "End the conversation.",
                                         "end conversation please", "STOP CONVERSATION", "ok, bye alexa",
                                         "Okay, now end the conversation."};
    for (unsigned i = 0; i < sizeof(EN_YES) / sizeof(EN_YES[0]); i++) {
        hangup_phrase_reset(&p);
        hangup_phrase_feed(&p, EN_YES[i], 100);
        if (!hangup_phrase_ready(&p, 900)) {
            return false;
        }
    }
    static const char *const EN_NO[] = {"Don't end the conversation", "don\xe2\x80\x99t end the conversation",
                                        "do not stop conversation", "never end conversation", "the weekend conversation",
                                        "bye computers", "Please don't end the conversation.", "not end conversation"};
    for (unsigned i = 0; i < sizeof(EN_NO) / sizeof(EN_NO[0]); i++) {
        hangup_phrase_reset(&p);
        hangup_phrase_feed(&p, EN_NO[i], 100);
        if (hangup_phrase_ready(&p, 900)) {
            return false;
        }
    }
    return true;
}
