/* Based on waveshare-ai-speaker-assistant (MIT, Copyright (c) 2026 KMX415). See THIRD_PARTY_NOTICES.md. */
/**
 * @file live_voice.h
 * @brief OpenAI gpt-live-1 voice session (design doc Section 2.8, ported from the original firmware's live_voice.c)
 *
 * Flow: check Wi-Fi -> check time (RTC first) -> WSS connect -> session.start -> mic upload loop
 *       -> session.close. State is reported with APP_EVT_VOICE_STATE (voice_state_t).
 *
 * This module does not run tools. When a function call is complete in a delegation response,
 * it is handed to the on_tool_calls handler (the assistant's tool worker), and the result comes back through
 * live_voice_submit_tool_outputs(). The upload loop does not stop meanwhile.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "app_events.h"
#include "cJSON.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    /** Builds the session.start JSON string (caller frees it) */
    char *(*build_start_event)(void);
    /** Array of completed function_call items. Ownership is transferred. Called from the receive task, so must not block */
    void (*on_tool_calls)(cJSON *calls, unsigned generation);
    /** About every 20ms from the session loop (drives mic calibration) */
    void (*on_tick)(void);
    /** When the session ends */
    void (*on_session_end)(void);
    /** On user input: an input transcript fragment or live_voice_text (TLG-14, for send confirmation) */
    void (*on_user_input)(void);
    /** Transcript fragment (from_user: the user's speech, otherwise the assistant's). Called from the receive task, so must not block */
    void (*on_transcript)(bool from_user, const char *delta);

    /*
     * AI choice and Live/Saver mode (docs/design-voice-saver-mode.md 11.5). live_voice does not read settings itself;
     * it talks to the assistant only through these handlers (assistant REQUIRES live_voice, so not the other way).
     */
    /** If true, use openai.live regardless of settings (English lesson; Telegram auto-read is a stage 1 TODO) */
    bool (*force_openai_live)(void);
    /** When a Saver mode session just starts (before listening). Same as guard_reset() etc. done by Live mode's assistant_start_event */
    void (*on_session_start)(void);
    /**
     * Saver mode instructions (including speaking briefly). Caller frees. Fills voice_out with the stored voice name
     * (assistant settings). If gemini is true, the web search line becomes "none" (Gemini Saver mode gets no search tool,
     * docs/design-voice-saver-mode.md stage 2 decision 5); the rest of the instructions is the same for either provider
     */
    char *(*build_saver_instructions)(bool gemini, char *voice_out, size_t voice_cap);
    /** Saver mode tool array (Responses format, same schema as delegation.responses.tools). Caller does cJSON_Delete */
    cJSON *(*build_saver_tools)(void);
    /** Run one tool (assistant_execute as is, including tool_guard). Caller does cJSON_Delete */
    cJSON *(*execute_tool)(const char *name, const char *arguments);
    /**
     * Gemini Live (stage 3) instructions: merges the live conversation rules and tool rules into one and rewrites
     * "delegate to the backend" as "call directly" (Gemini Live has no backend delegation, docs/design-voice-saver-mode.md 2.5, 16.4).
     * Fills voice_out with the voice name from assistant settings (gemini_live.c maps it to a Gemini voice,
     * reusing gemini_tts_voice from saver_voice.h). search_out says whether to give the Google Search (googleSearch) tool
     * along with the function declarations (follows the web_search setting; per the docs, Gemini Live, unlike Saver mode's
     * generateContent REST, can use function declarations and search together). Caller frees
     */
    char *(*build_gemini_live_instructions)(char *voice_out, size_t voice_cap, bool *search_out);
} live_voice_handlers_t;

esp_err_t live_voice_init(void);
void      live_voice_set_handlers(const live_voice_handlers_t *handlers);

/**
 * Start a conversation. ESP_ERR_INVALID_STATE if one is already running. Depending on settings (ai_provider, mode_openai, mode_gemini)
 * it takes one of four paths: openai.live (gpt-live-1), openai.saver, gemini.saver, gemini.live (stage 3, Gemini Live API)
 * (docs/design-voice-saver-mode.md 11.5, 16.4). Without a key for the selected provider: ESP_ERR_INVALID_STATE (+APP_ERR_NO_API_KEY).
 */
esp_err_t live_voice_start(void);
void      live_voice_stop(void);
/**
 * Short press of Key2. In Saver mode while the assistant is speaking, only playback stops and listening continues (the conversation does not end,
 * Section 11.5 "barge-in"). Otherwise (Live mode, or Saver mode while not speaking) it is the same as live_voice_stop().
 */
void      live_voice_barge_in(void);

bool          live_voice_active(void);      /* session task is alive */
bool          live_voice_ready(void);       /* after session.started, before a stop request */
voice_state_t live_voice_state(void);
/** Last status text (fixed string, for diagnostics) */
const char   *live_voice_status(void);
/** Current session number. Used to make sure tool results don't go to an earlier session */
unsigned      live_voice_generation(void);

/**
 * Time limits (ms) for the next session only. 0 means the default (10 minutes max, 60-second idle timeout).
 * Call before live_voice_start() (English lesson)
 */
void      live_voice_set_next_limits(uint32_t max_ms, uint32_t idle_ms);

/** Append an instruction for the model (mic calibration guidance etc.) */
bool      live_voice_instruction(const char *text);
/** Send a user message as text (up to 600 bytes) */
esp_err_t live_voice_text(const char *text);

/**
 * Send tool results. outputs is an array of {"call_id": "...", "output": "<JSON string>"}
 * and ownership is transferred. After sending them all, sends response.create.
 */
esp_err_t live_voice_submit_tool_outputs(cJSON *outputs, unsigned generation);

/**
 * Pure-logic self-test for Saver mode + Gemini (Saver and Live). 0x3F on pass (bit0 endpoint, bit1 text,
 * bit2 resample, bit3 gemini_schema, bit4 gemini_base64, bit5 gemini_live_proto).
 * docs/design-voice-saver-mode.md 11.9, 16.5; stage 3 (Gemini Live).
 */
unsigned saver_voice_selftest(void);

#ifdef __cplusplus
}
#endif
