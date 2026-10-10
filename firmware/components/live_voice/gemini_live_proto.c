/* See gemini_live_proto.h. Uses nothing but cJSON and gemini_base64 (test it directly on the Mac) */
#include "gemini_live_proto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gemini_base64.h"

static void add_text_part(cJSON *parts, const char *text)
{
    cJSON *part = cJSON_CreateObject();
    cJSON_AddStringToObject(part, "text", text);
    cJSON_AddItemToArray(parts, part);
}

char *gemini_live_build_setup(const char *model, const char *voice, const char *instructions,
                              const cJSON *tools_decls, bool search)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *setup = cJSON_AddObjectToObject(root, "setup");
    char full_model[96];
    if (model && strncmp(model, "models/", 7)) {
        snprintf(full_model, sizeof(full_model), "models/%s", model);
        cJSON_AddStringToObject(setup, "model", full_model);
    } else {
        cJSON_AddStringToObject(setup, "model", model ? model : "");
    }
    cJSON *gen = cJSON_AddObjectToObject(setup, "generationConfig");
    cJSON *modalities = cJSON_AddArrayToObject(gen, "responseModalities");
    cJSON_AddItemToArray(modalities, cJSON_CreateString("AUDIO"));
    if (voice && voice[0]) {
        cJSON *speech = cJSON_AddObjectToObject(gen, "speechConfig");
        cJSON *vc = cJSON_AddObjectToObject(speech, "voiceConfig");
        cJSON *pvc = cJSON_AddObjectToObject(vc, "prebuiltVoiceConfig");
        cJSON_AddStringToObject(pvc, "voiceName", voice);
    }
    if (instructions && instructions[0]) {
        cJSON *sys = cJSON_AddObjectToObject(setup, "systemInstruction");
        cJSON *parts = cJSON_AddArrayToObject(sys, "parts");
        add_text_part(parts, instructions);
    }
    bool have_decls = tools_decls && cJSON_IsArray(tools_decls) && cJSON_GetArraySize(tools_decls) > 0;
    if (have_decls || search) {
        cJSON *tools = cJSON_AddArrayToObject(setup, "tools");
        if (have_decls) {
            cJSON *entry = cJSON_CreateObject();
            cJSON_AddItemToObject(entry, "functionDeclarations", cJSON_Duplicate(tools_decls, true));
            cJSON_AddItemToArray(tools, entry);
        }
        if (search) {
            cJSON *entry = cJSON_CreateObject();
            cJSON_AddObjectToObject(entry, "googleSearch");
            cJSON_AddItemToArray(tools, entry);
        }
    }
    /* hang-up phrases, the TLG-14 user-utterance signal and the conversation log need the transcribed text (same reason as Section 16.5) */
    cJSON_AddObjectToObject(setup, "inputAudioTranscription");
    cJSON_AddObjectToObject(setup, "outputAudioTranscription");
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

char *gemini_live_build_audio_chunk(const int16_t *pcm, size_t sample_count)
{
    size_t pcm_bytes = sample_count * sizeof(int16_t);
    size_t b64_cap = gemini_base64_encoded_len(pcm_bytes) + 1;
    char *b64 = malloc(b64_cap);
    if (!b64) {
        return NULL;
    }
    size_t n = gemini_base64_encode((const uint8_t *)pcm, pcm_bytes, b64, b64_cap);
    b64[n] = '\0';
    cJSON *root = cJSON_CreateObject();
    cJSON *ri = cJSON_AddObjectToObject(root, "realtimeInput");
    cJSON *audio = cJSON_AddObjectToObject(ri, "audio");
    cJSON_AddStringToObject(audio, "data", b64);
    cJSON_AddStringToObject(audio, "mimeType", "audio/pcm;rate=16000");
    free(b64);
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

char *gemini_live_build_client_text(const char *text_in)
{
    if (!text_in) {
        return NULL;
    }
    cJSON *root = cJSON_CreateObject();
    cJSON *cc = cJSON_AddObjectToObject(root, "clientContent");
    cJSON *turns = cJSON_AddArrayToObject(cc, "turns");
    cJSON *turn = cJSON_CreateObject();
    cJSON_AddStringToObject(turn, "role", "user");
    cJSON *parts = cJSON_AddArrayToObject(turn, "parts");
    add_text_part(parts, text_in);
    cJSON_AddItemToArray(turns, turn);
    cJSON_AddBoolToObject(cc, "turnComplete", true);
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

char *gemini_live_build_tool_response(cJSON *responses)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *tr = cJSON_AddObjectToObject(root, "toolResponse");
    if (responses) {
        cJSON_AddItemToObject(tr, "functionResponses", responses);
    } else {
        cJSON_AddArrayToObject(tr, "functionResponses");
    }
    char *text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return text;
}

bool gemini_live_is_setup_complete(const cJSON *root)
{
    return cJSON_HasObjectItem(root, "setupComplete");
}

const cJSON *gemini_live_server_content(const cJSON *root)
{
    return cJSON_GetObjectItemCaseSensitive(root, "serverContent");
}

bool gemini_live_is_interrupted(const cJSON *content)
{
    return cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(content, "interrupted"));
}

