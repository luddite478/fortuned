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
#include <stdlib.h>

// -----------------------------------------------------------------------------
// Simplified Mixing Implementation (Following Official miniaudio Pattern)
// -----------------------------------------------------------------------------
#define MINIAUDIO_MAX_SLOTS 96
#define SAMPLE_FORMAT   ma_format_f32
#define CHANNEL_COUNT   2
#define SAMPLE_RATE     48000

// Memory safety limits
#define MAX_MEMORY_SLOTS 32                           // Max 32 memory slots out of 96 total
#define MAX_MEMORY_FILE_SIZE (50 * 1024 * 1024)      // 50MB per individual file
#define MAX_TOTAL_MEMORY_USAGE (500 * 1024 * 1024)   // 500MB total memory usage limit

// Simplified slot structure - uses ma_decoder for both file and memory
typedef struct {
    ma_decoder decoder;        // Single decoder handles both file and memory
    void* memory_data;         // NULL for file mode, allocated buffer for memory mode
    size_t memory_size;        // 0 for file mode, actual size for memory mode
    int active;
    int at_end;
    int loaded;
    char* file_path;
} audio_slot_t;

static ma_device g_device;
static audio_slot_t g_slots[MINIAUDIO_MAX_SLOTS];
static int g_is_initialized = 0;
static uint64_t g_total_memory_used = 0;

// Output recording state (following simple_capture example pattern)
static ma_encoder g_output_encoder;
static int g_is_output_recording = 0;
static uint64_t g_recording_start_time = 0;
static uint64_t g_total_frames_written = 0;

// Note: Thread safety removed for simplicity - miniaudio handles internal synchronization

// Helper function to load entire audio file into memory buffer
static int load_file_to_memory_buffer(const char* file_path, void** memory_data, size_t* memory_size) {
    FILE* file = fopen(file_path, "rb");
    if (!file) {
        prnt_err("🔴 [RAM] Failed to open file: %s", file_path);
        return -1;
    }
    
    // Get file size
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    if (file_size <= 0) {
        prnt_err("🔴 [RAM] Invalid file size: %ld", file_size);
        fclose(file);
        return -1;
    }
    
    // Allocate memory for entire file
    void* buffer = malloc(file_size);
    if (!buffer) {
        prnt_err("🔴 [RAM] Failed to allocate %.2f MB for file buffer", file_size / (1024.0 * 1024.0));
        fclose(file);
        return -1;
    }
    
    // Read entire file into memory
    size_t bytes_read = fread(buffer, 1, file_size, file);
    fclose(file);
    
    if (bytes_read != (size_t)file_size) {
        prnt_err("🔴 [RAM] Failed to read complete file: read %zu/%ld bytes", bytes_read, file_size);
        free(buffer);
        return -1;
    }
    
    *memory_data = buffer;
    *memory_size = file_size;
    
    prnt("💾 [RAM] Loaded %.2f MB file into memory", file_size / (1024.0 * 1024.0));
    return 0;
}

// Helper functions for memory limit checking
static int get_current_memory_slot_count(void) {
    int count = 0;
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        if (g_slots[i].memory_data) {
            count++;
        }
    }
    return count;
}

static int check_memory_limits(size_t file_size) {
    // Check individual file size limit
    if (file_size > MAX_MEMORY_FILE_SIZE) {
        prnt_err("🔴 [MEMORY LIMIT] File too large: %.2f MB (max: %.2f MB)", 
                 file_size / (1024.0 * 1024.0), MAX_MEMORY_FILE_SIZE / (1024.0 * 1024.0));
        return -1;
    }
    
    // Check memory slot count limit
    int current_memory_slots = get_current_memory_slot_count();
    if (current_memory_slots >= MAX_MEMORY_SLOTS) {
        prnt_err("🔴 [MEMORY LIMIT] Too many memory slots: %d/%d (max: %d)", 
                 current_memory_slots, MINIAUDIO_MAX_SLOTS, MAX_MEMORY_SLOTS);
        return -1;
    }
    
    // Check total memory usage limit
    if (g_total_memory_used + file_size > MAX_TOTAL_MEMORY_USAGE) {
        prnt_err("🔴 [MEMORY LIMIT] Total memory would exceed limit: %.2f MB + %.2f MB > %.2f MB", 
                 g_total_memory_used / (1024.0 * 1024.0),
                 file_size / (1024.0 * 1024.0),
                 MAX_TOTAL_MEMORY_USAGE / (1024.0 * 1024.0));
        return -1;
    }
    
    return 0;
}

