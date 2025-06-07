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
static ma_sound g_sound;              // Sound object for playback
static int g_is_initialized = 0;

#define LOG_MA_ERROR(prefix, result)                                           \
    fprintf(stderr, "🔴 [MINIAUDIO] %s: %s (code=%d)\n", prefix, ma_result_description(result), (int)result)

// -----------------------------------------------------------------------------
// Public API exposed through FFI
// -----------------------------------------------------------------------------
int miniaudio_init(void) {
    if (g_is_initialized) {
        fprintf(stderr, "ℹ️ [MINIAUDIO] Engine already initialized\n");
        return 1; // already up
    }

    ma_engine_config config = ma_engine_config_init(); // defaults
    ma_result res = ma_engine_init(&config, &g_engine);
    if (res != MA_SUCCESS) {
        LOG_MA_ERROR("ma_engine_init failed", res);
        return 0;
    }

    g_is_initialized = 1;
    fprintf(stderr, "✅ [MINIAUDIO] Engine initialized (CoreAudio)\n");
    return 1;
}

int miniaudio_play_sound(const char *file_path) {
    if (!g_is_initialized) {
        fprintf(stderr, "🔴 [MINIAUDIO] play_sound: engine not initialized\n");
        return 0;
    }

    if (file_path == NULL || strlen(file_path) == 0) {
        fprintf(stderr, "🔴 [MINIAUDIO] play_sound: file_path is null or empty\n");
        return 0;
    }

    fprintf(stderr, "🎵 [MINIAUDIO] Attempting to play: %s\n", file_path);
    
    // Stop any currently playing sound
    ma_sound_stop(&g_sound);
    ma_sound_uninit(&g_sound);
    
    // Initialize and start the new sound
    ma_sound_config soundConfig = ma_sound_config_init();
    soundConfig.pFilePath = file_path;
    soundConfig.flags = MA_SOUND_FLAG_LOOPING;  // Enable looping
    
    ma_result res = ma_sound_init_from_file(&g_engine, file_path, MA_SOUND_FLAG_LOOPING, NULL, NULL, &g_sound);
    if (res != MA_SUCCESS) {
        LOG_MA_ERROR("ma_sound_init_from_file failed", res);
        return 0;
    }
    
    res = ma_sound_start(&g_sound);
    if (res != MA_SUCCESS) {
        LOG_MA_ERROR("ma_sound_start failed", res);
        ma_sound_uninit(&g_sound);
        return 0;
    }
    
    fprintf(stderr, "✅ [MINIAUDIO] Successfully started playback\n");
    return 1;
}

void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        fprintf(stderr, "⚠️ [MINIAUDIO] stop_all_sounds: engine not initialized\n");
        return;
    }
    ma_sound_stop(&g_sound);
    fprintf(stderr, "🛑 [MINIAUDIO] All sounds stopped\n");
}

int miniaudio_is_initialized(void) {
    return g_is_initialized;
}

void miniaudio_cleanup(void) {
    if (!g_is_initialized) {
        return;
    }
    ma_sound_uninit(&g_sound);
    ma_engine_uninit(&g_engine);
    g_is_initialized = 0;
    fprintf(stderr, "✅ [MINIAUDIO] Engine cleaned up\n");
} 