#include "miniaudio_wrapper.h"

// Platform-specific includes and definitions
#ifdef __APPLE__
    #include <os/log.h>
    #include <pthread.h>
    // iOS Audio Session for Bluetooth routing
    #import <AVFoundation/AVFoundation.h>
    
    // Configure miniaudio implementation for iOS (CoreAudio only)
    // Disable AVFoundation in miniaudio to prevent DefaultToSpeaker override
    #define MA_NO_AVFOUNDATION          // CRITICAL: Prevent miniaudio from setting DefaultToSpeaker
    #define MA_NO_RUNTIME_LINKING       // we link statically
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_COREAUDIO         // use CoreAudio backend
    #define MA_ENABLE_NULL              // keep null device for testing
    
    // Logging macros for iOS
    #define prnt(fmt, ...) os_log(OS_LOG_DEFAULT, fmt, ##__VA_ARGS__)
    #define prnt_err(fmt, ...) os_log_error(OS_LOG_DEFAULT, fmt, ##__VA_ARGS__)
    
#elif defined(__ANDROID__)
    #include <android/log.h>
    #include <pthread.h>
    
    // Configure miniaudio implementation for Android
    #define MA_NO_RUNTIME_LINKING
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_AAUDIO           // Android's preferred audio API
    #define MA_ENABLE_OPENSL           // Fallback for older Android
    #define MA_ENABLE_NULL             // keep null device for testing
    
    // Logging macros for Android
    #define prnt(fmt, ...) __android_log_print(ANDROID_LOG_DEBUG, "audio", fmt, ##__VA_ARGS__)
    #define prnt_err(fmt, ...) __android_log_print(ANDROID_LOG_ERROR, "audio", fmt, ##__VA_ARGS__)
    
#else
    #include <stdio.h>
    #include <pthread.h>
    
    // Configure miniaudio for other platforms (Linux, Windows, etc.)
    #define MA_NO_RUNTIME_LINKING
    
    // Logging macros for other platforms (simple printf)
    #define prnt(fmt, ...) printf("[audio] " fmt "\n", ##__VA_ARGS__)
    #define prnt_err(fmt, ...) printf("[audio error] " fmt "\n", ##__VA_ARGS__)
#endif

// -----------------------------------------------------------------------------
// Configure miniaudio implementation (common for all platforms)
// -----------------------------------------------------------------------------
#define MINIAUDIO_IMPLEMENTATION

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

// Cross-platform threading primitives (using pthread for consistency)
static pthread_mutex_t g_audio_mutex = PTHREAD_MUTEX_INITIALIZER;

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
static uint64_t                        g_slot_memory_sizes[MINIAUDIO_MAX_SLOTS]      = {0}; // Track memory usage per slot
static uint64_t                        g_total_memory_used                            = 0;   // Total memory used

#define LOG_MA_ERROR(result, message) \
    prnt_err("🔴 [miniaudio] Error: %s - %s", message, ma_result_description(result))

// -----------------------------------------------------------------------------
// Cross-platform threading helpers (unified pthread implementation)
// -----------------------------------------------------------------------------
#define THREAD_SAFE_EXEC(code) do { \
    pthread_mutex_lock(&g_audio_mutex); \
    code \
    pthread_mutex_unlock(&g_audio_mutex); \
} while(0)

static int init_threading(void) {
    return pthread_mutex_init(&g_audio_mutex, NULL);
}

static void cleanup_threading(void) {
    pthread_mutex_destroy(&g_audio_mutex);
}

