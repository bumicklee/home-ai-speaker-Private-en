/**
 * @file gemini_schema.h
 * @brief Convert OpenAI Responses-format function tools → Gemini functionDeclarations (docs/design-voice-saver-mode.md stage 2)
 *
 * build_saver_tools() in assistant.c returns the same OpenAI Responses format as Live mode and OpenAI Saver mode
 * ({"type":"function","name":...,"strict":true,"parameters":{...,"type":["string","null"], ...}}).
 * Gemini generateContent's tools[].functionDeclarations uses an OpenAPI-subset Schema that differs in a few ways
 * (already summarized in the earlier "Gemini tool review" in docs/design-voice-saver-mode.md, checked on ai.google.dev 2026-10):
 *   - type is a single string, not an array. Gemini rejects nullable unions such as ["string","null"]
 *     (FunctionDeclaration.parameters is OpenAPI-based, so type is a scalar enum) → type becomes one uppercase value;
 *     if "null" is mixed in, add nullable:true and remove that name from required.
 *   - "strict" and "additionalProperties" are not fields in the Gemini Schema, so they are dropped.
 *   - enum can be used only for strings (sending an integer enum as is gets rejected). An integer enum becomes type INTEGER +
 *     minimum/maximum, and the exact allowed values are written at the end of description to guide the model to pick
 *     only those values within the range (not enforced).
 *   - maxItems/minItems etc. are protobuf int64 fields (json:",string") in Gemini's Schema, so sending them as strings
 *     is safe across all implementations (both are often accepted, but the string is the official form).
 *   - A function with no arguments (empty properties) drops "parameters" entirely.
 * This file uses only cJSON (like tool_guard.c, it compiles and tests directly on the Mac; no ESP-IDF dependency).
 */
#pragma once

#include <stdbool.h>
#include "cJSON.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Converts an OpenAI Responses tool array (what assistant_build_saver_tools() returns; non-function entries such as
 * web_search are skipped) into a Gemini functionDeclarations array. Returns a new cJSON array (caller does cJSON_Delete);
 * the input is not changed. Empty array if openai_tools is NULL or not an array.
 */
cJSON *gemini_schema_convert_tools(const cJSON *openai_tools);

/**
 * Converts one schema node (a function's parameters, or a property/items inside it). convert_tools uses it recursively,
 * and the self-test uses it directly. Returns a new cJSON (caller does cJSON_Delete).
 */
cJSON *gemini_schema_convert_node(const cJSON *openai_node);

bool gemini_schema_selftest(void);

#ifdef __cplusplus
}
#endif
