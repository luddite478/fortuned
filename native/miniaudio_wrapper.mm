#include "miniaudio_wrapper.h"
#include <os/log.h>
#include <dispatch/dispatch.h>

// iOS Audio Session for Bluetooth routing
#import <AVFoundation/AVFoundation.h>

// -----------------------------------------------------------------------------
// Configure miniaudio implementation for iOS (CoreAudio only)
// Disable AVFoundation in miniaudio to prevent DefaultToSpeaker override
// -----------------------------------------------------------------------------
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_AVFOUNDATION          // CRITICAL: Prevent miniaudio from setting DefaultToSpeaker
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
static dispatch_queue_t g_audio_queue = NULL; // Serial queue for thread-safe operations

// -----------------------------
// Multi-slot support
// -----------------------------
#ifndef MINIAUDIO_MAX_SLOTS
#define MINIAUDIO_MAX_SLOTS 8
#endif

static ma_sound                        g_slot_sounds[MINIAUDIO_MAX_SLOTS];
static ma_resource_manager_data_source g_slot_data_sources[MINIAUDIO_MAX_SLOTS];
static int                             g_slot_has_sound[MINIAUDIO_MAX_SLOTS]         = {0};
static int                             g_slot_loaded_in_memory[MINIAUDIO_MAX_SLOTS]  = {0};
static char*                           g_slot_file_paths[MINIAUDIO_MAX_SLOTS]        = {0};

#define LOG_MA_ERROR(result, message) \
    os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Error: %s - %s", message, ma_result_description(result))