bool gemini_live_is_turn_complete(const cJSON *content)
{
    return cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(content, "turnComplete"));
}

const char *gemini_live_transcript_text(const cJSON *content, bool input)
{
    const cJSON *holder = cJSON_GetObjectItemCaseSensitive(content, input ? "inputTranscription" : "outputTranscription");
    const cJSON *text = cJSON_GetObjectItemCaseSensitive(holder, "text");
    return cJSON_IsString(text) && text->valuestring[0] ? text->valuestring : NULL;
}

const char *gemini_live_find_inline_audio(const cJSON *content, size_t *len_out)
{
    const cJSON *model_turn = cJSON_GetObjectItemCaseSensitive(content, "modelTurn");
    const cJSON *parts = cJSON_GetObjectItemCaseSensitive(model_turn, "parts");
    const cJSON *part;
    cJSON_ArrayForEach(part, parts) {
        const cJSON *inline_data = cJSON_GetObjectItemCaseSensitive(part, "inlineData");
        const cJSON *data = cJSON_GetObjectItemCaseSensitive(inline_data, "data");
        if (cJSON_IsString(data) && data->valuestring[0]) {
            if (len_out) {
                *len_out = strlen(data->valuestring);
            }
            return data->valuestring;
        }
    }
    return NULL;
}

const cJSON *gemini_live_tool_calls(const cJSON *root)
{
    const cJSON *tool_call = cJSON_GetObjectItemCaseSensitive(root, "toolCall");
    const cJSON *calls = cJSON_GetObjectItemCaseSensitive(tool_call, "functionCalls");
    return cJSON_IsArray(calls) ? calls : NULL;
}

const cJSON *gemini_live_cancelled_ids(const cJSON *root)
{
    const cJSON *cancel = cJSON_GetObjectItemCaseSensitive(root, "toolCallCancellation");
    const cJSON *ids = cJSON_GetObjectItemCaseSensitive(cancel, "ids");
    return cJSON_IsArray(ids) ? ids : NULL;
}

bool gemini_live_is_goaway(const cJSON *root)
{
    return cJSON_HasObjectItem(root, "goAway");
}

/* ── Self-test ───────────────────────────────────────────── */

