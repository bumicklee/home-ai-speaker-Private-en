#include "saver_text.h"

#include <ctype.h>
#include <string.h>

static bool is_ascii_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/* ASCII punctuation (including space) treated as meaningless. Every non-ASCII (UTF-8) character counts as "meaningful" */
static bool is_ascii_filler_char(unsigned char c)
{
    return is_ascii_space(c) || strchr(".,!?~'\"-", (char)c) != NULL;
}

static const char *trim(const char *s, size_t *len)
{
    size_t n = strlen(s);
    size_t start = 0;
    while (start < n && is_ascii_space((unsigned char)s[start])) {
        start++;
    }
    size_t end = n;
    while (end > start && is_ascii_space((unsigned char)s[end - 1])) {
        end--;
    }
    *len = end - start;
    return s + start;
}

/* Noise phrases (docs/design-voice-saver-mode.md 11.6). Strip trailing ASCII punctuation and surrounding spaces, lowercase
 * ASCII only, then compare (non-ASCII bytes are left as is). Anything longer than 256 bytes is not such a short phrase to begin with */
static const char *const FILLERS[] = {
    "thank you",
    "thank you for watching",
    "thanks for watching",
    "bye",
};
#define FILLER_COUNT (sizeof(FILLERS) / sizeof(FILLERS[0]))

static bool matches_filler(const char *text, size_t len)
{
    if (len == 0 || len >= 256) {
        return false;
    }
    char buf[256];
    memcpy(buf, text, len);
    buf[len] = '\0';
    /* Strip trailing ASCII punctuation (periods etc.) */
    while (len > 0 && strchr(".,!?~ \t", buf[len - 1])) {
        buf[--len] = '\0';
    }
    /* Lowercase ASCII only */
    for (size_t i = 0; i < len; i++) {
        if ((unsigned char)buf[i] < 0x80) {
            buf[i] = (char)tolower((unsigned char)buf[i]);
        }
    }
    for (size_t i = 0; i < FILLER_COUNT; i++) {
        if (!strcmp(buf, FILLERS[i])) {
            return true;
        }
    }
    return false;
}

bool saver_text_is_noise(const char *text)
{
    if (!text) {
        return true;
    }
    size_t len;
    const char *trimmed = trim(text, &len);
    if (len == 0) {
        return true;
    }
    if (matches_filler(trimmed, len)) {
        return true;
    }
    /* Count meaningful characters (UTF-8 code points that are not space or ASCII punctuation). UTF-8 continuation
     * bytes (10xxxxxx) are skipped so each code point counts once */
    unsigned meaningful = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)trimmed[i];
        if ((c & 0xC0) == 0x80) {
            continue;   /* UTF-8 continuation byte: part of the previous code point */
        }
        if (c < 0x80 && is_ascii_filler_char(c)) {
            continue;
        }
        meaningful++;
    }
    return meaningful <= 2;
}

void saver_text_split_sentences(const char *text, saver_sentence_cb_t cb, void *ctx)
{
    if (!text || !cb) {
        return;
    }
    size_t start = 0, n = strlen(text);
    for (size_t i = 0; i <= n; i++) {
        bool boundary = i == n || text[i] == '.' || text[i] == '!' || text[i] == '?' || text[i] == '\n';
        if (!boundary) {
            continue;
        }
        size_t end = i < n ? i + 1 : i;   /* sentence-ending punctuation stays in the sentence */
        /* Skip leading and trailing spaces */
        size_t s = start;
        while (s < end && is_ascii_space((unsigned char)text[s])) {
            s++;
        }
        size_t e = end;
        while (e > s && is_ascii_space((unsigned char)text[e - 1])) {
            e--;
        }
        if (e > s) {
            cb(text + s, e - s, ctx);
        }
        start = end;
    }
}

/* ── Self-test ───────────────────────────────────────────── */

typedef struct {
    unsigned count;
    size_t lens[8];
    char first[64];
} split_capture_t;

static void capture_cb(const char *s, size_t len, void *ctx)
{
    split_capture_t *c = ctx;
    if (c->count < 8) {
        c->lens[c->count] = len;
    }
    if (c->count == 0) {
        size_t n = len < sizeof(c->first) - 1 ? len : sizeof(c->first) - 1;
        memcpy(c->first, s, n);
        c->first[n] = '\0';
    }
    c->count++;
}

bool saver_text_selftest(void)
{
    bool ok = true;

    ok &= saver_text_is_noise("");
    ok &= saver_text_is_noise("   ");
    ok &= saver_text_is_noise("A");           /* 1 character */
    ok &= saver_text_is_noise("Hm.");         /* 2 characters */
    ok &= saver_text_is_noise("  Thank you.  ");
    ok &= saver_text_is_noise("Thank you for watching.");
    ok &= saver_text_is_noise("Thanks for watching!");
    ok &= saver_text_is_noise("Thank you.");
    ok &= saver_text_is_noise("Bye.");
    ok &= !saver_text_is_noise("Thank you for watching the oven");  /* whole utterance only, never a substring */
    ok &= !saver_text_is_noise("Bye computer");                     /* hang-up phrase, not noise */
    ok &= !saver_text_is_noise("What's the weather tomorrow?");    /* meaningful question */
    ok &= !saver_text_is_noise("Yes");                              /* 3 characters, not in the list */
    ok &= saver_text_is_noise(NULL);                     /* NULL counts as noise */

    split_capture_t c = {0};
    saver_text_split_sentences("It's sunny today. It will rain tomorrow! Did you pack an umbrella?", capture_cb, &c);
    ok &= c.count == 3;
    ok &= !strcmp(c.first, "It's sunny today.");

    split_capture_t c2 = {0};
    saver_text_split_sentences("  ", capture_cb, &c2);
    ok &= c2.count == 0;      /* empty chunks are skipped */

    split_capture_t c3 = {0};
    saver_text_split_sentences("One line, last sentence (no final period)", capture_cb, &c3);
    ok &= c3.count == 1;      /* the last chunk comes out even without a final period */

    return ok;
}
