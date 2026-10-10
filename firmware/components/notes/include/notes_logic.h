/**
 * @file notes_logic.h
 * @brief Pure logic for the notes module (dates, UTF-8, search, id, phrases). No ESP-IDF dependency (tested on a Mac, same approach as tool_guard.c)
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Calendar (Howard Hinnant day-number formula) ─────────────────────── */
long notes_days_from_civil(int y, int m, int d);
void notes_civil_from_days(long z, int *y, int *m, int *d);
bool notes_is_leap_year(int y);
/** Whether y-m-d is a real Gregorian date (including February in leap years). y accepts only 1970-2200 */
bool notes_valid_calendar_date(int y, int m, int d);
/** Weekday 0=Sun 1=Mon … 6=Sat */
int notes_weekday(int y, int m, int d);

/* ── start/end strings ────────────────────────────────────────────────── */
/**
 * Checks for "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" and a real date and time (exact digit counts too).
 * On success returns true and fills y/m/d/hh/mm (hh=mm=0 if all_day). On failure the values are left unchanged.
 */
bool notes_parse_start(const char *s, int *y, int *m, int *d, int *hh, int *mm, bool *all_day);

/** Base (absolute) minute of an event. For an all-day event, uses all_day_hh:all_day_mm. Use only for subtraction and comparison */
int64_t notes_base_minutes(int y, int m, int d, int hh, int mm, bool all_day, int all_day_hh, int all_day_mm);

/* ── UTF-8 ────────────────────────────────────────────────────────────── */
bool notes_utf8_valid(const char *s, size_t len);
/** Truncates s to at most max bytes without cutting a character in half (out must be a buffer of at least max+1 bytes) */
void notes_utf8_truncate(const char *s, size_t max, char *out);

/* ── Search ───────────────────────────────────────────────────────────── */
/** Whether needle is in haystack, ignoring (ASCII) case and spaces. true if needle is empty */
bool notes_search_match(const char *haystack, const char *needle);

/* ── id and phrases ───────────────────────────────────────────────────── */
/** Builds an id of "n_" + 8 hex chars from a random 32-bit value (out must be at least 11 bytes) */
void notes_id_from_random(uint32_t r, char out[11]);
bool notes_id_looks_valid(const char *id);
/** 0, 10, 30, 60, 120, 1440 minutes get short phrases; others are in minutes/hours/days (all English: data the assistant model reads) */
void notes_remind_phrase(int minutes, char *out, size_t cap);

/** Self-test for dates, UTF-8, search, id, and base-time computation (compiles and runs with cc even without ESP-IDF) */
bool notes_selftest(void);

#ifdef __cplusplus
}
#endif
