#include "sequencer.h"

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
#include "miniaudio/miniaudio.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// -----------------------------------------------------------------------------
// Simplified Mixing Implementation (Following Official miniaudio Pattern)
// -----------------------------------------------------------------------------
#define MAX_SLOTS 1024
#define SAMPLE_FORMAT   ma_format_f32
#define CHANNEL_COUNT   2
#define SAMPLE_RATE     48000

// Memory safety limits
#define MAX_MEMORY_SLOTS 128                          // Up to 128 fully memory-loaded sounds
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

    // Node-graph specific members.
    ma_data_source_node node;   // Node wrapping this decoder for graph-based mixing.
    int node_initialized;       // 1 when the node has been successfully initialised and attached.
} audio_slot_t;

static ma_device g_device;
// Node graph which will handle mixing of all slot nodes.
static ma_node_graph g_nodeGraph;
static audio_slot_t g_slots[MAX_SLOTS];
static int g_is_initialized = 0;
static uint64_t g_total_memory_used = 0;

// Output recording state (following simple_capture example pattern)
static ma_encoder g_output_encoder;
static int g_is_output_recording = 0;
static uint64_t g_recording_start_time = 0;
static uint64_t g_total_frames_written = 0;

// Sequencer state
#define MAX_SEQUENCER_STEPS 32
#define MAX_TOTAL_COLUMNS 64
static int g_sequencer_playing = 0;
static int g_sequencer_bpm = 120;
static int g_sequencer_steps = 16;
static int g_current_step = 0;
static int g_columns = 4; // Current number of columns in sequencer (starts with 1 grid × 4 columns)
static int g_sequencer_grid[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS]; // [step][column] = sample_slot (-1 = empty)
static uint64_t g_frames_per_step = 0;
static uint64_t g_step_frame_counter = 0;
static int g_column_playing_sample[MAX_TOTAL_COLUMNS]; // Track which sample is playing in each column
static int g_step_just_changed = 0; // Flag to handle immediate step playback

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
    for (int i = 0; i < MAX_SLOTS; ++i) {
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
                 current_memory_slots, MAX_SLOTS, MAX_MEMORY_SLOTS);
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
    
    // -------------------------------------------------------------
    // Create a data_source_node for this decoder and attach it to
    // the graph endpoint. The node starts muted (volume 0) and will
    // be unmuted when the slot is explicitly played.
    // -------------------------------------------------------------
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&slot->decoder);
    ma_result nodeRes = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &slot->node);
    if (nodeRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create data source node for slot %d: %s", slot_index, ma_result_description(nodeRes));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_decoder_uninit(&slot->decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }

    // Attach output bus 0 of this node to the endpoint (input bus 0)
    ma_node_attach_output_bus(&slot->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    // Start muted
    ma_node_set_output_bus_volume(&slot->node, 0, 0.0f);
    slot->node_initialized = 1;
    
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
    // Create and attach data source node to the graph (muted initially)
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&slot->decoder);
    ma_result nodeRes = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &slot->node);
    if (nodeRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create data source node for slot %d (streaming): %s", slot_index, ma_result_description(nodeRes));
        ma_decoder_uninit(&slot->decoder);
        slot->loaded = 0;
        return -1;
    }
    ma_node_attach_output_bus(&slot->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&slot->node, 0, 0.0f);
    slot->node_initialized = 1;
    
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