// -----------------------------------------------------------------------------
// iOS Audio Session Configuration for Bluetooth Support
// -----------------------------------------------------------------------------
static int configure_ios_audio_session(void) {
    os_log(OS_LOG_DEFAULT, "🔧 [AUDIO SESSION] Configuring iOS audio session...");
    
    // Check if AVAudioSession class exists at runtime
    Class audioSessionClass = NSClassFromString(@"AVAudioSession");
    if (audioSessionClass == nil) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [DEBUG] AVAudioSession class not found at runtime!");
        return -1;
    }
    os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] AVAudioSession class found successfully");
    
    @try {
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Getting AVAudioSession sharedInstance...");
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        if (session == nil) {
            os_log_error(OS_LOG_DEFAULT, "🔴 [DEBUG] AVAudioSession sharedInstance returned nil!");
            return -1;
        }
        
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Session obtained successfully");
        
        // Try full Bluetooth configuration first
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Setting category with Bluetooth options...");
        BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                           AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                           AVAudioSessionCategoryOptionDefaultToSpeaker
                                       error:&error];
        
        if (!success) {
            os_log_error(OS_LOG_DEFAULT, "🔴 [AUDIO SESSION] Failed full config: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            
            // Fallback: Try basic playback category only
            os_log(OS_LOG_DEFAULT, "🔧 [AUDIO SESSION] Trying fallback basic configuration...");
            error = nil;  // Reset error
            success = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
            if (!success) {
                os_log_error(OS_LOG_DEFAULT, "🔴 [AUDIO SESSION] Even basic config failed: %@ (Code: %ld)", 
                             error.localizedDescription, (long)error.code);
                return -1;
            }
        }
        os_log(OS_LOG_DEFAULT, "✅ [AUDIO SESSION] Category set successfully");
        
        // Set mode for general audio
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Setting mode...");
        error = nil;  // Reset error
        success = [session setMode:AVAudioSessionModeDefault error:&error];
        if (!success) {
            os_log_error(OS_LOG_DEFAULT, "🔴 [AUDIO SESSION] Failed to set mode: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        os_log(OS_LOG_DEFAULT, "✅ [AUDIO SESSION] Mode set successfully");
        
        // Activate the session
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Activating session...");
        error = nil;  // Reset error
        success = [session setActive:YES error:&error];
        if (!success) {
            os_log_error(OS_LOG_DEFAULT, "🔴 [AUDIO SESSION] Failed to activate: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        os_log(OS_LOG_DEFAULT, "✅ [AUDIO SESSION] Session activated successfully");
        
        // Log current route for debugging
        os_log(OS_LOG_DEFAULT, "🔍 [DEBUG] Logging route after configuration...");
        AVAudioSessionRouteDescription *route = session.currentRoute;
        for (AVAudioSessionPortDescription *output in route.outputs) {
            os_log(OS_LOG_DEFAULT, "🎧 [AUDIO SESSION] Current output: %@ (%@)", 
                   output.portName, output.portType);
        }
        
        os_log(OS_LOG_DEFAULT, "✅ [AUDIO SESSION] Configured for Bluetooth support");
        return 0;
    } @catch (NSException *exception) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [DEBUG] Exception in configure_ios_audio_session: %@", exception.reason);
        return -1;
    }
}

// -----------------------------------------------------------------------------
// Public function to re-activate Bluetooth audio session from Flutter
// -----------------------------------------------------------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void) {
    os_log(OS_LOG_DEFAULT, "🔄 [AUDIO SESSION] Re-configuring audio session for Bluetooth...");
    return configure_ios_audio_session();
}

// -----------------------------------------------------------------------------
// Public API exposed through FFI
// -----------------------------------------------------------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_init(void) {
    if (g_is_initialized) {
        os_log(OS_LOG_DEFAULT, "ℹ️ [MINIAUDIO] Engine already initialized");
        return 0;
    }
    
    os_log(OS_LOG_DEFAULT, "🚀 [MINIAUDIO] Starting initialization process...");
    
    // Configure iOS audio session for Bluetooth BEFORE miniaudio init
    os_log(OS_LOG_DEFAULT, "🔧 [MINIAUDIO] Configuring audio session BEFORE engine init...");
    if (configure_ios_audio_session() != 0) {
        os_log_error(OS_LOG_DEFAULT, "⚠️ [MINIAUDIO] Audio session config failed, continuing with default");
        // Don't return error - continue with miniaudio initialization
    } else {
        os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Audio session configured successfully");
    }
    
    // Initialize resource manager first
    os_log(OS_LOG_DEFAULT, "🔧 [MINIAUDIO] Initializing resource manager...");
    ma_resource_manager_config resource_manager_config = ma_resource_manager_config_init();
    ma_result result = ma_resource_manager_init(&resource_manager_config, &g_resource_manager);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize resource manager");
        return -1;
    }
    
    // Initialize engine with resource manager
    os_log(OS_LOG_DEFAULT, "🔧 [MINIAUDIO] Initializing engine...");
    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.pResourceManager = &g_resource_manager;
    
    result = ma_engine_init(&engine_config, &g_engine);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize engine");
        ma_resource_manager_uninit(&g_resource_manager);
        return -1;
    }
    
    // Create serial queue once engine is alive
    if (g_audio_queue == NULL) {
        g_audio_queue = dispatch_queue_create("com.niyya.miniaudio", DISPATCH_QUEUE_SERIAL);
    }
    
    // Ensure slot arrays are zeroed (already static init, but be explicit)
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        g_slot_has_sound[i]        = 0;
        g_slot_loaded_in_memory[i] = 0;
        g_slot_file_paths[i]       = NULL;
        g_slot_sounds[i].pDataSource = NULL;
    }
    
    g_is_initialized = 1;
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Engine initialized successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
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

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return;
    }
    
    os_log(OS_LOG_DEFAULT, "⏹️ [MINIAUDIO] Stopping all sounds");
    
    // Stop single legacy sound
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
    }

    // Stop all slot sounds safely
    dispatch_sync(g_audio_queue, ^{
        for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
            if (g_slot_has_sound[i] && g_slot_sounds[i].pDataSource != NULL) {
                ma_sound_stop(&g_slot_sounds[i]);
            }
        }
    });
}

__attribute__((visibility("default"))) __attribute__((used))
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

__attribute__((visibility("default"))) __attribute__((used))
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

// -----------------------------
// Utility helpers
// -----------------------------
static int validate_slot(int slot) {
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return 0;
    }
    return 1;
}

static void free_slot_resources(int slot) {
    // Assumes dispatch_sync already protecting
    if (g_slot_has_sound[slot]) {
        ma_sound_uninit(&g_slot_sounds[slot]);
        if (g_slot_loaded_in_memory[slot]) {
            ma_resource_manager_data_source_uninit(&g_slot_data_sources[slot]);
            g_slot_loaded_in_memory[slot] = 0;
        }
        g_slot_has_sound[slot] = 0;
    }
    // Free stored path
    if (g_slot_file_paths[slot] != NULL) {
        free(g_slot_file_paths[slot]);
        g_slot_file_paths[slot] = NULL;
    }
}

