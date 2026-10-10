/*
 * Radio presets: /storage/presets.json on the storage (littlefs) partition (design document Section 2.9, RAD-08/12).
 * URLs are long and can exceed the NVS string limit (4,000B), so they live in a file.
 *
 * 13 default presets (RAD-12, user request 2026-10-03: Korean channels + CNN/Bloomberg + US/Korean talk).
 * All are direct MP3/AAC streams (this player can't play HLS). Connection and format checked on a Mac 2026-10-03.
 * - Major Korean broadcasters (KBS, MBC, SBS, CBS, YTN, TBS, EBS, OBS Gyeongin, TBN, Arirang) are all HLS (mostly tokenized), so they're not included.
 *   The Korean channels are internet stations (K-POP, oldies) and community radio (Mapo FM, Jeonju FM, mostly talk).
 * - CNN, CNN International and Bloomberg are TuneIn CDN URLs. They aren't the broadcasters' official URLs and may change or be blocked.
 * - Names carry both Korean and English so "블룸버그 틀어 줘" (play Bloomberg) also matches part of a name (radio_presets_find is a partial match).
 * Devices still using the old 6 defaults unchanged are switched to the new defaults at boot (user-edited lists are left alone).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "app_config.h"
#include "esp_littlefs.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "media_radio.h"

static const char *TAG = "PRESETS";

#define BASE_PATH  "/storage"
#define FILE_PATH  BASE_PATH "/presets.json"
#define FILE_MAX   (RADIO_MAX_PRESETS * (RADIO_NAME_MAX + RADIO_URL_MAX + RADIO_GENRE_MAX + 40))

static const char DEFAULTS[] =
    "["
    "{\"name\":\"Big B Radio K-POP 케이팝\",\"url\":\"https://antares.dribbcast.com/proxy/kpop?mp=/s\",\"genre\":\"kpop,pop,korean\"},"
    "{\"name\":\"ARA FM 아라FM\",\"url\":\"http://141.164.38.238/listen/ara_fm/radio.mp3\",\"genre\":\"kpop,ballad,chill,korean\"},"
    "{\"name\":\"올드팝카페 Oldpop Cafe\",\"url\":\"http://cast.oldpopcafe.net:7080/\",\"genre\":\"oldies,pop,newage,korean\"},"
    "{\"name\":\"LISTEN.moe K-POP\",\"url\":\"https://listen.moe/kpop/fallback\",\"genre\":\"kpop,pop\"},"
    "{\"name\":\"마포FM 공동체라디오\",\"url\":\"http://onair.mapofm.net/mapofm\",\"genre\":\"talk,community,korean\"},"
    "{\"name\":\"전주FM 공동체라디오\",\"url\":\"http://radiostream.communityradio.kr/jcfm1\",\"genre\":\"talk,community,korean\"},"
    "{\"name\":\"CNN\",\"url\":\"https://tunein.cdnstream1.com/2868_96.mp3\",\"genre\":\"news,talk,english\"},"
    "{\"name\":\"CNN International\",\"url\":\"https://tunein.cdnstream1.com/3519_96.aac\",\"genre\":\"news,world,english\"},"
    "{\"name\":\"블룸버그 Bloomberg Radio\",\"url\":\"https://tunein.cdnstream1.com/3521_96.mp3\",\"genre\":\"business,finance,news,english\"},"
    "{\"name\":\"NPR 미국 공영라디오\",\"url\":\"http://npr-ice.streamguys1.com/live.mp3\",\"genre\":\"talk,news,english\"},"
    "{\"name\":\"WNYC 뉴욕 공영라디오\",\"url\":\"https://fm939.wnyc.org/wnycfm-web\",\"genre\":\"talk,news,english\"},"
    "{\"name\":\"C-SPAN Radio\",\"url\":\"https://playerservices.streamtheworld.com/api/livestream-redirect/CSPANRADIO.mp3\",\"genre\":\"politics,talk,english\"},"
    "{\"name\":\"BBC World Service\",\"url\":\"https://stream.live.vc.bbcmedia.co.uk/bbc_world_service\",\"genre\":\"news,world,english\"}"
    "]";

/* Old (2026-10-02) defaults. Only devices with exactly this saved list get the new defaults */
static const char OLD_DEFAULTS_V1[] =
    "["
    "{\"name\":\"Radio Paradise Mellow\",\"url\":\"http://stream.radioparadise.com/mellow-128\",\"genre\":\"chill,mellow,eclectic\"},"
    "{\"name\":\"Radio Paradise Rock\",\"url\":\"http://stream.radioparadise.com/rock-128\",\"genre\":\"rock\"},"
    "{\"name\":\"SomaFM Groove Salad\",\"url\":\"https://ice1.somafm.com/groovesalad-128-mp3\",\"genre\":\"ambient,chill,electronic\"},"
    "{\"name\":\"SomaFM DEF CON Radio\",\"url\":\"https://ice1.somafm.com/defcon-128-mp3\",\"genre\":\"electronic\"},"
    "{\"name\":\"SomaFM Indie Pop Rocks\",\"url\":\"https://ice1.somafm.com/indiepop-128-mp3\",\"genre\":\"indie,pop\"},"
    "{\"name\":\"KEXP\",\"url\":\"https://kexp-mp3-128.streamguys1.com/kexp128.mp3\",\"genre\":\"alternative,indie,eclectic\"}"
    "]";

