#include "miniaudio_wrapper.h"
#include <os/log.h>

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
// Private variables
// -----------------------------------------------------------------------------
static ma_engine g_engine;
static ma_sound g_sound;
static int g_is_initialized = 0;
static ma_resource_manager g_resource_manager;
static char* g_current_file_path = NULL;
static ma_resource_manager_data_source g_loaded_sound;
static int g_has_loaded_sound = 0;

#define LOG_MA_ERROR(result, message) \
    os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Error: %s - %s", message, ma_result_description(result))

// -----------------------------------------------------------------------------
// Public API exposed through FFI
// -----------------------------------------------------------------------------
int miniaudio_init(void) {
    if (g_is_initialized) {
        os_log(OS_LOG_DEFAULT, "ℹ️ [MINIAUDIO] Engine already initialized");
        return 0;
    }
    
    // Initialize resource manager first
    ma_resource_manager_config resource_manager_config = ma_resource_manager_config_init();
    ma_result result = ma_resource_manager_init(&resource_manager_config, &g_resource_manager);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize resource manager");
        return -1;
    }
    
    // Initialize engine with resource manager
    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.pResourceManager = &g_resource_manager;
    
    result = ma_engine_init(&engine_config, &g_engine);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize engine");
        ma_resource_manager_uninit(&g_resource_manager);
        return -1;
    }
    
    g_is_initialized = 1;
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Engine initialized successfully");
    return 0;
}

int miniaudio_play_sound(const char* file_path) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (file_path == NULL || strlen(file_path) == 0) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }
    
    os_log(OS_LOG_DEFAULT, "▶️ [MINIAUDIO] Attempting to play sound: %s", file_path);
    
    // Store the current file path
    if (g_current_file_path != NULL) {
        free(g_current_file_path);
    }
    g_current_file_path = strdup(file_path);
    
    // Stop and uninitialize any currently playing sound
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
        ma_sound_uninit(&g_sound);
    }
    
    // Initialize and start the new sound
    ma_sound_config soundConfig = ma_sound_config_init();
    soundConfig.flags = MA_SOUND_FLAG_LOOPING;
    
    ma_result result = ma_sound_init_from_file(&g_engine, file_path, MA_SOUND_FLAG_LOOPING, NULL, NULL, &g_sound);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize sound");
        return -1;
    }
    
    result = ma_sound_start(&g_sound);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to start sound");
        ma_sound_uninit(&g_sound);
        return -1;
    }
    
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Sound started successfully");
    return 0;
}

void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return;
    }
    
    os_log(OS_LOG_DEFAULT, "⏹️ [MINIAUDIO] Stopping all sounds");
    
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
        ma_sound_uninit(&g_sound);
    }
}

int miniaudio_load_sound(const char* file_path) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (file_path == NULL || strlen(file_path) == 0) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }
    
    os_log(OS_LOG_DEFAULT, "📥 [MINIAUDIO] Loading sound into memory: %s", file_path);
    
    // Unload previous sound if any
    if (g_has_loaded_sound) {
        ma_resource_manager_data_source_uninit(&g_loaded_sound);
        g_has_loaded_sound = 0;
    }
    
    // Load the sound into memory
    ma_result result = ma_resource_manager_data_source_init(
        &g_resource_manager,
        file_path,
        MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_DECODE | MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_ASYNC,
        NULL,  // No custom allocation callbacks
        &g_loaded_sound
    );
    
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to load sound into memory");
        return -1;
    }
    
    g_has_loaded_sound = 1;
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Sound loaded into memory successfully");
    return 0;
}

int miniaudio_play_loaded_sound(void) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (!g_has_loaded_sound) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] No sound loaded in memory");
        return -1;
    }
    
    os_log(OS_LOG_DEFAULT, "▶️ [MINIAUDIO] Playing loaded sound");
    
    // Stop and uninitialize any currently playing sound
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
        ma_sound_uninit(&g_sound);
    }
    
    // Initialize and start the sound from the loaded data
    ma_sound_config soundConfig = ma_sound_config_init();
    soundConfig.flags = MA_SOUND_FLAG_LOOPING;
    
    ma_result result = ma_sound_init_from_data_source(
        &g_engine,
        &g_loaded_sound,
        MA_SOUND_FLAG_LOOPING,
        NULL,
        &g_sound
    );
    
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize sound from loaded data");
        return -1;
    }
    
    result = ma_sound_start(&g_sound);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to start sound");
        ma_sound_uninit(&g_sound);
        return -1;
    }
    
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Loaded sound started successfully");
    return 0;
}

void miniaudio_cleanup(void) {
    os_log(OS_LOG_DEFAULT, "🧹 [MINIAUDIO] Cleaning up");
    
    if (g_is_initialized) {
        // Stop and uninitialize sound first
        if (g_sound.pDataSource != NULL) {
            ma_sound_stop(&g_sound);
            ma_sound_uninit(&g_sound);
        }
        
        // Free the stored file path
        if (g_current_file_path != NULL) {
            free(g_current_file_path);
            g_current_file_path = NULL;
        }
        
        // Unload any loaded sound
        if (g_has_loaded_sound) {
            ma_resource_manager_data_source_uninit(&g_loaded_sound);
            g_has_loaded_sound = 0;
        }
        
        // Then uninitialize engine
        ma_engine_uninit(&g_engine);
        
        // Finally uninitialize resource manager
        ma_resource_manager_uninit(&g_resource_manager);
        
        g_is_initialized = 0;
        os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Cleanup completed successfully");
    }
} 