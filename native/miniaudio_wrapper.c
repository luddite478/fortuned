#include "miniaudio_wrapper.h"
#include <stdio.h>

// For now, let's stick with test implementation while we fix the Dart string conversion
static int g_is_initialized = 0;

// Initialize the miniaudio engine
int miniaudio_init(void) {
    if (g_is_initialized) {
        return 1; // Already initialized
    }
    
    g_is_initialized = 1;
    printf("Test audio engine initialized successfully\n");
    return 1; // Success
}

// Play an audio file
int miniaudio_play_sound(const char* file_path) {
    if (!g_is_initialized) {
        printf("Audio engine not initialized\n");
        return 0;
    }
    
    if (file_path == NULL) {
        printf("File path is null\n");
        return 0;
    }
    
    printf("✅ FFI SUCCESS: Would play audio file: %s\n", file_path);
    return 1; // Success (simulated)
}

// Stop all sounds
void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        return;
    }
    
    printf("✅ FFI SUCCESS: Audio stopped\n");
}

// Check if engine is initialized
int miniaudio_is_initialized(void) {
    return g_is_initialized;
}

// Cleanup the miniaudio engine
void miniaudio_cleanup(void) {
    if (!g_is_initialized) {
        return;
    }
    
    g_is_initialized = 0;
    printf("✅ FFI SUCCESS: Audio engine cleaned up\n");
} 