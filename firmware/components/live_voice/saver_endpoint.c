#include "saver_endpoint.h"

#include <stddef.h>

void saver_endpoint_reset(saver_endpoint_t *ep)
{
    ep->in_speech = false;
    ep->speech_started_ms = 0;
    ep->last_speech_ms = 0;
}

saver_endpoint_result_t saver_endpoint_feed(saver_endpoint_t *ep, bool speech, uint32_t now_ms, bool *started_out)
{
    if (started_out) {
        *started_out = false;
    }
    if (!ep->in_speech) {
        if (!speech) {
            return SAVER_EP_CONTINUE;
        }
        ep->in_speech = true;
        ep->speech_started_ms = now_ms;
        ep->last_speech_ms = now_ms;
        if (started_out) {
            *started_out = true;
        }
        return SAVER_EP_CONTINUE;
    }
    if (speech) {
        ep->last_speech_ms = now_ms;
    }
    if (now_ms - ep->speech_started_ms >= SAVER_EP_MAX_UTTERANCE_MS) {
        return SAVER_EP_END_MAXLEN;
    }
    if (now_ms - ep->last_speech_ms >= SAVER_EP_SILENCE_END_MS) {
        return SAVER_EP_END_SILENCE;
    }
    return SAVER_EP_CONTINUE;
}

/* ── Self-test ───────────────────────────────────────────── */

bool saver_endpoint_selftest(void)
{
    bool ok = true;
    saver_endpoint_t ep;
    bool started;

    /* If only silence continues, there is no start and no end */
    saver_endpoint_reset(&ep);
    for (uint32_t t = 0; t < 5000; t += 20) {
        ok &= saver_endpoint_feed(&ep, false, t, &started) == SAVER_EP_CONTINUE;
        ok &= !started;
    }
    ok &= !ep.in_speech;

    /* When speech starts, started=true; continued speech after that gives CONTINUE */
    saver_endpoint_reset(&ep);
    ok &= saver_endpoint_feed(&ep, true, 1000, &started) == SAVER_EP_CONTINUE;
    ok &= started;
    ok &= saver_endpoint_feed(&ep, true, 1020, &started) == SAVER_EP_CONTINUE;
    ok &= !started;        /* The second call is not a "start" */

    /* 0.69 s of silence is not the end yet; at 0.70 s it ends */
    saver_endpoint_reset(&ep);
    saver_endpoint_feed(&ep, true, 0, &started);
    ok &= saver_endpoint_feed(&ep, false, 690, NULL) == SAVER_EP_CONTINUE;
    ok &= saver_endpoint_feed(&ep, false, 700, NULL) == SAVER_EP_END_SILENCE;

    /* Speaking again midway resets the silence time */
    saver_endpoint_reset(&ep);
    saver_endpoint_feed(&ep, true, 0, NULL);
    ok &= saver_endpoint_feed(&ep, false, 500, NULL) == SAVER_EP_CONTINUE;
    ok &= saver_endpoint_feed(&ep, true, 690, NULL) == SAVER_EP_CONTINUE;    /* speaks again */
    ok &= saver_endpoint_feed(&ep, false, 1000, NULL) == SAVER_EP_CONTINUE; /* 690+700=1390, so not yet */
    ok &= saver_endpoint_feed(&ep, false, 1390, NULL) == SAVER_EP_END_SILENCE;

    /* Speaking 30 seconds without a pause gives MAXLEN (it must come before a silence end) */
    saver_endpoint_reset(&ep);
    saver_endpoint_feed(&ep, true, 0, NULL);
    saver_endpoint_result_t last = SAVER_EP_CONTINUE;
    for (uint32_t t = 20; t <= 30000; t += 20) {
        last = saver_endpoint_feed(&ep, true, t, NULL);
        if (last != SAVER_EP_CONTINUE) {
            break;
        }
    }
    ok &= last == SAVER_EP_END_MAXLEN;

    return ok;
}
