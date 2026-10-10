/* See gemini_schema.h. Uses nothing but cJSON (test it directly on the Mac) */
#include "gemini_schema.h"

#include <stdio.h>
#include <string.h>

/* OpenAI lowercase type → Gemini (OpenAPI subset) uppercase type */
static const char *upper_type(const char *t)
{
    if (!t) {
        return NULL;
    }
    if (!strcmp(t, "string")) return "STRING";
    if (!strcmp(t, "integer")) return "INTEGER";
    if (!strcmp(t, "number")) return "NUMBER";
    if (!strcmp(t, "boolean")) return "BOOLEAN";
    if (!strcmp(t, "object")) return "OBJECT";
    if (!strcmp(t, "array")) return "ARRAY";
    return NULL;    /* unknown type: not carried over (safer than having Gemini reject it) */
}

/* From {"type":"x"} or {"type":["x","null"]}, extract the actual type string and whether it is nullable */
static void read_type(const cJSON *node, const char **type_out, bool *nullable_out)
{
    *type_out = NULL;
    *nullable_out = false;
    const cJSON *type_item = cJSON_GetObjectItemCaseSensitive(node, "type");
    if (cJSON_IsString(type_item)) {
        *type_out = type_item->valuestring;
    } else if (cJSON_IsArray(type_item)) {
        const cJSON *t;
        cJSON_ArrayForEach(t, type_item) {
            if (!cJSON_IsString(t)) {
                continue;
            }
            if (!strcmp(t->valuestring, "null")) {
                *nullable_out = true;
            } else {
                *type_out = t->valuestring;
            }
        }
    }
}

/* Turn an integer enum (e.g. gain_db 0,3,6,...,36) into min/max + a note in description */
static void add_integer_enum_note(cJSON *dst, const cJSON *enum_arr)
{
    int lo = 0, hi = 0;
    bool first = true;
    char list[160] = "";
    size_t list_len = 0;
    const cJSON *v;
    cJSON_ArrayForEach(v, enum_arr) {
        if (!cJSON_IsNumber(v)) {
            continue;
        }
        int iv = v->valueint;
        if (first || iv < lo) {
            lo = iv;
        }
        if (first || iv > hi) {
            hi = iv;
        }
        first = false;
        if (list_len < sizeof(list) - 8) {
            list_len += (size_t)snprintf(list + list_len, sizeof(list) - list_len, "%s%d", list_len ? "," : "", iv);
        }
    }
    cJSON_AddNumberToObject(dst, "minimum", lo);
    cJSON_AddNumberToObject(dst, "maximum", hi);
    cJSON *desc = cJSON_GetObjectItemCaseSensitive(dst, "description");
    char combined[320];
    if (cJSON_IsString(desc) && desc->valuestring[0]) {
        snprintf(combined, sizeof(combined), "%s (allowed values: %s)", desc->valuestring, list);
    } else {
        snprintf(combined, sizeof(combined), "allowed values: %s", list);
    }
    if (desc) {
        cJSON_ReplaceItemInObjectCaseSensitive(dst, "description", cJSON_CreateString(combined));
    } else {
        cJSON_AddStringToObject(dst, "description", combined);
    }
}

/* Gemini's protobuf int64 fields such as maxItems/minItems are safest sent as strings, across all implementations */
static void copy_count_field_as_string(const cJSON *src, cJSON *dst, const char *key)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(src, key);
    if (cJSON_IsNumber(v)) {
        char buf[16];
        snprintf(buf, sizeof(buf), "%d", v->valueint);
        cJSON_AddStringToObject(dst, key, buf);
    } else if (cJSON_IsString(v)) {
        cJSON_AddStringToObject(dst, key, v->valuestring);
    }
}