bool gemini_live_proto_selftest(void)
{
    bool ok = true;

    /* setup: prepend "models/" to model, omit voice (empty string), both tools and search */
    cJSON *decls = cJSON_Parse("[{\"name\":\"radio_play\",\"parameters\":{\"type\":\"OBJECT\",\"properties\":{}}}]");
    char *setup_text = gemini_live_build_setup("gemini-3.8-live", "Kore", "be brief", decls, true);
    cJSON *setup_json = cJSON_Parse(setup_text ? setup_text : "");
    cJSON *setup = cJSON_GetObjectItemCaseSensitive(setup_json, "setup");
    ok &= setup_text && setup_json && setup;
    ok &= setup && !strcmp(cJSON_GetObjectItemCaseSensitive(setup, "model")->valuestring, "models/gemini-3.8-live");
    cJSON *gen = cJSON_GetObjectItemCaseSensitive(setup, "generationConfig");
    ok &= gen && !strcmp(cJSON_GetArrayItem(cJSON_GetObjectItemCaseSensitive(gen, "responseModalities"), 0)->valuestring,
                         "AUDIO");
    cJSON *voice_name = cJSON_GetObjectItemCaseSensitive(
        cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(gen, "speechConfig"), "voiceConfig"),
        "prebuiltVoiceConfig");
    ok &= voice_name && !strcmp(cJSON_GetObjectItemCaseSensitive(voice_name, "voiceName")->valuestring, "Kore");
    cJSON *tools = cJSON_GetObjectItemCaseSensitive(setup, "tools");
    ok &= tools && cJSON_GetArraySize(tools) == 2;    /* functionDeclarations + googleSearch */
    bool have_fd = false, have_search = false;
    const cJSON *t;
    cJSON_ArrayForEach(t, tools) {
        if (cJSON_GetObjectItemCaseSensitive(t, "functionDeclarations")) have_fd = true;
        if (cJSON_HasObjectItem(t, "googleSearch")) have_search = true;
    }
    ok &= have_fd && have_search;
    ok &= cJSON_HasObjectItem(setup, "inputAudioTranscription") && cJSON_HasObjectItem(setup, "outputAudioTranscription");
    cJSON_Delete(decls);
    cJSON_Delete(setup_json);
    free(setup_text);

    /* model already "models/..." → don't prepend; voice NULL → no speechConfig; no tools → no tools */
    char *setup2 = gemini_live_build_setup("models/gemini-3.8-live", NULL, "x", NULL, false);
    cJSON *setup2_json = cJSON_Parse(setup2 ? setup2 : "");
    cJSON *setup2_s = cJSON_GetObjectItemCaseSensitive(setup2_json, "setup");
    ok &= setup2_s && !strcmp(cJSON_GetObjectItemCaseSensitive(setup2_s, "model")->valuestring, "models/gemini-3.8-live");
    ok &= !cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(setup2_s, "generationConfig"), "speechConfig");
    ok &= !cJSON_GetObjectItemCaseSensitive(setup2_s, "tools");
    cJSON_Delete(setup2_json);
    free(setup2);

    /* audio chunk: realtimeInput.audio.data is base64 (decodes to the original PCM), check mimeType */
    int16_t pcm[4] = {1, -1, 1000, -1000};
    char *audio_text = gemini_live_build_audio_chunk(pcm, 4);
    cJSON *audio_json = cJSON_Parse(audio_text ? audio_text : "");
    cJSON *audio = cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(audio_json, "realtimeInput"), "audio");
    ok &= audio && !strcmp(cJSON_GetObjectItemCaseSensitive(audio, "mimeType")->valuestring, "audio/pcm;rate=16000");
    const char *b64 = audio ? cJSON_GetObjectItemCaseSensitive(audio, "data")->valuestring : "";
    uint8_t decoded[8];
    size_t dn = gemini_base64_decode(b64, strlen(b64), decoded, sizeof(decoded));
    ok &= dn == 8 && !memcmp(decoded, pcm, 8);
    cJSON_Delete(audio_json);
    free(audio_text);

    /* text sent by the device (clientContent) */
    char *ct_text = gemini_live_build_client_text("hello");
    cJSON *ct_json = cJSON_Parse(ct_text ? ct_text : "");
    cJSON *cc = cJSON_GetObjectItemCaseSensitive(ct_json, "clientContent");
    ok &= cc && cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(cc, "turnComplete"));
    cJSON *turn0 = cJSON_GetArrayItem(cJSON_GetObjectItemCaseSensitive(cc, "turns"), 0);
    ok &= turn0 && !strcmp(cJSON_GetObjectItemCaseSensitive(turn0, "role")->valuestring, "user");
    const cJSON *part0 = cJSON_GetArrayItem(cJSON_GetObjectItemCaseSensitive(turn0, "parts"), 0);
    ok &= part0 && !strcmp(cJSON_GetObjectItemCaseSensitive(part0, "text")->valuestring, "hello");
    cJSON_Delete(ct_json);
    free(ct_text);

    /* tool response */
    cJSON *responses = cJSON_CreateArray();
    cJSON *resp_item = cJSON_CreateObject();
    cJSON_AddStringToObject(resp_item, "id", "call-1");
    cJSON_AddStringToObject(resp_item, "name", "radio_play");
    cJSON_AddItemToObject(resp_item, "response", cJSON_Parse("{\"ok\":true}"));
    cJSON_AddItemToArray(responses, resp_item);
    char *tr_text = gemini_live_build_tool_response(responses);   /* takes ownership */
    cJSON *tr_json = cJSON_Parse(tr_text ? tr_text : "");
    cJSON *frs = cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(tr_json, "toolResponse"),
                                                  "functionResponses");
    ok &= frs && cJSON_GetArraySize(frs) == 1;
    ok &= !strcmp(cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(frs, 0), "id")->valuestring, "call-1");
    cJSON_Delete(tr_json);
    free(tr_text);

    /* reading server messages: setupComplete, serverContent (audio, transcription, interrupted), toolCall, cancellation, goAway */
    cJSON *sc_msg = cJSON_Parse("{\"setupComplete\":{}}");
    ok &= gemini_live_is_setup_complete(sc_msg);
    ok &= !gemini_live_server_content(sc_msg);
    cJSON_Delete(sc_msg);

    cJSON *content_msg = cJSON_Parse(
        "{\"serverContent\":{\"modelTurn\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"audio/pcm;rate=24000\","
        "\"data\":\"AQID\"}}]},\"turnComplete\":true,\"interrupted\":true,\"inputTranscription\":{\"text\":\"hi\"},"
        "\"outputTranscription\":{\"text\":\"hello\"}}}");
    const cJSON *content = gemini_live_server_content(content_msg);
    ok &= content && gemini_live_is_interrupted(content) && gemini_live_is_turn_complete(content);
    ok &= content && !strcmp(gemini_live_transcript_text(content, true), "hi");
    ok &= content && !strcmp(gemini_live_transcript_text(content, false), "hello");
    size_t audio_len = 0;
    const char *inline_b64 = gemini_live_find_inline_audio(content, &audio_len);
    ok &= inline_b64 && audio_len == 4 && !strcmp(inline_b64, "AQID");
    cJSON_Delete(content_msg);

    cJSON *empty_content_msg = cJSON_Parse("{\"serverContent\":{}}");
    ok &= !gemini_live_transcript_text(gemini_live_server_content(empty_content_msg), true);
    ok &= !gemini_live_find_inline_audio(gemini_live_server_content(empty_content_msg), &audio_len);
    cJSON_Delete(empty_content_msg);

    cJSON *tc_msg = cJSON_Parse("{\"toolCall\":{\"functionCalls\":[{\"id\":\"c1\",\"name\":\"radio_play\",\"args\":{}}]}}");
    const cJSON *calls = gemini_live_tool_calls(tc_msg);
    ok &= calls && cJSON_GetArraySize(calls) == 1;
    ok &= !strcmp(cJSON_GetObjectItemCaseSensitive(cJSON_GetArrayItem(calls, 0), "id")->valuestring, "c1");
    cJSON_Delete(tc_msg);

    cJSON *cancel_msg = cJSON_Parse("{\"toolCallCancellation\":{\"ids\":[\"c1\",\"c2\"]}}");
    const cJSON *ids = gemini_live_cancelled_ids(cancel_msg);
    ok &= ids && cJSON_GetArraySize(ids) == 2;
    cJSON_Delete(cancel_msg);

    cJSON *goaway_msg = cJSON_Parse("{\"goAway\":{\"timeLeft\":\"10s\"}}");
    ok &= gemini_live_is_goaway(goaway_msg);
    cJSON_Delete(goaway_msg);

    cJSON *plain_msg = cJSON_Parse("{\"serverContent\":{}}");
    ok &= !gemini_live_is_goaway(plain_msg) && !gemini_live_is_setup_complete(plain_msg) &&
          !gemini_live_tool_calls(plain_msg) && !gemini_live_cancelled_ids(plain_msg);
    cJSON_Delete(plain_msg);

    return ok;
}