// Clean helper functions for loading sounds
static int load_sound_to_memory(audio_slot_t* slot, const char* file_path, ma_decoder_config* config, int slot_index) {
    // Load file to memory buffer
    if (load_file_to_memory_buffer(file_path, &slot->memory_data, &slot->memory_size) != 0) {
        prnt_err("🔴 [MINIAUDIO] Failed to load slot %d to memory", slot_index);
        return -1;
    }
    
    // Check memory limits
    if (check_memory_limits(slot->memory_size) != 0) {
        prnt_err("🔴 [MINIAUDIO] Memory limits exceeded for slot %d", slot_index);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    
    // Create decoder from memory
    ma_result ma_res = ma_decoder_init_memory(slot->memory_data, slot->memory_size, config, &slot->decoder);
    if (ma_res != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create decoder from memory for slot %d: %s", 
                 slot_index, ma_result_description(ma_res));
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    
    // Success - update tracking
    g_total_memory_used += slot->memory_size;
    slot->loaded = 1;
    
    prnt("✅ [MINIAUDIO] Slot %d loaded to memory (%.2f MB) [%d/%d memory slots, %.2f/%.2f MB total]", 
         slot_index, slot->memory_size / (1024.0 * 1024.0),
         get_current_memory_slot_count(), MAX_MEMORY_SLOTS,
         g_total_memory_used / (1024.0 * 1024.0), 
         MAX_TOTAL_MEMORY_USAGE / (1024.0 * 1024.0));
    
    return 0;
}

static int load_sound_from_file(audio_slot_t* slot, const char* file_path, ma_decoder_config* config, int slot_index) {
    ma_result ma_res = ma_decoder_init_file(file_path, config, &slot->decoder);
    if (ma_res != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize decoder for slot %d: %s", 
                 slot_index, ma_result_description(ma_res));
        return -1;
    }
    
    slot->loaded = 1;
    prnt("✅ [MINIAUDIO] Slot %d loaded for streaming", slot_index);
    return 0;
}

// Mix one slot into the output buffer
static void mix_slot_audio(audio_slot_t* slot, float* output, ma_uint32 frameCount) {
    static float temp[4096];
    static const ma_uint32 tempCapInFrames = sizeof(temp) / sizeof(float) / CHANNEL_COUNT;
    
    ma_uint32 totalFramesRead = 0;
    while (totalFramesRead < frameCount) {
        ma_uint32 framesToRead = tempCapInFrames;
        if (framesToRead > frameCount - totalFramesRead) {
            framesToRead = frameCount - totalFramesRead;
        }

        ma_uint64 framesReadThisIteration = 0;
        ma_result result = ma_decoder_read_pcm_frames(&slot->decoder, temp, framesToRead, &framesReadThisIteration);
        
        // Check for end of audio or error
        if (result != MA_SUCCESS || framesReadThisIteration == 0) {
            slot->at_end = 1;
            break;
        }

        // Mix by summing samples (official miniaudio approach)
        for (ma_uint64 i = 0; i < framesReadThisIteration * CHANNEL_COUNT; ++i) {
            output[totalFramesRead * CHANNEL_COUNT + i] += temp[i];
        }
        
        totalFramesRead += (ma_uint32)framesReadThisIteration;

        // Check if we reached end of file
        if (framesReadThisIteration < framesToRead) {
            slot->at_end = 1;
            break;
        }
    }
}

