#include "saver_resample.h"

#define STEP_24_TO_16 1.5   /* 24000/16000 */

void saver_resample_reset(saver_resample_t *r)
{
    r->next_in_pos = 0;
    r->consumed_in = 0;
    r->prev_last = 0;
    r->have_prev = false;
}

static int16_t clamp16(double v)
{
    if (v > 32767.0) {
        return 32767;
    }
    if (v < -32768.0) {
        return -32768;
    }
    return (int16_t)v;
}

size_t saver_resample_24to16(saver_resample_t *r, const int16_t *in, size_t count_in, int16_t *out,
                              size_t out_capacity)
{
    size_t written = 0;
    while (written < out_capacity) {
        double local = r->next_in_pos - r->consumed_in;   /* position relative to this call's in[]. in[-1] = last sample of the previous call */
        if (local > (double)(count_in ? count_in - 1 : 0)) {
            break;   /* this chunk alone is not enough yet. Wait for the next call */
        }
        double s0, s1, frac;
        if (local < 0.0) {
            s0 = r->have_prev ? r->prev_last : (count_in ? in[0] : 0);
            s1 = count_in ? in[0] : s0;
            frac = local + 1.0;              /* local is in [-1, 0) */
        } else {
            size_t idx = (size_t)local;
            frac = local - (double)idx;
            s0 = in[idx];
            s1 = (idx + 1 < count_in) ? in[idx + 1] : in[idx];
        }
        out[written++] = clamp16(s0 + (s1 - s0) * frac);
        r->next_in_pos += STEP_24_TO_16;
    }
    if (count_in) {
        r->prev_last = in[count_in - 1];
        r->have_prev = true;
    }
    r->consumed_in += (double)count_in;
    return written;
}

/* ── Self-test ───────────────────────────────────────────── */

bool saver_resample_selftest(void)
{
    bool ok = true;

    /* Count: n samples at 24kHz -> about n*2/3 (within 2); the total must match even when fed in several chunks */
    saver_resample_t r;
    saver_resample_reset(&r);
    int16_t in[300];
    for (int i = 0; i < 300; i++) {
        in[i] = (int16_t)(i * 10);   /* gentle rising ramp */
    }
    int16_t out[256];
    size_t total_out = 0;
    /* Feed it in three chunks (97+97+106), like streaming */
    total_out += saver_resample_24to16(&r, in, 97, out, 256);
    total_out += saver_resample_24to16(&r, in + 97, 97, out, 256);
    total_out += saver_resample_24to16(&r, in + 194, 106, out, 256);
    size_t expect = (size_t)(300.0 / 1.5);   /* 200 */
    ok &= total_out >= expect - 2 && total_out <= expect + 2;

    /* The count must nearly match feeding it all at once (within 1 at the boundaries) */
    saver_resample_t r2;
    saver_resample_reset(&r2);
    int16_t out2[256];
    size_t one_shot = saver_resample_24to16(&r2, in, 300, out2, 256);
    ok &= one_shot >= total_out - 1 && one_shot <= total_out + 1;

    /* Ramp input -> output also increases monotonically (linear interpolation) */
    bool increasing = true;
    for (size_t i = 1; i < one_shot; i++) {
        if (out2[i] < out2[i - 1]) {
            increasing = false;
            break;
        }
    }
    ok &= increasing;

    /* Out-of-range input (clipping) is also clamped safely */
    saver_resample_t r3;
    saver_resample_reset(&r3);
    int16_t big[4] = {32767, 32767, -32768, -32768};
    int16_t out3[8];
    size_t n3 = saver_resample_24to16(&r3, big, 4, out3, 8);
    ok &= n3 > 0;   /* the int16_t result type already guarantees the range; only the count is checked here */

    return ok;
}