// -----------------------------------------------------------------------------
// iOS Audio Session Configuration for Bluetooth Support (iOS only)
// -----------------------------------------------------------------------------
#ifdef __APPLE__
static int configure_ios_audio_session(void) {
    prnt("🔧 [AUDIO SESSION] Configuring iOS audio session...");
    
    // Check if AVAudioSession class exists at runtime
    Class audioSessionClass = NSClassFromString(@"AVAudioSession");
    if (audioSessionClass == nil) {
        prnt_err("🔴 [DEBUG] AVAudioSession class not found at runtime!");
        return -1;
    }
    prnt("🔍 [DEBUG] AVAudioSession class found successfully");
    
    @try {
        prnt("🔍 [DEBUG] Getting AVAudioSession sharedInstance...");
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        if (session == nil) {
            prnt_err("🔴 [DEBUG] AVAudioSession sharedInstance returned nil!");
            return -1;
        }
        
        prnt("🔍 [DEBUG] Session obtained successfully");
        
        // Try full Bluetooth configuration first
        prnt("🔍 [DEBUG] Setting category with Bluetooth options...");
        BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                           AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                           AVAudioSessionCategoryOptionDefaultToSpeaker
                                       error:&error];
        
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed full config: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            
            // Fallback: Try basic playback category only
            prnt("🔧 [AUDIO SESSION] Trying fallback basic configuration...");
            error = nil;  // Reset error
            success = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
            if (!success) {
                prnt_err("🔴 [AUDIO SESSION] Even basic config failed: %@ (Code: %ld)", 
                             error.localizedDescription, (long)error.code);
                return -1;
            }
        }
        prnt("✅ [AUDIO SESSION] Category set successfully");
        
        // Set mode for general audio
        prnt("🔍 [DEBUG] Setting mode...");
        error = nil;  // Reset error
        success = [session setMode:AVAudioSessionModeDefault error:&error];
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed to set mode: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        prnt("✅ [AUDIO SESSION] Mode set successfully");
        
        // Activate the session
        prnt("🔍 [DEBUG] Activating session...");
        error = nil;  // Reset error
        success = [session setActive:YES error:&error];
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed to activate: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        prnt("✅ [AUDIO SESSION] Session activated successfully");
        
        // Log current route for debugging
        prnt("🔍 [DEBUG] Logging route after configuration...");
        AVAudioSessionRouteDescription *route = session.currentRoute;
        for (AVAudioSessionPortDescription *output in route.outputs) {
            prnt("🎧 [AUDIO SESSION] Current output: %@ (%@)", 
                   output.portName, output.portType);
        }
        
        prnt("✅ [AUDIO SESSION] Configured for Bluetooth support");
        return 0;
    } @catch (NSException *exception) {
        prnt_err("🔴 [DEBUG] Exception in configure_ios_audio_session: %@", exception.reason);
        return -1;
    }
}

// -----------------------------------------------------------------------------
// Public function to re-activate Bluetooth audio session from Flutter
// -----------------------------------------------------------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void) {
    prnt("🔄 [AUDIO SESSION] Re-configuring audio session for Bluetooth...");
    return configure_ios_audio_session();
}
#else
// Stub implementations for non-iOS platforms
static int configure_ios_audio_session(void) {
    prnt("ℹ️ [AUDIO SESSION] Audio session configuration not needed on this platform");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void) {
    prnt("ℹ️ [AUDIO SESSION] Audio session reconfiguration not needed on this platform");
    return 0;
}
#endif