// Official miniaudio Simple Mixing data callback (exactly like the example)
static void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    float* pOutputF32 = (float*)pOutput;
    memset(pOutputF32, 0, sizeof(float) * frameCount * CHANNEL_COUNT);

    // Mix all active slots
    for (int slot = 0; slot < MINIAUDIO_MAX_SLOTS; ++slot) {
        audio_slot_t* s = &g_slots[slot];
        
        // Skip inactive, unloaded, or finished slots
        if (!s->active || !s->loaded || s->at_end) {
            continue;
        }

        mix_slot_audio(s, pOutputF32, frameCount);
    }
    
    // If recording, write the mixed output to the encoder (following simple_capture example)
    if (g_is_output_recording) {
        ma_encoder_write_pcm_frames(&g_output_encoder, pOutputF32, frameCount, NULL);
        g_total_frames_written += frameCount;
    }
    
    (void)pInput;
    (void)pDevice;
}

static void free_slot_resources(int slot) {
    audio_slot_t* s = &g_slots[slot];
    
    if (s->loaded) {
        ma_decoder_uninit(&s->decoder);
        s->loaded = 0;
    }
    
    if (s->memory_data) {
        g_total_memory_used -= s->memory_size;
        free(s->memory_data);
        s->memory_data = NULL;
        prnt("🗑️ [RAM] Freed %.2f MB from slot %d", s->memory_size / (1024.0 * 1024.0), slot);
        s->memory_size = 0;
    }
    
    if (s->file_path) {
        free(s->file_path);
        s->file_path = NULL;
    }
    
    s->active = 0;
    s->at_end = 0;
}

// -----------------------------------------------------------------------------
// iOS Audio Session Configuration for Bluetooth Support (iOS only)
// -----------------------------------------------------------------------------
#ifdef __APPLE__
static int configure_ios_audio_session(void) {
    prnt("🔧 [AUDIO SESSION] Configuring iOS audio session...");
    
    Class audioSessionClass = NSClassFromString(@"AVAudioSession");
    if (audioSessionClass == nil) {
        prnt_err("🔴 [DEBUG] AVAudioSession class not found at runtime!");
        return -1;
    }
    
    @try {
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        if (session == nil) {
            prnt_err("🔴 [DEBUG] AVAudioSession sharedInstance returned nil!");
            return -1;
        }
        
        BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                           AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                           AVAudioSessionCategoryOptionDefaultToSpeaker
                                       error:&error];
        
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed full config: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            
            error = nil;
            success = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
            if (!success) {
                prnt_err("🔴 [AUDIO SESSION] Even basic config failed: %@ (Code: %ld)", 
                             error.localizedDescription, (long)error.code);
                return -1;
            }
        }
        
        error = nil;
        success = [session setMode:AVAudioSessionModeDefault error:&error];
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed to set mode: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        
        error = nil;
        success = [session setActive:YES error:&error];
        if (!success) {
            prnt_err("🔴 [AUDIO SESSION] Failed to activate: %@ (Code: %ld)", 
                         error.localizedDescription, (long)error.code);
            return -1;
        }
        
        prnt("✅ [AUDIO SESSION] Configured for Bluetooth support");
        return 0;
    } @catch (NSException *exception) {
        prnt_err("🔴 [DEBUG] Exception in configure_ios_audio_session: %@", exception.reason);
        return -1;
    }
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void) {
    prnt("🔄 [AUDIO SESSION] Re-configuring audio session for Bluetooth...");
    return configure_ios_audio_session();
}
#else
static int configure_ios_audio_session(void) {
    return 0; // No-op on non-iOS platforms
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void) {
    return 0; // No-op on non-iOS platforms
}
#endif

