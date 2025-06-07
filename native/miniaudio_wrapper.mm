#include "miniaudio_wrapper.h"

// -----------------------------------------------------------------------------
// Configure miniaudio implementation for iOS (CoreAudio only)
// -----------------------------------------------------------------------------
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_AVFOUNDATION          // avoid Objective-C AVFoundation dependency
#define MA_NO_RUNTIME_LINKING       // we link statically
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_COREAUDIO         // use CoreAudio backend
#define MA_ENABLE_NULL              // keep null device for testing

#include "miniaudio.h"

#include <stdio.h>
#include <string.h>

// -----------------------------------------------------------------------------
// Internal helpers / globals
// -----------------------------------------------------------------------------
static ma_engine g_engine;            // High-level engine (global for simplicity)
static int       g_is_initialized = 0;

#define LOG_MA_ERROR(prefix, result)                                           \
    fprintf(stderr, "%s: %s (code=%d)\n", prefix, ma_result_description(result), (int)result)

// -----------------------------------------------------------------------------
// Public API exposed through FFI
// -----------------------------------------------------------------------------
int miniaudio_init(void) {
    if (g_is_initialized) {
        return 1; // already up
    }

    ma_engine_config config = ma_engine_config_init(); // defaults
    ma_result res = ma_engine_init(&config, &g_engine);
    if (res != MA_SUCCESS) {
        LOG_MA_ERROR("ma_engine_init failed", res);
        return 0;
    }

    g_is_initialized = 1;
    printf("✅ miniaudio engine initialised (CoreAudio)\n");
    return 1;
}

int miniaudio_play_sound(const char *file_path) {
    if (!g_is_initialized) {
        fprintf(stderr, "miniaudio_play_sound: engine not initialised\n");
        return 0;
    }

    if (file_path == NULL || strlen(file_path) == 0) {
        fprintf(stderr, "miniaudio_play_sound: file_path is null or empty\n");
        return 0;
    }

    ma_result res = ma_engine_play_sound(&g_engine, file_path, NULL);
    if (res != MA_SUCCESS) {
        LOG_MA_ERROR("ma_engine_play_sound failed", res);
        return 0;
    }
    return 1;
}

void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        return;
    }
    ma_engine_stop(&g_engine);
}

int miniaudio_is_initialized(void) {
    return g_is_initialized;
}

void miniaudio_cleanup(void) {
    if (!g_is_initialized) {
        return;
    }
    ma_engine_uninit(&g_engine);
    g_is_initialized = 0;
    printf("✅ miniaudio engine cleaned up\n");
} 