// Play all samples that should trigger on this step across all columns
static void play_samples_for_step(int step) {
    if (step < 0 || step >= g_sequencer_steps) return;
    
    prnt("🎵 [SEQUENCER] Playing step %d across %d columns", step, g_columns);
    
    // Process all columns (which represent all UI grids concatenated horizontally)
    for (int column = 0; column < g_columns; column++) {
        int sample_to_play = g_sequencer_grid[step][column];
        
        // Is there a sample in this grid cell?
        if (sample_to_play >= 0 && sample_to_play < MAX_SLOTS) {
            audio_slot_t* sample = &g_slots[sample_to_play];
            if (sample->loaded && sample->node_initialized) {
                prnt("🎹 [SEQUENCER] Step %d, Column %d: Want sample %d, Currently playing: %d", 
                     step, column, sample_to_play, g_column_playing_sample[column]);
                
                // Different sample than what's currently playing in this column?
                if (g_column_playing_sample[column] != sample_to_play) {
                    // Stop the old sample in this column
                    if (g_column_playing_sample[column] >= 0) {
                        audio_slot_t* old_sample = &g_slots[g_column_playing_sample[column]];
                        if (old_sample->node_initialized) {
                            ma_node_set_output_bus_volume(&old_sample->node, 0, 0.0f);
                            prnt("⏹️ [SEQUENCER] Stopped sample %d in column %d", g_column_playing_sample[column], column);
                        }
                    }
                    
                    // Start the new sample
                    ma_decoder_seek_to_pcm_frame(&sample->decoder, 0);  // Restart from beginning
                    ma_node_set_output_bus_volume(&sample->node, 0, 1.0f);  // Turn volume on
                    g_column_playing_sample[column] = sample_to_play;  // Remember what's playing
                    prnt("▶️ [SEQUENCER] Started sample %d in column %d", sample_to_play, column);
                } else {
                    // Same sample - restart it from the beginning
                    ma_decoder_seek_to_pcm_frame(&sample->decoder, 0);
                    prnt("🔄 [SEQUENCER] Restarted sample %d in column %d", sample_to_play, column);
                }
            }
        } else {
            prnt("➖ [SEQUENCER] Step %d, Column %d: Empty (currently playing: %d)", 
                 step, column, g_column_playing_sample[column]);
        }
        // IMPORTANT: If grid cell is empty, do NOTHING
        // Let previous samples continue playing until replaced
    }
}

// Run the sequencer: count frames, advance steps, and trigger samples
static void run_sequencer(ma_uint32 frameCount) {
    if (!g_sequencer_playing || g_frames_per_step == 0) return;
    
    // If sequencer just started, play step 0 immediately
    if (g_step_just_changed) {
        g_step_just_changed = 0;
        play_samples_for_step(g_current_step);
    }
    
    // Count audio frames to determine when to advance to next step
    for (ma_uint32 frame = 0; frame < frameCount; frame++) {
        g_step_frame_counter++;
        
        // Time to move to the next step?
        if (g_step_frame_counter >= g_frames_per_step) {
            g_step_frame_counter = 0;  // Reset frame counter
            int previous_step = g_current_step;
            g_current_step = (g_current_step + 1) % g_sequencer_steps;  // Advance step (with loop)
            
            // Did we loop back from last step to step 0?
            if (previous_step > g_current_step) {
                prnt("🔄 [SEQUENCER] Looping back to step 0 - clearing column memory");
                // Clear memory of what was playing in each column
                for (int col = 0; col < g_columns; col++) {
                    g_column_playing_sample[col] = -1;
                }
            }
            
            // Play samples for the new step
            play_samples_for_step(g_current_step);
        }
    }
}

// Main audio callback - called by miniaudio every ~11ms to fill the audio buffer
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    // 1. Run the sequencer (timing + sample triggering)
    run_sequencer(frameCount);
    
    // 2. Mix all playing samples into the output buffer
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);

    // 3. If recording, save the mixed audio to file
    if (g_is_output_recording) {
        ma_encoder_write_pcm_frames(&g_output_encoder, pOutput, frameCount, NULL);
        g_total_frames_written += frameCount;
    }

    (void)pInput;
    (void)pDevice;
}