static SemaphoreHandle_t s_lock;
static cJSON *s_presets;
static bool s_mounted;

static bool string_ok(const cJSON *v, size_t min, size_t max)
{
    return cJSON_IsString(v) && strlen(v->valuestring) >= min && strlen(v->valuestring) <= max;
}

static bool presets_valid(const cJSON *arr)
{
    if (!cJSON_IsArray(arr) || cJSON_GetArraySize(arr) > RADIO_MAX_PRESETS) {
        return false;
    }
    const cJSON *p;
    cJSON_ArrayForEach(p, arr) {
        const cJSON *url = cJSON_GetObjectItemCaseSensitive(p, "url");
        const cJSON *genre = cJSON_GetObjectItemCaseSensitive(p, "genre");
        if (!cJSON_IsObject(p) || !string_ok(cJSON_GetObjectItemCaseSensitive(p, "name"), 1, RADIO_NAME_MAX) ||
            !string_ok(url, 8, RADIO_URL_MAX) ||
            (strncmp(url->valuestring, "http://", 7) && strncmp(url->valuestring, "https://", 8)) ||
            (genre && !string_ok(genre, 0, RADIO_GENRE_MAX))) {
            return false;
        }
    }
    return true;
}

static esp_err_t write_file(const cJSON *arr)
{
    if (!s_mounted) {
        return ESP_ERR_INVALID_STATE;
    }
    char *text = cJSON_PrintUnformatted(arr);
    if (!text) {
        return ESP_ERR_NO_MEM;
    }
    FILE *f = fopen(FILE_PATH ".tmp", "w");
    esp_err_t err = ESP_FAIL;
    if (f) {
        bool ok = fputs(text, f) >= 0;
        ok = (fclose(f) == 0) && ok;
        /* Write everything to a temp file, then swap it in (so the previous list survives a power loss mid-write) */
        if (ok) {
            remove(FILE_PATH);
            ok = rename(FILE_PATH ".tmp", FILE_PATH) == 0;
        }
        err = ok ? ESP_OK : ESP_FAIL;
    }
    free(text);
    return err;
}

static cJSON *read_file(void)
{
    FILE *f = s_mounted ? fopen(FILE_PATH, "r") : NULL;
    if (!f) {
        return NULL;
    }
    char *buf = malloc(FILE_MAX + 1);
    cJSON *j = NULL;
    if (buf) {
        size_t n = fread(buf, 1, FILE_MAX, f);
        buf[n] = '\0';
        j = cJSON_Parse(buf);
        free(buf);
    }
    fclose(f);
    return j;
}