// -----------------------------
// Public FFI Slot API
// -----------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_get_slot_count(void) {
    return MINIAUDIO_MAX_SLOTS;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_slot_loaded(int slot) {
    if (!validate_slot(slot)) return 0;
    return g_slot_has_sound[slot];
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_load_sound_to_slot(int slot, const char* file_path, int loadToMemory) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    if (!validate_slot(slot)) return -1;
    if (file_path == NULL || strlen(file_path) == 0) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }

    __block int resultCode = 0;
    dispatch_sync(g_audio_queue, ^{
        // Cleanup existing resources in the slot first
        free_slot_resources(slot);

        // Store new path copy for diagnostics / future reloads
        g_slot_file_paths[slot] = strdup(file_path);

        ma_result result;
        if (loadToMemory) {
            os_log(OS_LOG_DEFAULT, "📥 [MINIAUDIO] Slot %d loading (memory) %s", slot, file_path);
            result = ma_resource_manager_data_source_init(&g_resource_manager,
                                                          file_path,
                                                          MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_DECODE,
                                                          NULL,
                                                          &g_slot_data_sources[slot]);
            if (result != MA_SUCCESS) {
                LOG_MA_ERROR(result, "Failed to load data source");
                resultCode = -1;
                return;
            }
            result = ma_sound_init_from_data_source(&g_engine, &g_slot_data_sources[slot], 0, NULL, &g_slot_sounds[slot]);
            if (result != MA_SUCCESS) {
                LOG_MA_ERROR(result, "Failed to init sound from data source");
                ma_resource_manager_data_source_uninit(&g_slot_data_sources[slot]);
                resultCode = -1;
                return;
            }
            g_slot_loaded_in_memory[slot] = 1;
        } else {
            os_log(OS_LOG_DEFAULT, "📥 [MINIAUDIO] Slot %d loading (stream) %s", slot, file_path);
            result = ma_sound_init_from_file(&g_engine, file_path, 0, NULL, NULL, &g_slot_sounds[slot]);
            if (result != MA_SUCCESS) {
                LOG_MA_ERROR(result, "Failed to init sound from file");
                resultCode = -1;
                return;
            }
            g_slot_loaded_in_memory[slot] = 0;
        }
        g_slot_has_sound[slot] = 1;
    });
    return resultCode;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_slot(int slot) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    if (!validate_slot(slot)) return -1;
    __block int rc = 0;
    dispatch_sync(g_audio_queue, ^{
        if (!g_slot_has_sound[slot]) {
            os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Slot %d has no sound loaded", slot);
            rc = -1;
            return;
        }
        
        // If already playing, stop first to restart from beginning
        if (ma_sound_is_playing(&g_slot_sounds[slot])) {
            ma_sound_stop(&g_slot_sounds[slot]);
        }
        
        // Seek to beginning to ensure restart
        ma_sound_seek_to_pcm_frame(&g_slot_sounds[slot], 0);
        
        ma_result result = ma_sound_start(&g_slot_sounds[slot]);
        if (result != MA_SUCCESS) {
            LOG_MA_ERROR(result, "Failed to start slot sound");
            rc = -1;
        } else {
            os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Slot %d restarted from beginning", slot);
        }
    });
    return rc;
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_slot(int slot) {
    if (!g_is_initialized) {
        os_log_error(OS_LOG_DEFAULT, "🔴 [MINIAUDIO] Engine not initialized");
        return;
    }
    if (!validate_slot(slot)) return;
    dispatch_sync(g_audio_queue, ^{
        if (g_slot_has_sound[slot]) {
            ma_sound_stop(&g_slot_sounds[slot]);
        }
    });
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_unload_slot(int slot) {
    if (!g_is_initialized) return;
    if (!validate_slot(slot)) return;
    dispatch_sync(g_audio_queue, ^{
        free_slot_resources(slot);
    });
}

// -----------------------------
// Misc helpers
// -----------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_initialized(void) {
    return g_is_initialized;
}

// Debug functions removed - Bluetooth audio is working correctly

// Extend cleanup to release slot resources
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void) {
    os_log(OS_LOG_DEFAULT, "🧹 [MINIAUDIO] Cleaning up");
    if (!g_is_initialized) return;

    // Legacy sound cleanup
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
        ma_sound_uninit(&g_sound);
    }

    // Free slots
    dispatch_sync(g_audio_queue, ^{
        for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
            free_slot_resources(i);
        }
    });

    // Free other resources (existing code moved here)
    if (g_current_file_path != NULL) {
        free(g_current_file_path);
        g_current_file_path = NULL;
    }
    if (g_has_loaded_sound) {
        ma_resource_manager_data_source_uninit(&g_loaded_sound);
        g_has_loaded_sound = 0;
    }

    ma_engine_uninit(&g_engine);
    ma_resource_manager_uninit(&g_resource_manager);

    g_is_initialized = 0;
    if (g_audio_queue != NULL) {
        // queues are automatically cleaned up; nothing to free
    }
    os_log(OS_LOG_DEFAULT, "✅ [MINIAUDIO] Cleanup completed successfully");
} 