static void free_slot_resources(int slot) {
    audio_slot_t* s = &g_slots[slot];

    // First detach/uninit the node so it no longer references the decoder.
    if (s->node_initialized) {
        ma_data_source_node_uninit(&s->node, NULL);
        s->node_initialized = 0;
    }

    // Now it is safe to uninit the decoder.
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

int reconfigure_audio_session(void) {
    prnt("🔄 [AUDIO SESSION] Re-configuring audio session for Bluetooth...");
    return configure_ios_audio_session();
}
#else
static int configure_ios_audio_session(void) {
    return 0; // No-op on non-iOS platforms
}

int reconfigure_audio_session(void) {
    return 0; // No-op on non-iOS platforms
}
#endif

// -----------------------------------------------------------------------------
// Public FFI API
// -----------------------------------------------------------------------------
int init(void) {
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
    for (int i = 0; i < MAX_SLOTS; ++i) {
        memset(&g_slots[i], 0, sizeof(audio_slot_t));
    }
    g_total_memory_used = 0;
    
    // Initialize sequencer state
    g_sequencer_playing = 0;
    g_sequencer_bpm = 120;
    g_sequencer_steps = 16;
    g_current_step = 0;
    g_step_frame_counter = 0;
    g_step_just_changed = 0;
    g_frames_per_step = (SAMPLE_RATE * 60) / (g_sequencer_bpm * 4); // 1/16 note frames
    
    // Initialize sequencer grid (all empty)
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
            g_sequencer_grid[step][col] = -1; // -1 means empty
        }
    }
    
    // Initialize column tracking
    for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
        g_column_playing_sample[col] = -1;
    }
    
    // ---------------------------------------------------------------------
    // Initialize the node graph which will perform automatic mixing of all
    // slot nodes. Every slot's data_source_node will connect directly to
    // the endpoint of this graph so their outputs are implicitly mixed.
    // ---------------------------------------------------------------------
    {
        ma_node_graph_config nodeGraphConfig = ma_node_graph_config_init(CHANNEL_COUNT);
        ma_result resultGraph = ma_node_graph_init(&nodeGraphConfig, NULL, &g_nodeGraph);
        if (resultGraph != MA_SUCCESS) {
            prnt_err("🔴 [MINIAUDIO] Failed to initialise node graph: %s", ma_result_description(resultGraph));
            return -1;
        }
    }
        
    // Configure and initialize device
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = SAMPLE_FORMAT;
    deviceConfig.playback.channels = CHANNEL_COUNT;
    deviceConfig.sampleRate = SAMPLE_RATE;
    deviceConfig.dataCallback = audio_callback;
    deviceConfig.pUserData = NULL;
    
    // Optimize buffer settings for lower latency and better performance
    deviceConfig.periodSizeInFrames = 512;     // Reduce buffer size for lower latency
    deviceConfig.periodSizeInMilliseconds = 0; // Use frames instead of milliseconds
    deviceConfig.periods = 2;                  // Double buffering for smooth playback
    
    // iOS-specific optimizations
    #ifdef __APPLE__
    deviceConfig.coreaudio.allowNominalSampleRateChange = MA_FALSE; // Prevent rate changes
    #endif
    
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

int get_slot_count(void) {
    return MAX_SLOTS;
}

int is_slot_loaded(int slot) {
    if (slot < 0 || slot >= MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return 0;
    }
    return g_slots[slot].loaded;
}

int load_sound_to_slot(int slot, const char* file_path, int loadToMemory) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return -1;
    }
    if (slot < 0 || slot >= MAX_SLOTS) {
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

int play_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return -1;
    }
    if (slot < 0 || slot >= MAX_SLOTS) {
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
    if (s->node_initialized) {
        ma_node_set_output_bus_volume(&s->node, 0, 1.0f);
    }
    prnt("✅ [MINIAUDIO] Slot %d started playing (%s)", slot, s->memory_data ? "memory" : "file");
    
    return 0;
}

void stop_slot(int slot) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return;
    }
    if (slot < 0 || slot >= MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return;
    }
    
    audio_slot_t* s = &g_slots[slot];
    s->active = 0;
    if (s->node_initialized) {
        ma_node_set_output_bus_volume(&s->node, 0, 0.0f);
    }
    prnt("⏹️ [MINIAUDIO] Slot %d stopped", slot);
}

void unload_slot(int slot) {
    if (!g_is_initialized) return;
    if (slot < 0 || slot >= MAX_SLOTS) {
        prnt_err("🔴 [MINIAUDIO] Invalid slot index: %d", slot);
        return;
    }
    
    free_slot_resources(slot);
    prnt("🗑️ [MINIAUDIO] Slot %d unloaded", slot);
}