cJSON *gemini_schema_convert_node(const cJSON *src)
{
    if (!cJSON_IsObject(src)) {
        return cJSON_CreateObject();
    }
    cJSON *dst = cJSON_CreateObject();
    if (!dst) {
        return NULL;
    }
    const cJSON *desc = cJSON_GetObjectItemCaseSensitive(src, "description");
    if (cJSON_IsString(desc)) {
        cJSON_AddStringToObject(dst, "description", desc->valuestring);
    }

    const char *type_str = NULL;
    bool nullable = false;
    read_type(src, &type_str, &nullable);
    const char *gemini_type = upper_type(type_str);

    const cJSON *enum_arr = cJSON_GetObjectItemCaseSensitive(src, "enum");
    bool enum_is_integer = cJSON_IsArray(enum_arr) && gemini_type && !strcmp(gemini_type, "INTEGER");
    if (gemini_type) {
        cJSON_AddStringToObject(dst, "type", gemini_type);
    }
    if (nullable) {
        cJSON_AddBoolToObject(dst, "nullable", true);
    }

    if (cJSON_IsArray(enum_arr) && enum_is_integer) {
        add_integer_enum_note(dst, enum_arr);  /* Gemini: enum only for strings. Integers become a range + a note */
    } else if (cJSON_IsArray(enum_arr)) {
        cJSON_AddItemToObject(dst, "enum", cJSON_Duplicate(enum_arr, true));  /* string enums pass through as is */
    }

    if (gemini_type && !strcmp(gemini_type, "OBJECT")) {
        const cJSON *props = cJSON_GetObjectItemCaseSensitive(src, "properties");
        const cJSON *required = cJSON_GetObjectItemCaseSensitive(src, "required");
        cJSON *out_props = cJSON_AddObjectToObject(dst, "properties");
        cJSON *out_required = cJSON_CreateArray();
        const cJSON *prop;
        cJSON_ArrayForEach(prop, props) {
            cJSON *converted = gemini_schema_convert_node(prop);
            bool prop_nullable = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(converted, "nullable"));
            cJSON_AddItemToObject(out_props, prop->string, converted);
            bool was_required = false;
            const cJSON *req_item;
            cJSON_ArrayForEach(req_item, required) {
                if (cJSON_IsString(req_item) && !strcmp(req_item->valuestring, prop->string)) {
                    was_required = true;
                }
            }
            if (was_required && !prop_nullable) {
                cJSON_AddItemToArray(out_required, cJSON_CreateString(prop->string));
            }
        }
        if (cJSON_GetArraySize(out_required)) {
            cJSON_AddItemToObject(dst, "required", out_required);
        } else {
            cJSON_Delete(out_required);
        }
        /* if properties is empty (a function with no arguments), the caller (convert_tools) drops "parameters" itself */
    } else if (gemini_type && !strcmp(gemini_type, "ARRAY")) {
        const cJSON *items = cJSON_GetObjectItemCaseSensitive(src, "items");
        cJSON *out_items = gemini_schema_convert_node(items);
        cJSON_AddItemToObject(dst, "items", out_items);
        copy_count_field_as_string(src, dst, "maxItems");
        copy_count_field_as_string(src, dst, "minItems");
    }
    return dst;
}

cJSON *gemini_schema_convert_tools(const cJSON *openai_tools)
{
    cJSON *out = cJSON_CreateArray();
    if (!out || !cJSON_IsArray(openai_tools)) {
        return out;
    }
    const cJSON *tool;
    cJSON_ArrayForEach(tool, openai_tools) {
        const cJSON *type = cJSON_GetObjectItemCaseSensitive(tool, "type");
        if (!cJSON_IsString(type) || strcmp(type->valuestring, "function")) {
            continue;   /* non-function tools such as web_search are not carried over to Gemini (Section 2.5: search is dropped) */
        }
        const cJSON *name = cJSON_GetObjectItemCaseSensitive(tool, "name");
        if (!cJSON_IsString(name)) {
            continue;
        }
        cJSON *decl = cJSON_CreateObject();
        cJSON_AddStringToObject(decl, "name", name->valuestring);
        const cJSON *desc = cJSON_GetObjectItemCaseSensitive(tool, "description");
        if (cJSON_IsString(desc)) {
            cJSON_AddStringToObject(decl, "description", desc->valuestring);
        }
        const cJSON *params = cJSON_GetObjectItemCaseSensitive(tool, "parameters");
        const cJSON *props = params ? cJSON_GetObjectItemCaseSensitive(params, "properties") : NULL;
        if (props && cJSON_GetArraySize(props) > 0) {
            cJSON *converted = gemini_schema_convert_node(params);
            cJSON_AddItemToObject(decl, "parameters", converted);
        }
        /* if properties is missing or empty, drop "parameters" entirely (a function with no arguments) */
        cJSON_AddItemToArray(out, decl);
    }
    return out;
}

/* ── Self-test ───────────────────────────────────────────── */

static cJSON *find_prop(const cJSON *decl, const char *name)
{
    const cJSON *params = cJSON_GetObjectItemCaseSensitive(decl, "parameters");
    const cJSON *props = cJSON_GetObjectItemCaseSensitive(params, "properties");
    return cJSON_GetObjectItemCaseSensitive(props, name);
}

static bool required_has(const cJSON *decl, const char *name)
{
    const cJSON *params = cJSON_GetObjectItemCaseSensitive(decl, "parameters");
    const cJSON *required = cJSON_GetObjectItemCaseSensitive(params, "required");
    const cJSON *r;
    cJSON_ArrayForEach(r, required) {
        if (cJSON_IsString(r) && !strcmp(r->valuestring, name)) {
            return true;
        }
    }
    return false;
}

