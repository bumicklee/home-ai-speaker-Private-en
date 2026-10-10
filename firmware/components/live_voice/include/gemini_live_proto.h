/**
 * @file gemini_live_proto.h
 * @brief Building and parsing Gemini Live (BidiGenerateContent) WebSocket messages (pure logic, docs/design-voice-saver-mode.md stage 3)
 *
 * Only this file knows the message shapes (key names, nesting); gemini_live.c handles ESP-IDF and sockets. Uses only
 * cJSON and gemini_base64 (like gemini_schema.c and gemini_base64.c, it compiles and tests directly on the Mac; no ESP-IDF
 * dependency). Message shapes checked 2026-10 against ai.google.dev/api/live, /gemini-api/docs/live-api/get-started-websocket,
 * /gemini-api/docs/live-api/tools, /gemini-api/docs/live-api/capabilities:
 *   - client → server: {"setup":{...}} (first message), {"realtimeInput":{"audio":{"data":b64,
 *     "mimeType":"audio/pcm;rate=16000"}}}, {"clientContent":{"turns":[...],"turnComplete":true}},
 *     {"toolResponse":{"functionResponses":[{"id","name","response"}]}}
 *   - server → client: {"setupComplete":{}}, {"serverContent":{"modelTurn":{"parts":[{"inlineData":
 *     {"mimeType":"audio/pcm;rate=24000","data":b64}}]},"turnComplete":bool,"interrupted":bool,
 *     "inputTranscription":{"text":...},"outputTranscription":{"text":...}}},
 *     {"toolCall":{"functionCalls":[{"id","name","args"}]}}, {"toolCallCancellation":{"ids":[...]}},
 *     {"goAway":{"timeLeft":...}}
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "cJSON.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The first message ("setup"). model is a full name such as "models/gemini-3.8-live" (if the model name already has
 * "models/", it is used as is; otherwise this function prepends it). voice is a Gemini voice name (omitted if NULL or empty,
 * falling back to Gemini's default). tools_decls is the array from gemini_schema_convert_tools() (NULL or empty means no
 * function tools; contents are copied). If search is true, the built-in googleSearch tool is added with the function declarations (request 6:
 * the docs say the Live API can use both together, unlike the "drop it, it's a preview" decision for Saver mode, which uses
 * generateContent REST). inputAudioTranscription and outputAudioTranscription are always on (hang-up phrases,
 * TLG-14 and the conversation log need the transcribed text; same reason as Sections 11.6/16.5). Caller frees; NULL on failure.
 */
char *gemini_live_build_setup(const char *model, const char *voice, const char *instructions,
                               const cJSON *tools_decls, bool search);

/**
 * One mic chunk (realtimeInput.audio, 16-bit little-endian 16kHz PCM, mimeType "audio/pcm;rate=16000").
 * Caller frees; NULL on failure (out of memory).
 */
char *gemini_live_build_audio_chunk(const int16_t *pcm, size_t sample_count);

/**
 * Text sent by the device (clientContent, role "user", turnComplete true). Both live_voice_text() (reminders, auto-read) and
 * live_voice_instruction() (mic calibration guidance) send in this shape. Gemini Live has no dedicated "append to the
 * instructions" message like OpenAI's "session.instructions.append" (checked 2026-10), so it is sent as a user turn
 * (request 5 decision, documented). Caller frees; NULL on failure.
 */
char *gemini_live_build_client_text(const char *text);

/**
 * Tool result response (toolResponse.functionResponses[]). responses is an array the caller built ({"id","name",
 * "response"} objects, must not be empty); ownership passes to this function (it calls cJSON_Delete). Caller frees the
 * string; NULL on failure (responses is freed in that case too).
 */
char *gemini_live_build_tool_response(cJSON *responses);

/* ── Reading server messages (root is the cJSON_Parse result, owned by the caller. The functions below return pointers
 * straight into it without copying; use them only while root is alive) ───────────────────────── */

/** Is this a {"setupComplete":{}} message (true if the key is present, even with no fields) */
bool gemini_live_is_setup_complete(const cJSON *root);

/** serverContent object (NULL if absent) */
const cJSON *gemini_live_server_content(const cJSON *content_holder_root);

bool gemini_live_is_interrupted(const cJSON *content);
bool gemini_live_is_turn_complete(const cJSON *content);

/** Input (person, input=true) or output (assistant, input=false) transcription text (only when non-empty, otherwise NULL) */
const char *gemini_live_transcript_text(const cJSON *content, bool input);

/** Pointer and length of the first inlineData (base64 audio) text in modelTurn.parts[] (NULL if none) */
const char *gemini_live_find_inline_audio(const cJSON *content, size_t *len_out);

/** toolCall.functionCalls array (NULL if absent) */
const cJSON *gemini_live_tool_calls(const cJSON *root);

/** toolCallCancellation.ids array (NULL if absent) */
const cJSON *gemini_live_cancelled_ids(const cJSON *root);

/** Is this a goAway message (the server's notice that the connection will close soon) */
bool gemini_live_is_goaway(const cJSON *root);

bool gemini_live_proto_selftest(void);

#ifdef __cplusplus
}
#endif