void stop_all_sounds(void) {
    if (!g_is_initialized) {
        prnt_err("🔴 [MINIAUDIO] Device not initialized");
        return;
    }
    
    prnt("⏹️ [MINIAUDIO] Stopping all sounds");
    
    for (int i = 0; i < MAX_SLOTS; ++i) {
        audio_slot_t* s = &g_slots[i];
        s->active = 0;
        if (s->node_initialized) {
            ma_node_set_output_bus_volume(&s->node, 0, 0.0f);
        }
    }
}

int is_initialized(void) {
    return g_is_initialized;
}

// Memory tracking functions
uint64_t get_total_memory_usage(void) {
    return g_total_memory_used;
}

uint64_t get_slot_memory_usage(int slot) {
    if (slot < 0 || slot >= MAX_SLOTS) return 0;
    return g_slots[slot].memory_data ? g_slots[slot].memory_size : 0;
}

int get_memory_slot_count(void) {
    return get_current_memory_slot_count();
}

// Memory limit information functions
int get_max_memory_slots(void) {
    return MAX_MEMORY_SLOTS;
}

uint64_t get_max_memory_file_size(void) {
    return MAX_MEMORY_FILE_SIZE;
}

uint64_t get_max_total_memory_usage(void) {
    return MAX_TOTAL_MEMORY_USAGE;
}

uint64_t get_available_memory_capacity(void) {
    if (g_total_memory_used >= MAX_TOTAL_MEMORY_USAGE) {
        return 0;
    }
    return MAX_TOTAL_MEMORY_USAGE - g_total_memory_used;
}

// Legacy compatibility functions (no longer used but kept for compatibility)
int play_sound(const char* file_path) {
    prnt("ℹ️ [MINIAUDIO] Legacy play_sound called, use slot-based API instead");
    return -1;
}

int load_sound(const char* file_path) {
    prnt("ℹ️ [MINIAUDIO] Legacy load_sound called, use slot-based API instead");
    return -1;
}

int play_loaded_sound(void) {
    prnt("ℹ️ [MINIAUDIO] Legacy play_loaded_sound called, use slot-based API instead");
    return -1;
}

void log_route(void) {
    prnt("ℹ️ [MINIAUDIO] Audio route logging not implemented in Simple Mixing");
}