// -----------------------------------------------------------------------------
// Public API exposed through FFI
// -----------------------------------------------------------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_init(void) {
    if (g_is_initialized) {
        prnt("ℹ️ [MINIAUDIO] Engine already initialized");
        return 0;
    }
    
    prnt("🚀 [MINIAUDIO] Starting initialization process...");
    
    // Configure audio session for platform-specific audio routing BEFORE miniaudio init
    prnt("🔧 [MINIAUDIO] Configuring audio session BEFORE engine init...");
    if (configure_ios_audio_session() != 0) {
        prnt_err("⚠️ [MINIAUDIO] Audio session config failed, continuing with default");
        // Don't return error - continue with miniaudio initialization
    } else {
        prnt("✅ [MINIAUDIO] Audio session configured successfully");
    }
    
    // Initialize threading
    if (init_threading() != 0) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize threading");
        return -1;
    }
    
    // Initialize resource manager first
    prnt("🔧 [MINIAUDIO] Initializing resource manager...");
    ma_resource_manager_config resource_manager_config = ma_resource_manager_config_init();
    ma_result result = ma_resource_manager_init(&resource_manager_config, &g_resource_manager);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize resource manager");
        cleanup_threading();
        return -1;
    }
    
    // Initialize engine with resource manager
    prnt("🔧 [MINIAUDIO] Initializing engine...");
    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.pResourceManager = &g_resource_manager;
    
    result = ma_engine_init(&engine_config, &g_engine);
    if (result != MA_SUCCESS) {
        LOG_MA_ERROR(result, "Failed to initialize engine");
        ma_resource_manager_uninit(&g_resource_manager);
        cleanup_threading();
        return -1;
    }
    
    // Ensure slot arrays are zeroed (already static init, but be explicit)
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        g_slot_has_sound[i]        = 0;
        g_slot_loaded_in_memory[i] = 0;
        g_slot_file_paths[i]       = NULL;
        g_slot_sounds[i].pDataSource = NULL;
    }
    
    g_is_initialized = 1;
    prnt("✅ [MINIAUDIO] Engine initialized successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_sound(const char* file_path) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (file_path == NULL || strlen(file_path) == 0) {
        prnt_err("🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }
    
    prnt("▶️ [MINIAUDIO] Attempting to play sound: %s", file_path);
    
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
    
    prnt("✅ [MINIAUDIO] Sound started successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Engine not initialized");
        return;
    }
    
    prnt("⏹️ [MINIAUDIO] Stopping all sounds");
    
    // Stop single legacy sound
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
    }

    // Stop all slot sounds safely using cross-platform threading
    THREAD_SAFE_EXEC({
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
        prnt_err("🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (file_path == NULL || strlen(file_path) == 0) {
        prnt_err("🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }
    
    prnt("📥 [MINIAUDIO] Loading sound into memory: %s", file_path);
    
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
    prnt( "✅ [MINIAUDIO] Sound loaded into memory successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_loaded_sound(void) {
    if (!g_is_initialized) {
        prnt_err( "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    
    if (!g_has_loaded_sound) {
        prnt_err( "🔴 [MINIAUDIO] No sound loaded in memory");
        return -1;
    }
    
    prnt( "▶️ [MINIAUDIO] Playing loaded sound");
    
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
    
    prnt( "✅ [MINIAUDIO] Loaded sound started successfully");
    return 0;
}

// -----------------------------
// Utility helpers
// -----------------------------
static int validate_slot(int slot) {
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err( "🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return 0;
    }
    return 1;
}

// Helper function to calculate memory size of a loaded audio sample
static uint64_t calculate_sample_memory_size(ma_resource_manager_data_source* data_source) {
    if (data_source == NULL) return 0;
    
    ma_uint64 lengthInPCMFrames;
    ma_result result = ma_resource_manager_data_source_get_length_in_pcm_frames(data_source, &lengthInPCMFrames);
    if (result != MA_SUCCESS) {
        return 0;
    }
    
    ma_format format;
    ma_uint32 channels;
    ma_uint32 sampleRate;
    result = ma_resource_manager_data_source_get_data_format(data_source, &format, &channels, &sampleRate, NULL, 0);
    if (result != MA_SUCCESS) {
        return 0;
    }
    
    // Calculate memory usage: frames * channels * bytes_per_sample
    uint32_t bytesPerSample = ma_get_bytes_per_sample(format);
    uint64_t totalBytes = lengthInPCMFrames * channels * bytesPerSample;
    
    return totalBytes;
}

static void free_slot_resources(int slot) {
    // Assumes dispatch_sync already protecting
    if (g_slot_has_sound[slot]) {
        ma_sound_uninit(&g_slot_sounds[slot]);
        if (g_slot_loaded_in_memory[slot]) {
            // Update memory tracking before freeing
            g_total_memory_used -= g_slot_memory_sizes[slot];
            g_slot_memory_sizes[slot] = 0;
            
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
        prnt_err( "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    if (!validate_slot(slot)) return -1;
    if (file_path == NULL || strlen(file_path) == 0) {
        prnt_err( "🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }

    int resultCode = 0;
    THREAD_SAFE_EXEC({
        // Cleanup existing resources in the slot first
        free_slot_resources(slot);

        // Store new path copy for diagnostics / future reloads
        g_slot_file_paths[slot] = strdup(file_path);

        ma_result result;
        if (loadToMemory) {
            prnt( "📥 [MINIAUDIO] Slot %d loading (memory) %s", slot, file_path);
            result = ma_resource_manager_data_source_init(&g_resource_manager,
                                                          file_path,
                                                          MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_DECODE,
                                                          NULL,
                                                          &g_slot_data_sources[slot]);
            if (result == MA_SUCCESS) {
                // Calculate memory usage for this sample
                uint64_t memorySize = calculate_sample_memory_size(&g_slot_data_sources[slot]);
                g_slot_memory_sizes[slot] = memorySize;
                g_total_memory_used += memorySize;
                
                result = ma_sound_init_from_data_source(&g_engine, &g_slot_data_sources[slot], 0, NULL, &g_slot_sounds[slot]);
                if (result == MA_SUCCESS) {
                    g_slot_loaded_in_memory[slot] = 1;
                    g_slot_has_sound[slot] = 1;
                    
                    // Log memory usage
                    prnt( "💾 [MINIAUDIO] Slot %d loaded %llu bytes (%.2f MB) - Total: %.2f MB", 
                           slot, memorySize, memorySize / (1024.0 * 1024.0), g_total_memory_used / (1024.0 * 1024.0));
                } else {
                    LOG_MA_ERROR(result, "Failed to init sound from data source");
                    // Rollback memory tracking
                    g_total_memory_used -= g_slot_memory_sizes[slot];
                    g_slot_memory_sizes[slot] = 0;
                    ma_resource_manager_data_source_uninit(&g_slot_data_sources[slot]);
                    resultCode = -1;
                }
            } else {
                LOG_MA_ERROR(result, "Failed to load data source");
                resultCode = -1;
            }
        } else {
            prnt( "📥 [MINIAUDIO] Slot %d loading (stream) %s", slot, file_path);
            result = ma_sound_init_from_file(&g_engine, file_path, 0, NULL, NULL, &g_slot_sounds[slot]);
            if (result == MA_SUCCESS) {
                g_slot_loaded_in_memory[slot] = 0;
                g_slot_memory_sizes[slot] = 0; // Streaming uses no additional memory
                g_slot_has_sound[slot] = 1;
            } else {
                LOG_MA_ERROR(result, "Failed to init sound from file");
                resultCode = -1;
            }
        }
    });
    return resultCode;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err( "🔴 [MINIAUDIO] Engine not initialized");
        return -1;
    }
    if (!validate_slot(slot)) return -1;
    int rc = 0;
    THREAD_SAFE_EXEC({
        if (g_slot_has_sound[slot]) {
            // If already playing, stop first to restart from beginning
            if (ma_sound_is_playing(&g_slot_sounds[slot])) {
                ma_sound_stop(&g_slot_sounds[slot]);
            }
            
            // Seek to beginning to ensure restart
            ma_sound_seek_to_pcm_frame(&g_slot_sounds[slot], 0);
            
            ma_result result = ma_sound_start(&g_slot_sounds[slot]);
            if (result == MA_SUCCESS) {
                prnt( "✅ [MINIAUDIO] Slot %d restarted from beginning", slot);
            } else {
                LOG_MA_ERROR(result, "Failed to start slot sound");
                rc = -1;
            }
        } else {
            prnt_err( "🔴 [MINIAUDIO] Slot %d has no sound loaded", slot);
            rc = -1;
        }
    });
    return rc;
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err( "🔴 [MINIAUDIO] Engine not initialized");
        return;
    }
    if (!validate_slot(slot)) return;
    THREAD_SAFE_EXEC({
        if (g_slot_has_sound[slot]) {
            ma_sound_stop(&g_slot_sounds[slot]);
        }
    });
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_unload_slot(int slot) {
    if (!g_is_initialized) return;
    if (!validate_slot(slot)) return;
    THREAD_SAFE_EXEC({
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

// Memory usage tracking functions
__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_total_memory_usage(void) {
    return g_total_memory_used;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_slot_memory_usage(int slot) {
    if (!validate_slot(slot)) return 0;
    return g_slot_memory_sizes[slot];
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_get_memory_slot_count(void) {
    int count = 0;
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        if (g_slot_loaded_in_memory[i]) {
            count++;
        }
    }
    return count;
}

// Debug functions removed - Bluetooth audio is working correctly

// Extend cleanup to release slot resources
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void) {
    prnt( "🧹 [MINIAUDIO] Cleaning up");
    if (!g_is_initialized) return;

    // Legacy sound cleanup
    if (g_sound.pDataSource != NULL) {
        ma_sound_stop(&g_sound);
        ma_sound_uninit(&g_sound);
    }

    // Free slots
    THREAD_SAFE_EXEC({
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
    cleanup_threading();
    prnt( "✅ [MINIAUDIO] Cleanup completed successfully");
} 