// -----------------------------------------------------------------------------
// Public FFI API
// -----------------------------------------------------------------------------
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_init(void) {
    if (g_is_initialized) {
        prnt("ℹ️ [MINIAUDIO] Engine already initialized");
        return 0;
    }
    
    prnt("🚀 [MINIAUDIO] Starting initialization process...");
    
    // Configure iOS audio session for Bluetooth BEFORE miniaudio init
#ifdef __APPLE__
    prnt("🔧 [MINIAUDIO] Configuring audio session BEFORE device init...");
    if (configure_ios_audio_session() != 0) {
        prnt_err("⚠️ [MINIAUDIO] Audio session config failed, continuing with default");
    } else {
        prnt("✅ [MINIAUDIO] Audio session configured successfully");
    }
#endif
    
    // Initialize slot arrays
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        memset(&g_slots[i], 0, sizeof(audio_slot_t));
    }
    g_total_memory_used = 0;
    
    // Threading removed for simplicity
    
    // Configure and initialize device
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = SAMPLE_FORMAT;
    deviceConfig.playback.channels = CHANNEL_COUNT;
    deviceConfig.sampleRate = SAMPLE_RATE;
    deviceConfig.dataCallback = data_callback;
    deviceConfig.pUserData = NULL;
    
    ma_result result = ma_device_init(NULL, &deviceConfig, &g_device);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize device: %s", ma_result_description(result));
        return -1;
    }
    
    result = ma_device_start(&g_device);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to start device: %s", ma_result_description(result));
        ma_device_uninit(&g_device);
        return -2;
    }
    
    g_is_initialized = 1;
    prnt("✅ [MINIAUDIO] Device initialized and started successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_get_slot_count(void) {
    return MINIAUDIO_MAX_SLOTS;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_slot_loaded(int slot) {
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return 0;
    }
    return g_slots[slot].loaded;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_load_sound_to_slot(int slot, const char* file_path, int loadToMemory) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return -1;
    }
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return -1;
    }
    if (file_path == NULL || strlen(file_path) == 0) {
        prnt_err("🔴 [MINIAUDIO] Invalid file path");
        return -1;
    }
    
    prnt("📥 [MINIAUDIO] Loading sound to slot %d: %s (memory: %s)", slot, file_path, loadToMemory ? "yes" : "no");
    
    // Free existing resources in the slot
    free_slot_resources(slot);
    
    audio_slot_t* s = &g_slots[slot];
    s->file_path = strdup(file_path);
    
    ma_decoder_config decoderConfig = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    
    int result;
    if (loadToMemory) {
        result = load_sound_to_memory(s, file_path, &decoderConfig, slot);
    } else {
        result = load_sound_from_file(s, file_path, &decoderConfig, slot);
    }
    
    if (result == 0) {
        s->active = 0;
        s->at_end = 0;
    } else {
        // Cleanup on failure
        free_slot_resources(slot);
    }
    
    return result;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return -1;
    }
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return -1;
    }
    
    audio_slot_t* s = &g_slots[slot];
    
    // Check if slot is loaded
    if (!s->loaded) {
        prnt_err("🔴 [MINIAUDIO] Slot %d has no sound loaded", slot);
        return -1;
    }
    
    // Seek to beginning (works for both file and memory decoders)
    ma_result ma_res = ma_decoder_seek_to_pcm_frame(&s->decoder, 0);
    if (ma_res != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to seek slot %d to beginning: %s", slot, ma_result_description(ma_res));
        return -1;
    }
    
    // Success - start playing
    s->active = 1;
    s->at_end = 0;
    prnt("✅ [MINIAUDIO] Slot %d started playing (%s)", slot, s->memory_data ? "memory" : "file");
    
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return;
    }
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return;
    }
    
    g_slots[slot].active = 0;
    prnt("⏹️ [MINIAUDIO] Slot %d stopped", slot);
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_unload_slot(int slot) {
    if (!g_is_initialized) return;
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return;
    }
    
    free_slot_resources(slot);
    prnt("🗑️ [MINIAUDIO] Slot %d unloaded", slot);
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_all_sounds(void) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return;
    }
    
    prnt("⏹️ [MINIAUDIO] Stopping all sounds");
    
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        g_slots[i].active = 0;
    }
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_initialized(void) {
    return g_is_initialized;
}

