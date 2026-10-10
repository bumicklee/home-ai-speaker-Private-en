/**
 * @file gemini_base64.h
 * @brief base64 encoding and decoding (pure logic, used for Gemini requests (audio) and responses (synthesized PCM))
 *
 * cJSON string values make their own copy, so the encoded text can be freed right after it is added. No ESP-IDF
 * dependency (like saver_endpoint.c, it compiles and tests directly on the Mac).
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Number of characters needed to encode in_len bytes (padding included, NUL excluded) */
size_t gemini_base64_encoded_len(size_t in_len);

/**
 * Writes in (in_len bytes) to out as standard base64 (RFC 4648, '+'/'/' alphabet, '=' padding). out_cap must be
 * at least gemini_base64_encoded_len(in_len) (the caller appends the NUL). Returns: characters written
 * (0 if out_cap is too small; nothing is written to out).
 */
size_t gemini_base64_encode(const uint8_t *in, size_t in_len, char *out, size_t out_cap);

/**
 * Decodes base64 text (in_len characters; newlines and spaces are skipped) into out. Returns: bytes written, or
 * SIZE_MAX if out_cap is too small or a character is invalid.
 */
size_t gemini_base64_decode(const char *in, size_t in_len, uint8_t *out, size_t out_cap);

bool gemini_base64_selftest(void);

#ifdef __cplusplus
}
#endif
