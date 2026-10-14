/**
 * @file app_config.h
 * @brief Version, timing and identifier constants (config kept in one place)
 *
 * BLE and LAN spec constants follow design document Sections 2.13 and 2.14. When you change them,
 * change the app's ble_protocol.dart and api_paths.dart in the same PR.
 */
#pragma once

/* ── Version ──────────────────────────────────────────────────── */
#define APP_FW_VERSION              "0.1.0"
#define APP_PRODUCT_CODE            "AISPK-S3-V1"
#define APP_PROTOCOL_VERSION        1

/* ── Partitions ───────────────────────────────────────────────── */
#define APP_PART_SECRETS            "secrets"
#define APP_PART_STORAGE            "storage"
#define APP_PART_MODEL              "model"

/* ── BLE (Section 2.13) ─────────────────────────────────────────── */
#define APP_BLE_NAME_PREFIX         "JARVIS_"
#define APP_BLE_SVC_WIFI            0xFF50
#define APP_BLE_CHR_SSID            0xFF51
#define APP_BLE_CHR_PASSWORD        0xFF52
#define APP_BLE_CHR_STATUS          0xFF53
#define APP_BLE_CHR_SCAN            0xFF54
#define APP_BLE_SVC_DEVICE          0xFF60
#define APP_BLE_CHR_MAC             0xFF61
#define APP_BLE_CHR_PRODUCT         0xFF62
#define APP_BLE_CHR_FIRMWARE        0xFF63
#define APP_BLE_SVC_CONFIG          0xFF80
#define APP_BLE_CHR_CMD_RX          0xFF81
#define APP_BLE_CHR_CMD_TX          0xFF82
#define APP_BLE_CHR_PROV_DONE       0xFF88

#define APP_BLE_WINDOW_MS           (5 * 60 * 1000)    /* closes after 5 min with no connection */
#define APP_BLE_WINDOW_MAX_MS       (15 * 60 * 1000)   /* extended while connected, 15 min max */
#define APP_BLE_CMD_MAX_BYTES       4096
#define APP_BLE_CMD_REASSEMBLY_MS   3000
#define APP_PROV_REBOOT_DELAY_MS    2000

/* ── LAN (Section 2.14) ─────────────────────────────────────────── */
#define APP_MDNS_SERVICE            "_aispeaker"
#define APP_MDNS_PROTO              "_tcp"
#define APP_MDNS_HOST_PREFIX        "jarvis-"
#define APP_HTTP_PORT               80
#define APP_API_MAX_PHONES          5

/* ── Wi-Fi ────────────────────────────────────────────────── */
#define APP_WIFI_CONNECT_TIMEOUT_MS 20000   /* 20 s to decide the connection (status 5 = timeout) */
#define APP_WIFI_RETRY_MIN_MS       1000    /* reconnect exponential backoff start */
#define APP_WIFI_RETRY_MAX_MS       60000   /* backoff cap. Retries never stop */
#define APP_WIFI_DHCP_GRACE_MS      30000   /* associated but no IP: disconnect and retry. At 15 s a slow router kept getting disconnected (real board) */
#define APP_WIFI_DHCP_CHECK_MS      2000
#define APP_SNTP_SERVER             "pool.ntp.org"
#define APP_TIME_VALID_EPOCH        1767225600  /* 2026-01-01 UTC. Anything earlier means the time is not set */

/* ── Voice conversation ────────────────────────────────────────────── */
/* idle timeout cut to save on cost (2026-10-04, user). Korean lessons use their own limit */
#define APP_VOICE_IDLE_TIMEOUT_MS   (20 * 1000)        /* 20-second idle timeout (60 → 30 → 15 → 30 → 20 s, book Chapter 16, Bug 2) */
#define APP_VOICE_MAX_SESSION_MS    (10 * 60 * 1000)   /* conversation 10 min max */
#define APP_VOICE_USAGE_WAIT_MS     (15 * 1000)        /* wait for usage after the session ends */
#define APP_LIVE_MODEL_DEFAULT      "gpt-live-1"
#define APP_BACKEND_MODEL_DEFAULT   "gpt-5.6-luna"
/* Gemini Saver mode (docs/design-voice-saver-mode.md stage 2; checked ai.google.dev 2026-10: current values unchanged) */
#define APP_GEMINI_MODEL_DEFAULT     "gemini-3.1-flash-lite"
#define APP_GEMINI_TTS_MODEL_DEFAULT "gemini-3.8-flash-lite-tts"
/* Gemini Live (Live API), stage 3. The model name is kept in short form without "models/"; gemini_live.c
 * adds "models/" when it puts it into BidiGenerateContentSetup.model (checked 2026-10 ai.google.dev/api/live,
 * /gemini-api/docs/live-api/tools: gemini-3.8-live, the default for low-latency voice conversation) */
#define APP_GEMINI_LIVE_MODEL_DEFAULT "gemini-3.8-live"

/* ── Spotify (Section 2.10) ─────────────────────────────────────── */
/* Connect receiver name prefix. If a device on the same account has this name, playback goes to that device */
#define APP_SPOTIFY_DEVICE_NAME     "Jarvis"

/* ── Buttons (Section 2.15) ────────────────────────────────────────── */
#define APP_BUTTON_POLL_MS          20
#define APP_BUTTON_DEBOUNCE_COUNT   2       /* confirmed after the same value 2 times in a row (40ms) */
#define APP_KEY2_BLE_MS             3000
#define APP_KEY2_WARN_MS            7000
#define APP_KEY2_FACTORY_MS         10000
#define APP_VOLUME_REPEAT_MS        300

/* ── Audio ───────────────────────────────────────────────── */
#define APP_VOLUME_MAX              80
#define APP_VOLUME_STEP             5
#define APP_MIC_GAIN_MAX_DB         37.5f
#define APP_AMP_ON_DELAY_MS         50      /* from TX silence output to amp on */
