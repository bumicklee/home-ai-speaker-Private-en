/**
 * @file saver_text.h
 * @brief Saver mode transcription noise filter and sentence splitter (pure logic, docs/design-voice-saver-mode.md 11.6/5.2)
 *
 * Neither allocates memory (they only read the string or report chunk boundaries through a callback), so
 * they compile and test directly on the host, even without cJSON.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Is the transcription "meaningless": empty, 2 or fewer meaningful characters (excluding spaces and punctuation),
 * or (after trimming) exactly a noise phrase. If true, discard it and keep listening (avoids cost and off-target replies).
 */
bool saver_text_is_noise(const char *text);

typedef void (*saver_sentence_cb_t)(const char *sentence, size_t len, void *ctx);

/**
 * Splits text into sentences (after ". ", "!", "?", or a newline) and calls cb. Leading spaces in a sentence are skipped,
 * and empty chunks are skipped. Each sentence points into text (no copy) and is not NUL-terminated, so use len.
 */
void saver_text_split_sentences(const char *text, saver_sentence_cb_t cb, void *ctx);

bool saver_text_selftest(void);

#ifdef __cplusplus
}
#endif