// Memory tracking functions
__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_total_memory_usage(void) {
    return g_total_memory_used;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_slot_memory_usage(int slot) {
    if (slot < 0 || slot >= MINIAUDIO_MAX_SLOTS) return 0;
    return g_slots[slot].memory_data ? g_slots[slot].memory_size : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_get_memory_slot_count(void) {
    return get_current_memory_slot_count();
}

// Memory limit information functions
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_get_max_memory_slots(void) {
    return MAX_MEMORY_SLOTS;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_max_memory_file_size(void) {
    return MAX_MEMORY_FILE_SIZE;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_max_total_memory_usage(void) {
    return MAX_TOTAL_MEMORY_USAGE;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_available_memory_capacity(void) {
    if (g_total_memory_used >= MAX_TOTAL_MEMORY_USAGE) {
        return 0;
    }
    return MAX_TOTAL_MEMORY_USAGE - g_total_memory_used;
}

// Legacy compatibility functions (no longer used but kept for compatibility)
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_sound(const char* file_path) {
    prnt("ℹ️ [MINIAUDIO] Legacy play_sound called, use slot-based API instead");
    return -1;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_load_sound(const char* file_path) {
    prnt("ℹ️ [MINIAUDIO] Legacy load_sound called, use slot-based API instead");
    return -1;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_loaded_sound(void) {
    prnt("ℹ️ [MINIAUDIO] Legacy play_loaded_sound called, use slot-based API instead");
    return -1;
}

__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_log_audio_route(void) {
    prnt("ℹ️ [MINIAUDIO] Audio route logging not implemented in Simple Mixing");
}

// Output recording functions (following simple_capture example pattern)
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_start_output_recording(const char* output_file_path) {
    if (!g_is_initialized) {
        prnt_err("🔴 [RECORDING] Device not initialized");
        return -1;
    }
    
    if (g_is_output_recording) {
        prnt_err("🔴 [RECORDING] Already recording, stop first");
        return -1;
    }
    
    prnt("🎙️ [RECORDING] Starting output recording to: %s", output_file_path);
    
    // Configure encoder for WAV output (following simple_capture example)
    ma_encoder_config encoderConfig = ma_encoder_config_init(ma_encoding_format_wav, SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    
    ma_result result = ma_encoder_init_file(output_file_path, &encoderConfig, &g_output_encoder);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [RECORDING] Failed to initialize encoder: %s", ma_result_description(result));
        return -1;
    }
    
    g_is_output_recording = 1;
    g_recording_start_time = 0; // Will use frame-based timing instead
    g_total_frames_written = 0;
    
    prnt("✅ [RECORDING] Output recording started successfully");
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_stop_output_recording(void) {
    if (!g_is_output_recording) {
        prnt_err("🔴 [RECORDING] Not currently recording");
        return -1;
    }
    
    prnt("⏹️ [RECORDING] Stopping output recording...");
    
    // Get duration before cleanup
    uint64_t duration_ms = miniaudio_get_recording_duration_ms();
    
    // Finalize and cleanup encoder
    ma_encoder_uninit(&g_output_encoder);
    g_is_output_recording = 0;
    g_recording_start_time = 0;
    g_total_frames_written = 0;
    
    prnt("✅ [RECORDING] Output recording stopped (duration: %llu ms)", duration_ms);
    return 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_output_recording(void) {
    return g_is_output_recording;
}

__attribute__((visibility("default"))) __attribute__((used))
uint64_t miniaudio_get_recording_duration_ms(void) {
    if (!g_is_output_recording || !g_is_initialized) {
        return 0;
    }
    
    // Calculate duration from frames written
    // Duration = (frames_written / sample_rate) * 1000 (for milliseconds)
    return (g_total_frames_written * 1000) / SAMPLE_RATE;
}

// Cleanup function
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void) {
    if (!g_is_initialized) return;
    
    prnt("🧹 [MINIAUDIO] Starting cleanup...");
    
    // Stop recording if active
    if (g_is_output_recording) {
        miniaudio_stop_output_recording();
    }
    
    // Stop device first
    ma_device_stop(&g_device);
    
    // Free all slot resources
    for (int i = 0; i < MINIAUDIO_MAX_SLOTS; ++i) {
        free_slot_resources(i);
    }
    
    // Uninitialize device
    ma_device_uninit(&g_device);
    
    g_total_memory_used = 0;
    g_is_initialized = 0;
    prnt("✅ [MINIAUDIO] Cleanup completed successfully");
} 