// Output recording functions (following simple_capture example pattern)
int start_recording(const char* output_file_path) {
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

int stop_recording(void) {
    if (!g_is_output_recording) {
        prnt_err("🔴 [RECORDING] Not currently recording");
        return -1;
    }
    
    prnt("⏹️ [RECORDING] Stopping output recording...");
    
    // Get duration before cleanup
    uint64_t duration_ms = get_recording_duration();
    
    // Finalize and cleanup encoder
    ma_encoder_uninit(&g_output_encoder);
    g_is_output_recording = 0;
    g_recording_start_time = 0;
    g_total_frames_written = 0;
    
    prnt("✅ [RECORDING] Output recording stopped (duration: %llu ms)", duration_ms);
    return 0;
}

int is_recording(void) {
    return g_is_output_recording;
}

uint64_t get_recording_duration(void) {
    if (!g_is_output_recording || !g_is_initialized) {
        return 0;
    }
    
    // Calculate duration from frames written
    // Duration = (frames_written / sample_rate) * 1000 (for milliseconds)
    return (g_total_frames_written * 1000) / SAMPLE_RATE;
}

// Sequencer functions (sample-accurate timing)
int start(int bpm, int steps) {
    if (!g_is_initialized) {
        prnt_err("🔴 [SEQUENCER] Device not initialized");
        return -1;
    }
    
    if (bpm <= 0 || bpm > 300) {
        prnt_err("🔴 [SEQUENCER] Invalid BPM: %d", bpm);
        return -1;
    }
    
    if (steps <= 0 || steps > MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [SEQUENCER] Invalid steps: %d (max: %d)", steps, MAX_SEQUENCER_STEPS);
        return -1;
    }
    
    // Stop any currently playing samples
    for (int col = 0; col < g_columns; col++) {
        if (g_column_playing_sample[col] >= 0) {
            audio_slot_t* s = &g_slots[g_column_playing_sample[col]];
            if (s->node_initialized) {
                ma_node_set_output_bus_volume(&s->node, 0, 0.0f);
            }
            g_column_playing_sample[col] = -1;
        }
    }
    
    // Configure sequencer
    g_sequencer_bpm = bpm;
    g_sequencer_steps = steps;
    g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
    g_current_step = 0;
    g_step_frame_counter = 0;
    g_step_just_changed = 1; // Flag to play step 0 immediately
    g_sequencer_playing = 1;
    
    prnt("🎵 [SEQUENCER] Started: %d BPM, %d steps, %llu frames per step", bpm, steps, g_frames_per_step);
    return 0;
}

void stop(void) {
    g_sequencer_playing = 0;
    g_current_step = 0;
    g_step_frame_counter = 0;
    g_step_just_changed = 0;
    
    // Stop all currently playing samples
    for (int col = 0; col < g_columns; col++) {
        if (g_column_playing_sample[col] >= 0) {
            audio_slot_t* s = &g_slots[g_column_playing_sample[col]];
            if (s->node_initialized) {
                ma_node_set_output_bus_volume(&s->node, 0, 0.0f);
            }
            g_column_playing_sample[col] = -1;
        }
    }
    
    prnt("⏹️ [SEQUENCER] Stopped");
}

int is_playing(void) {
    return g_sequencer_playing;
}

int get_current_step(void) {
    return g_current_step;
}

void set_bpm(int bpm) {
    if (bpm > 0 && bpm <= 300) {
        g_sequencer_bpm = bpm;
        g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
        prnt("🎵 [SEQUENCER] BPM changed to %d (%llu frames per step)", bpm, g_frames_per_step);
    } else {
        prnt_err("🔴 [SEQUENCER] Invalid BPM: %d", bpm);
    }
}

void set_cell(int step, int column, int sample_slot) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [SEQUENCER] Invalid step: %d", step);
        return;
    }
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [SEQUENCER] Invalid column: %d", column);
        return;
    }
    if (sample_slot < -1 || sample_slot >= MAX_SLOTS) {
        prnt_err("🔴 [SEQUENCER] Invalid sample slot: %d", sample_slot);
        return;
    }
    
    // Only set the cell if within current column range
    if (column >= g_columns) {
        prnt_err("🔴 [SEQUENCER] Column %d beyond current range (max: %d). Use set_columns() first.", column, g_columns - 1);
        return;
    }
    
    g_sequencer_grid[step][column] = sample_slot;
    prnt("🎹 [SEQUENCER] Set cell [%d,%d] = %d", step, column, sample_slot);
}

void clear_cell(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) return;
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) return;
    
    g_sequencer_grid[step][column] = -1;
    prnt("🗑️ [SEQUENCER] Cleared cell [%d,%d]", step, column);
}

void clear_all_cells(void) {
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
            g_sequencer_grid[step][col] = -1;
        }
    }
    prnt("🗑️ [SEQUENCER] Cleared all grid cells (entire %dx%d table)", MAX_SEQUENCER_STEPS, MAX_TOTAL_COLUMNS);
}

// Multi-grid sequencer support
void set_columns(int columns) {
    if (columns < 1 || columns > MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [SEQUENCER] Invalid columns: %d (max: %d)", columns, MAX_TOTAL_COLUMNS);
        return;
    }
    
    g_columns = columns;
    prnt("🎛️ [SEQUENCER] Set columns to %d", columns);
}

// Cleanup function
void cleanup(void) {
    if (!g_is_initialized) return;
    
    prnt("🧹 [MINIAUDIO] Starting cleanup...");
    
    // Stop sequencer
    stop();
    
    // Stop recording if active
    if (g_is_output_recording) {
        stop_recording();
    }
    
    // Stop device first
    ma_device_stop(&g_device);
    
    // Free all slot resources
    for (int i = 0; i < MAX_SLOTS; ++i) {
        free_slot_resources(i);
    }
    
    // Uninitialize device
    ma_device_uninit(&g_device);
    
    // Uninitialize the node graph (after all nodes have been freed)
    ma_node_graph_uninit(&g_nodeGraph, NULL);
    
    g_total_memory_used = 0;
    g_is_initialized = 0;
    prnt("✅ [MINIAUDIO] Cleanup completed successfully");
}