bool gemini_schema_selftest(void)
{
    bool ok = true;
    cJSON *tools = cJSON_CreateArray();
    cJSON *ws = cJSON_Parse("{\"type\":\"web_search\"}");
    cJSON_AddItemToArray(tools, ws);
    cJSON *radio = cJSON_Parse(
        "{\"type\":\"function\",\"name\":\"radio_play\",\"description\":\"d\",\"strict\":true,\"parameters\":"
        "{\"type\":\"object\",\"properties\":{\"station\":{\"type\":[\"string\",\"null\"]},\"genre\":{\"type\":"
        "[\"string\",\"null\"]}},\"required\":[\"station\",\"genre\"],\"additionalProperties\":false}}");
    cJSON_AddItemToArray(tools, radio);
    cJSON *gain = cJSON_Parse(
        "{\"type\":\"function\",\"name\":\"set_microphone_gain\",\"description\":\"d\",\"strict\":true,"
        "\"parameters\":{\"type\":\"object\",\"properties\":{\"gain_db\":{\"type\":\"integer\",\"enum\":[0,3,6,9,"
        "12,15,18,21,24,27,30,36]}},\"required\":[\"gain_db\"],\"additionalProperties\":false}}");
    cJSON_AddItemToArray(tools, gain);
    cJSON *notes_add = cJSON_Parse(
        "{\"type\":\"function\",\"name\":\"notes_add\",\"description\":\"d\",\"strict\":true,\"parameters\":"
        "{\"type\":\"object\",\"properties\":{\"kind\":{\"type\":\"string\",\"enum\":[\"memo\",\"event\"]},"
        "\"title\":{\"type\":\"string\"},\"remind\":{\"type\":[\"array\",\"null\"],\"items\":{\"type\":"
        "\"integer\"},\"maxItems\":3}},\"required\":[\"kind\",\"title\",\"remind\"],\"additionalProperties\":false}}");
    cJSON_AddItemToArray(tools, notes_add);
    cJSON *noargs = cJSON_Parse(
        "{\"type\":\"function\",\"name\":\"get_now_playing\",\"description\":\"d\",\"strict\":true,\"parameters\":"
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}}");
    cJSON_AddItemToArray(tools, noargs);

    cJSON *out = gemini_schema_convert_tools(tools);
    ok &= cJSON_GetArraySize(out) == 4;     /* web_search is dropped */

    cJSON *decl_radio = NULL, *decl_gain = NULL, *decl_notes = NULL, *decl_noargs = NULL;
    const cJSON *d;
    cJSON_ArrayForEach(d, out) {
        const char *n = cJSON_GetObjectItemCaseSensitive(d, "name")->valuestring;
        if (!strcmp(n, "radio_play")) decl_radio = (cJSON *)d;
        if (!strcmp(n, "set_microphone_gain")) decl_gain = (cJSON *)d;
        if (!strcmp(n, "notes_add")) decl_notes = (cJSON *)d;
        if (!strcmp(n, "get_now_playing")) decl_noargs = (cJSON *)d;
    }
    ok &= decl_radio && decl_gain && decl_notes && decl_noargs;

    /* ["string","null"] → type STRING, nullable true, removed from required */
    cJSON *station = find_prop(decl_radio, "station");
    ok &= station && cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(station, "nullable"));
    ok &= station && !strcmp(cJSON_GetObjectItemCaseSensitive(station, "type")->valuestring, "STRING");
    ok &= !required_has(decl_radio, "station");
    ok &= !cJSON_GetObjectItemCaseSensitive(cJSON_GetObjectItemCaseSensitive(decl_radio, "parameters"), "strict");

    /* integer enum → INTEGER + minimum/maximum, no enum, allowed values in description */
    cJSON *gain_prop = find_prop(decl_gain, "gain_db");
    ok &= gain_prop && !strcmp(cJSON_GetObjectItemCaseSensitive(gain_prop, "type")->valuestring, "INTEGER");
    ok &= gain_prop && !cJSON_GetObjectItemCaseSensitive(gain_prop, "enum");
    ok &= gain_prop && cJSON_GetObjectItemCaseSensitive(gain_prop, "minimum")->valueint == 0;
    ok &= gain_prop && cJSON_GetObjectItemCaseSensitive(gain_prop, "maximum")->valueint == 36;
    ok &= gain_prop && strstr(cJSON_GetObjectItemCaseSensitive(gain_prop, "description")->valuestring, "36") != NULL;

    /* string enums pass through as is */
    cJSON *kind_prop = find_prop(decl_notes, "kind");
    ok &= kind_prop && cJSON_IsArray(cJSON_GetObjectItemCaseSensitive(kind_prop, "enum"));

    /* nullable array + items conversion + maxItems as a string */
    cJSON *remind_prop = find_prop(decl_notes, "remind");
    ok &= remind_prop && !strcmp(cJSON_GetObjectItemCaseSensitive(remind_prop, "type")->valuestring, "ARRAY");
    ok &= remind_prop && cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(remind_prop, "nullable"));
    cJSON *remind_items = cJSON_GetObjectItemCaseSensitive(remind_prop, "items");
    ok &= remind_items && !strcmp(cJSON_GetObjectItemCaseSensitive(remind_items, "type")->valuestring, "INTEGER");
    cJSON *max_items = cJSON_GetObjectItemCaseSensitive(remind_prop, "maxItems");
    ok &= max_items && cJSON_IsString(max_items) && !strcmp(max_items->valuestring, "3");
    ok &= !required_has(decl_notes, "remind");     /* nullable is removed from required */
    ok &= required_has(decl_notes, "kind") && required_has(decl_notes, "title");

    /* a function with no arguments has no parameters at all */
    ok &= cJSON_GetObjectItemCaseSensitive(decl_noargs, "parameters") == NULL;

    cJSON_Delete(tools);
    cJSON_Delete(out);
    return ok;
}
