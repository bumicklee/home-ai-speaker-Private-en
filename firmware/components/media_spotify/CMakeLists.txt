# If CONFIG_APP_SPOTIFY (main/Kconfig.projbuild, off by default) is off, substitute code is built instead of the real code.
# The public API (media_spotify.h) is the same, so callers do not change.
if(CONFIG_APP_SPOTIFY)
    set(srcs "spotify_api.c")
else()
    set(srcs "spotify_off.c")
endif()

idf_component_register(SRCS ${srcs}
                       INCLUDE_DIRS "include"
                       REQUIRES app_config app_events settings net json esp_http_client esp-tls esp_timer
                                freertos heap)