esp_err_t radio_presets_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) {
        return ESP_ERR_NO_MEM;
    }
    const esp_vfs_littlefs_conf_t conf = {
        .base_path = BASE_PATH,
        .partition_label = APP_PART_STORAGE,
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_littlefs_register(&conf);
    s_mounted = err == ESP_OK;
    if (!s_mounted) {
        ESP_LOGE(TAG, "littlefs mount failed: %s (using defaults in RAM)", esp_err_to_name(err));
    }
    s_presets = read_file();
    if (!presets_valid(s_presets)) {
        cJSON_Delete(s_presets);
        s_presets = cJSON_Parse(DEFAULTS);
        write_file(s_presets);
    } else {
        cJSON *old = cJSON_Parse(OLD_DEFAULTS_V1);
        if (old && cJSON_Compare(s_presets, old, true)) {
            ESP_LOGI(TAG, "old default presets: replacing with new defaults");
            cJSON_Delete(s_presets);
            s_presets = cJSON_Parse(DEFAULTS);
            write_file(s_presets);
        }
        cJSON_Delete(old);
    }
    ESP_LOGI(TAG, "%d preset(s)", cJSON_GetArraySize(s_presets));
    return s_presets ? ESP_OK : ESP_ERR_NO_MEM;
}

cJSON *radio_presets_get(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    cJSON *copy = cJSON_Duplicate(s_presets, true);
    xSemaphoreGive(s_lock);
    return copy;
}

esp_err_t radio_presets_set(const cJSON *presets)
{
    if (!presets_valid(presets)) {
        return ESP_ERR_INVALID_ARG;
    }
    cJSON *copy = cJSON_Duplicate(presets, true);
    if (!copy) {
        return ESP_ERR_NO_MEM;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    esp_err_t err = write_file(copy);
    if (err == ESP_OK) {
        cJSON_Delete(s_presets);
        s_presets = copy;
        copy = NULL;
    }
    xSemaphoreGive(s_lock);
    cJSON_Delete(copy);
    return err;
}

esp_err_t radio_presets_reset(void)
{
    cJSON *def = cJSON_Parse(DEFAULTS);
    esp_err_t err = radio_presets_set(def);
    cJSON_Delete(def);
    return err;
}

int radio_presets_count(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int n = cJSON_GetArraySize(s_presets);
    xSemaphoreGive(s_lock);
    return n;
}

bool radio_presets_entry(int index, char *url, size_t url_len, char *name, size_t name_len)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    const cJSON *p = cJSON_GetArrayItem(s_presets, index);
    bool ok = p != NULL;
    if (ok) {
        strlcpy(url, cJSON_GetObjectItem(p, "url")->valuestring, url_len);
        strlcpy(name, cJSON_GetObjectItem(p, "name")->valuestring, name_len);
    }
    xSemaphoreGive(s_lock);
    return ok;
}

/* Case-insensitive substring search (Korean is compared byte for byte) */
static bool contains_ci(const char *hay, const char *needle)
{
    size_t n = strlen(needle);
    if (!n) {
        return false;
    }
    for (; *hay; hay++) {
        if (!strncasecmp(hay, needle, n)) {
            return true;
        }
    }
    return false;
}

int radio_presets_find(const char *name, const char *genre)
{
    int found = -1;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int i = 0;
    const cJSON *p;
    cJSON_ArrayForEach(p, s_presets) {
        const cJSON *pn = cJSON_GetObjectItem(p, "name"), *pg = cJSON_GetObjectItem(p, "genre");
        if ((name && name[0] && contains_ci(pn->valuestring, name)) ||
            (genre && genre[0] && cJSON_IsString(pg) && contains_ci(pg->valuestring, genre))) {
            found = i;
            break;
        }
        i++;
    }
    xSemaphoreGive(s_lock);
    return found;
}
