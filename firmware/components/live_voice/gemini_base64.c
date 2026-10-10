/* See gemini_base64.h. No ESP-IDF dependency (test it directly on the Mac) */
#include "gemini_base64.h"

#include <string.h>

static const char ENC_TABLE[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t gemini_base64_encoded_len(size_t in_len)
{
    return ((in_len + 2) / 3) * 4;
}

size_t gemini_base64_encode(const uint8_t *in, size_t in_len, char *out, size_t out_cap)
{
    size_t need = gemini_base64_encoded_len(in_len);
    if (out_cap < need) {
        return 0;
    }
    size_t oi = 0;
    size_t i = 0;
    for (; i + 3 <= in_len; i += 3) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
        out[oi++] = ENC_TABLE[(v >> 18) & 0x3F];
        out[oi++] = ENC_TABLE[(v >> 12) & 0x3F];
        out[oi++] = ENC_TABLE[(v >> 6) & 0x3F];
        out[oi++] = ENC_TABLE[v & 0x3F];
    }
    size_t rem = in_len - i;
    if (rem == 1) {
        uint32_t v = (uint32_t)in[i] << 16;
        out[oi++] = ENC_TABLE[(v >> 18) & 0x3F];
        out[oi++] = ENC_TABLE[(v >> 12) & 0x3F];
        out[oi++] = '=';
        out[oi++] = '=';
    } else if (rem == 2) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8);
        out[oi++] = ENC_TABLE[(v >> 18) & 0x3F];
        out[oi++] = ENC_TABLE[(v >> 12) & 0x3F];
        out[oi++] = ENC_TABLE[(v >> 6) & 0x3F];
        out[oi++] = '=';
    }
    return oi;
}

static int dec_value(char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

size_t gemini_base64_decode(const char *in, size_t in_len, uint8_t *out, size_t out_cap)
{
    size_t oi = 0;
    int vals[4];
    int n = 0;
    for (size_t i = 0; i < in_len; i++) {
        char c = in[i];
        if (c == '\r' || c == '\n' || c == ' ' || c == '\t') {
            continue;
        }
        if (c == '=') {
            break;      /* padding: stop here */
        }
        int v = dec_value(c);
        if (v < 0) {
            return (size_t)-1;
        }
        vals[n++] = v;
        if (n == 4) {
            if (oi + 3 > out_cap) {
                return (size_t)-1;
            }
            out[oi++] = (uint8_t)((vals[0] << 2) | (vals[1] >> 4));
            out[oi++] = (uint8_t)((vals[1] << 4) | (vals[2] >> 2));
            out[oi++] = (uint8_t)((vals[2] << 6) | vals[3]);
            n = 0;
        }
    }
    if (n == 2) {
        if (oi + 1 > out_cap) {
            return (size_t)-1;
        }
        out[oi++] = (uint8_t)((vals[0] << 2) | (vals[1] >> 4));
    } else if (n == 3) {
        if (oi + 2 > out_cap) {
            return (size_t)-1;
        }
        out[oi++] = (uint8_t)((vals[0] << 2) | (vals[1] >> 4));
        out[oi++] = (uint8_t)((vals[1] << 4) | (vals[2] >> 2));
    } else if (n == 1) {
        return (size_t)-1;     /* a single leftover character is invalid base64 */
    }
    return oi;
}

bool gemini_base64_selftest(void)
{
    bool ok = true;
    char buf[64];

    /* RFC 4648 standard test vectors */
    ok &= gemini_base64_encode((const uint8_t *)"", 0, buf, sizeof(buf)) == 0;
    size_t n = gemini_base64_encode((const uint8_t *)"f", 1, buf, sizeof(buf));
    ok &= n == 4 && !memcmp(buf, "Zg==", 4);
    n = gemini_base64_encode((const uint8_t *)"fo", 2, buf, sizeof(buf));
    ok &= n == 4 && !memcmp(buf, "Zm8=", 4);
    n = gemini_base64_encode((const uint8_t *)"foo", 3, buf, sizeof(buf));
    ok &= n == 4 && !memcmp(buf, "Zm9v", 4);
    n = gemini_base64_encode((const uint8_t *)"foobar", 6, buf, sizeof(buf));
    ok &= n == 8 && !memcmp(buf, "Zm9vYmFy", 8);

    uint8_t dec[16];
    size_t dn = gemini_base64_decode("Zm9vYmFy", 8, dec, sizeof(dec));
    ok &= dn == 6 && !memcmp(dec, "foobar", 6);
    dn = gemini_base64_decode("Zg==", 4, dec, sizeof(dec));
    ok &= dn == 1 && dec[0] == 'f';
    dn = gemini_base64_decode("Zm8=", 4, dec, sizeof(dec));
    ok &= dn == 2 && !memcmp(dec, "fo", 2);

    /* newlines and spaces are skipped */
    dn = gemini_base64_decode("Zm9v\nYmFy", 9, dec, sizeof(dec));
    ok &= dn == 6 && !memcmp(dec, "foobar", 6);

    /* invalid characters fail */
    dn = gemini_base64_decode("Zg!=", 4, dec, sizeof(dec));
    ok &= dn == (size_t)-1;

    /* round trip: arbitrary bytes */
    uint8_t raw[37];
    for (unsigned i = 0; i < sizeof(raw); i++) {
        raw[i] = (uint8_t)(i * 7 + 3);
    }
    char enc[64];
    size_t enc_n = gemini_base64_encode(raw, sizeof(raw), enc, sizeof(enc));
    ok &= enc_n == gemini_base64_encoded_len(sizeof(raw));
    uint8_t back[37];
    size_t back_n = gemini_base64_decode(enc, enc_n, back, sizeof(back));
    ok &= back_n == sizeof(raw) && !memcmp(raw, back, sizeof(raw));

    /* fails if the buffer is too small */
    char tiny[2];
    ok &= gemini_base64_encode((const uint8_t *)"foo", 3, tiny, sizeof(tiny)) == 0;
    ok &= gemini_base64_decode("Zm9vYmFy", 8, back, 3) == (size_t)-1;

    return ok;
}
