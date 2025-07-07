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
#include <math.h>


#define MAX_SLOTS 1024
#define SAMPLE_FORMAT   ma_format_f32
#define CHANNEL_COUNT   2
#define SAMPLE_RATE     48000

// Memory safety limits
#define MAX_MEMORY_SLOTS 128                          // Up to 128 fully memory-loaded sounds
#define MAX_MEMORY_FILE_SIZE (50 * 1024 * 1024)      // 50MB per individual file
#define MAX_TOTAL_MEMORY_USAGE (500 * 1024 * 1024)   // 500MB total memory usage limit

// Pitch data source wrapper using miniaudio resampler for pitch shifting
typedef struct {
    ma_data_source_base ds;
    ma_data_source* original_ds;
    float pitch_ratio;
    ma_uint32 channels;
    ma_uint32 sample_rate;
    
    // Use miniaudio resampler for pitch shifting
    ma_resampler resampler;
    int resampler_initialized;
    ma_uint32 target_sample_rate;  // Calculated from pitch ratio
} ma_pitch_data_source;

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
    
    // Volume control
    float volume;              // Sample bank volume (0.0 to 1.0)
    
    // Pitch control
    float pitch;               // Sample bank pitch (0.03125 to 32.0, 1.0 = normal, covers C0-C10)
    ma_pitch_data_source pitch_ds; // Pitch data source wrapper
    int pitch_ds_initialized;  // 1 when pitch data source is initialized
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
static float g_sequencer_grid_volumes[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS]; // [step][column] = volume (0.0 to 1.0)
static float g_sequencer_grid_pitches[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS]; // [step][column] = pitch (0.03125 to 32.0, 1.0 = normal, covers C0-C10)
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

// -----------------------------------------------------------------------------
// Custom Pitch Data Source Implementation
// -----------------------------------------------------------------------------

// Pitch data source callbacks
static ma_result ma_pitch_data_source_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL || pFramesOut == NULL || pFramesRead == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // Initialize pFramesRead to 0
    *pFramesRead = 0;
    
    // If resampler is not initialized or pitch ratio is 1.0 (no change), pass through
    if (!pPitch->resampler_initialized || pPitch->pitch_ratio == 1.0f) {
        return ma_data_source_read_pcm_frames(pPitch->original_ds, pFramesOut, frameCount, pFramesRead);
    }
    
    // Use miniaudio resampler for pitch shifting
    // We need a temporary input buffer since resampler expects to process input/output separately
    static float tempInputBuffer[4096 * 2]; // 4096 frames * 2 channels max
    const ma_uint64 tempCapacityInFrames = 4096;
    
    // For pitch shifting, estimate input frames needed based on pitch ratio
    // INVERTED: Higher pitch = need fewer input frames, lower pitch = need more input frames
    ma_uint64 inputFramesNeeded = (ma_uint64)(frameCount / pPitch->pitch_ratio);
    if (inputFramesNeeded < 1) inputFramesNeeded = 1; // Always read at least 1 frame
    if (inputFramesNeeded > tempCapacityInFrames) {
        inputFramesNeeded = tempCapacityInFrames;
    }
    
    // Read input frames from original data source
    ma_uint64 inputFramesRead = 0;
    ma_result result = ma_data_source_read_pcm_frames(pPitch->original_ds, tempInputBuffer, inputFramesNeeded, &inputFramesRead);
    
    if (result != MA_SUCCESS || inputFramesRead == 0) {
        return result;
    }
    
    // Process through the resampler
    ma_uint64 inputFramesToProcess = inputFramesRead;
    ma_uint64 outputFramesProcessed = frameCount;
    result = ma_resampler_process_pcm_frames(&pPitch->resampler, tempInputBuffer, &inputFramesToProcess, pFramesOut, &outputFramesProcessed);
    
    if (result == MA_SUCCESS) {
        *pFramesRead = outputFramesProcessed;
    }
    
    return result;
}

static ma_result ma_pitch_data_source_seek(ma_data_source* pDataSource, ma_uint64 frameIndex) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // Seek the original data source (converter doesn't need reset since we manually feed it)
    return ma_data_source_seek_to_pcm_frame(pPitch->original_ds, frameIndex);
}

static ma_result ma_pitch_data_source_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // If using resampler, return the resampler's output format
    if (pPitch->resampler_initialized) {
        if (pFormat) *pFormat = SAMPLE_FORMAT;
        if (pChannels) *pChannels = pPitch->channels;
        if (pSampleRate) *pSampleRate = pPitch->target_sample_rate;
        
        // For channel map, get it from the original source since channels don't change
        if (pChannelMap && channelMapCap > 0) {
            return ma_data_source_get_data_format(pPitch->original_ds, NULL, NULL, NULL, pChannelMap, channelMapCap);
        }
        
        return MA_SUCCESS;
    } else {
        // No resampling, pass through original format
        return ma_data_source_get_data_format(pPitch->original_ds, pFormat, pChannels, pSampleRate, pChannelMap, channelMapCap);
    }
}

static ma_result ma_pitch_data_source_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL || pCursor == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // Get cursor from original data source (input position)
    return ma_data_source_get_cursor_in_pcm_frames(pPitch->original_ds, pCursor);
}

static ma_result ma_pitch_data_source_get_length(ma_data_source* pDataSource, ma_uint64* pLength) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL || pLength == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // Get original length
    ma_result result = ma_data_source_get_length_in_pcm_frames(pPitch->original_ds, pLength);
    
    // If using resampler, adjust the length based on the pitch ratio
    // INVERTED: Higher pitch = shorter duration, lower pitch = longer duration
    if (result == MA_SUCCESS && pPitch->resampler_initialized && pPitch->pitch_ratio != 1.0f) {
        *pLength = (ma_uint64)(*pLength * pPitch->pitch_ratio);
    }
    
    return result;
}

static ma_data_source_vtable g_pitch_data_source_vtable = {
    ma_pitch_data_source_read,
    ma_pitch_data_source_seek,
    ma_pitch_data_source_get_data_format,
    ma_pitch_data_source_get_cursor,
    ma_pitch_data_source_get_length,
    NULL, // onSetLooping
    0     // flags
};

// Initialize pitch data source
static ma_result ma_pitch_data_source_init(ma_pitch_data_source* pPitch, ma_data_source* pOriginalDataSource, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate) {
    if (pPitch == NULL || pOriginalDataSource == NULL) {
        return MA_INVALID_ARGS;
    }
    
    ma_data_source_config config = ma_data_source_config_init();
    config.vtable = &g_pitch_data_source_vtable;
    
    ma_result result = ma_data_source_init(&config, &pPitch->ds);
    if (result != MA_SUCCESS) {
        return result;
    }
    
    pPitch->original_ds = pOriginalDataSource;
    pPitch->pitch_ratio = pitchRatio;
    pPitch->channels = channels;
    pPitch->sample_rate = sampleRate;
    pPitch->resampler_initialized = 0;
    
    // Initialize resampler for pitch shifting if needed
    if (pitchRatio != 1.0f) {
        // Calculate target sample rate for pitch shifting
        // INVERTED: Higher pitch ratio = lower target sample rate (faster playback)
        // Lower pitch ratio = higher target sample rate (slower playback)
        pPitch->target_sample_rate = (ma_uint32)(sampleRate / pitchRatio);
        
        // Clamp to reasonable range to prevent extreme values
        if (pPitch->target_sample_rate < 8000) pPitch->target_sample_rate = 8000;
        if (pPitch->target_sample_rate > 192000) pPitch->target_sample_rate = 192000;
        
        // Configure resampler for pitch shifting
        ma_resampler_config resamplerConfig = ma_resampler_config_init(
            SAMPLE_FORMAT,                // format
            channels,                     // channels
            sampleRate,                   // input sample rate (original)
            pPitch->target_sample_rate,   // output sample rate (pitch-shifted)
            ma_resample_algorithm_linear  // use linear algorithm for speed
        );
        
        // Initialize the resampler
        result = ma_resampler_init(&resamplerConfig, NULL, &pPitch->resampler);
        if (result == MA_SUCCESS) {
            pPitch->resampler_initialized = 1;
            prnt("✅ [PITCH] Initialized resampler: %.2fx pitch (rate: %d -> %d Hz)", 
                 pitchRatio, sampleRate, pPitch->target_sample_rate);
        } else {
            prnt_err("🔴 [PITCH] Failed to initialize resampler: %s", ma_result_description(result));
        }
    }
    
    return MA_SUCCESS;
}

// Update pitch ratio
static ma_result ma_pitch_data_source_set_pitch(ma_pitch_data_source* pPitch, float pitchRatio) {
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // If pitch ratio hasn't changed significantly, don't recreate converter
    if (fabs(pPitch->pitch_ratio - pitchRatio) < 0.001f) {
        return MA_SUCCESS;
    }
    
    // Clean up existing resampler
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    
    pPitch->pitch_ratio = pitchRatio;
    
    // If pitch ratio is 1.0 (no change), don't create resampler
    if (pitchRatio == 1.0f) {
        prnt("🎵 [PITCH] Reset to normal pitch (no resampling)");
        return MA_SUCCESS;
    }
    
    // Calculate new target sample rate
    // INVERTED: Higher pitch ratio = lower target sample rate (faster playback)
    pPitch->target_sample_rate = (ma_uint32)(pPitch->sample_rate / pitchRatio);
    
    // Clamp to reasonable range
    if (pPitch->target_sample_rate < 8000) pPitch->target_sample_rate = 8000;
    if (pPitch->target_sample_rate > 192000) pPitch->target_sample_rate = 192000;
    
    // Configure new resampler
    ma_resampler_config resamplerConfig = ma_resampler_config_init(
        SAMPLE_FORMAT,                // format
        pPitch->channels,             // channels
        pPitch->sample_rate,          // input sample rate (original)
        pPitch->target_sample_rate,   // output sample rate (pitch-shifted)
        ma_resample_algorithm_linear  // use linear algorithm for speed
    );
    
    // Initialize the new resampler
    ma_result result = ma_resampler_init(&resamplerConfig, NULL, &pPitch->resampler);
    if (result == MA_SUCCESS) {
        pPitch->resampler_initialized = 1;
        prnt("🎵 [PITCH] Updated resampler: %.2fx pitch (rate: %d -> %d Hz)", 
             pitchRatio, pPitch->sample_rate, pPitch->target_sample_rate);
    } else {
        prnt_err("🔴 [PITCH] Failed to initialize resampler: %s", ma_result_description(result));
        return result;
    }
    
    return MA_SUCCESS;
}

// Uninitialize pitch data source
static void ma_pitch_data_source_uninit(ma_pitch_data_source* pPitch) {
    if (pPitch == NULL) {
        return;
    }
    
    // Clean up resampler if initialized
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    
    ma_data_source_uninit(&pPitch->ds);
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
    
    // Initialize default pitch and volume
    slot->pitch = 1.0f;              // Default pitch (no change)
    slot->volume = 1.0f;             // Default volume (full)
    
    // -------------------------------------------------------------
    // Initialize pitch data source wrapper around the decoder
    // -------------------------------------------------------------
    ma_result pitchRes = ma_pitch_data_source_init(&slot->pitch_ds, &slot->decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize pitch data source for slot %d: %s", slot_index, ma_result_description(pitchRes));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_decoder_uninit(&slot->decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    slot->pitch_ds_initialized = 1;
    
    // -------------------------------------------------------------
    // Create a data_source_node for this pitch data source and attach it to
    // the graph endpoint. The node starts muted (volume 0) and will
    // be unmuted when the slot is explicitly played.
    // -------------------------------------------------------------
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&slot->pitch_ds);
    ma_result nodeRes = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &slot->node);
    if (nodeRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create data source node for slot %d: %s", slot_index, ma_result_description(nodeRes));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_pitch_data_source_uninit(&slot->pitch_ds);
        slot->pitch_ds_initialized = 0;
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
    
    // Initialize default pitch and volume
    slot->pitch = 1.0f;              // Default pitch (no change)
    slot->volume = 1.0f;             // Default volume (full)
    
    // Initialize pitch data source wrapper
    ma_result pitchRes = ma_pitch_data_source_init(&slot->pitch_ds, &slot->decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize pitch data source for slot %d (streaming): %s", slot_index, ma_result_description(pitchRes));
        ma_decoder_uninit(&slot->decoder);
        slot->loaded = 0;
        return -1;
    }
    slot->pitch_ds_initialized = 1;
    
    // Create and attach data source node to the graph (muted initially)
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&slot->pitch_ds);
    ma_result nodeRes = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &slot->node);
    if (nodeRes != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create data source node for slot %d (streaming): %s", slot_index, ma_result_description(nodeRes));
        ma_pitch_data_source_uninit(&slot->pitch_ds);
        slot->pitch_ds_initialized = 0;
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
                // prnt("🎹 [SEQUENCER] Step %d, Column %d: Want sample %d, Currently playing: %d", 
                //      step, column, sample_to_play, g_column_playing_sample[column]);
                
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
                    
                    // Volume logic: cell volume overrides sample bank volume when set
                    float bank_volume = sample->volume;
                    float cell_volume = g_sequencer_grid_volumes[step][column];
                    float final_volume = (cell_volume != 1.0f) ? cell_volume : bank_volume;
                    
                    // Pitch logic: cell pitch overrides sample bank pitch when set
                    float bank_pitch = sample->pitch;
                    float cell_pitch = g_sequencer_grid_pitches[step][column];
                    float final_pitch = (cell_pitch != 1.0f) ? cell_pitch : bank_pitch;
                    
                    // Apply pitch to the pitch data source
                    if (sample->pitch_ds_initialized) {
                        ma_pitch_data_source_set_pitch(&sample->pitch_ds, final_pitch);
                    }
                    
                    ma_node_set_output_bus_volume(&sample->node, 0, final_volume);
                    g_column_playing_sample[column] = sample_to_play;  // Remember what's playing
                    prnt("▶️ [SEQUENCER] Started sample %d in column %d (bank: %.2f, cell: %.2f → vol: %.2f, pitch: %.2f)", 
                         sample_to_play, column, bank_volume, cell_volume, final_volume, final_pitch);
                } else {
                    // Same sample - restart it from the beginning
                    ma_decoder_seek_to_pcm_frame(&sample->decoder, 0);
                    
                    // Apply volume logic for restart too
                    float bank_volume = sample->volume;
                    float cell_volume = g_sequencer_grid_volumes[step][column];
                    float final_volume = (cell_volume != 1.0f) ? cell_volume : bank_volume;
                    
                    // Apply pitch logic for restart too
                    float bank_pitch = sample->pitch;
                    float cell_pitch = g_sequencer_grid_pitches[step][column];
                    float final_pitch = (cell_pitch != 1.0f) ? cell_pitch : bank_pitch;
                    
                    // Apply pitch to the pitch data source
                    if (sample->pitch_ds_initialized) {
                        ma_pitch_data_source_set_pitch(&sample->pitch_ds, final_pitch);
                    }
                    
                    ma_node_set_output_bus_volume(&sample->node, 0, final_volume);
                    
                    prnt("🔄 [SEQUENCER] Restarted sample %d in column %d (volume: %.2f)", sample_to_play, column, final_volume);
                }
            }
        } else {
            // prnt("➖ [SEQUENCER] Step %d, Column %d: Empty (currently playing: %d)", 
            //      step, column, g_column_playing_sample[column]);
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

    // First detach/uninit the node so it no longer references the pitch data source.
    if (s->node_initialized) {
        ma_data_source_node_uninit(&s->node, NULL);
        s->node_initialized = 0;
    }

    // Uninit the pitch data source (which will also uninit the resampler)
    if (s->pitch_ds_initialized) {
        ma_pitch_data_source_uninit(&s->pitch_ds);
        s->pitch_ds_initialized = 0;
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
    s->pitch = 1.0f;    // Reset pitch to default
    s->volume = 1.0f;   // Reset volume to default
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
        g_slots[i].volume = 1.0f; // Default volume: 100%
        g_slots[i].pitch = 1.0f;  // Default pitch: normal
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
            g_sequencer_grid_volumes[step][col] = 1.0f; // Default volume: 100%
            g_sequencer_grid_pitches[step][col] = 1.0f; // Default pitch: normal
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
        ma_node_set_output_bus_volume(&s->node, 0, s->volume);
    }
    prnt("✅ [MINIAUDIO] Slot %d started playing (%s) at volume %.2f", slot, s->memory_data ? "memory" : "file", s->volume);
    
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
            g_sequencer_grid_volumes[step][col] = 1.0f; // Reset volume to 100%
            g_sequencer_grid_pitches[step][col] = 1.0f; // Reset pitch to normal
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

// Volume control functions
int set_sample_bank_volume(int bank, float volume) {
    if (bank < 0 || bank >= MAX_SLOTS) {
        prnt_err("🔴 [VOLUME] Invalid sample bank: %d", bank);
        return -1;
    }
    
    if (volume < 0.0f || volume > 1.0f) {
        prnt_err("🔴 [VOLUME] Invalid volume: %f (must be 0.0-1.0)", volume);
        return -1;
    }
    
    audio_slot_t* s = &g_slots[bank];
    s->volume = volume;
    
    // NOTE: Don't apply volume immediately to playing samples
    // Volume will be applied when cells are triggered during sequencer playback
    
    prnt("🔊 [VOLUME] Sample bank %d volume set to %.2f (will apply on next trigger)", bank, volume);
    return 0;
}

float get_sample_bank_volume(int bank) {
    if (bank < 0 || bank >= MAX_SLOTS) {
        prnt_err("🔴 [VOLUME] Invalid sample bank: %d", bank);
        return 0.0f;
    }
    
    return g_slots[bank].volume;
}

int set_cell_volume(int step, int column, float volume) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [VOLUME] Invalid step: %d", step);
        return -1;
    }
    
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [VOLUME] Invalid column: %d", column);
        return -1;
    }
    
    if (volume < 0.0f || volume > 1.0f) {
        prnt_err("🔴 [VOLUME] Invalid volume: %f (must be 0.0-1.0)", volume);
        return -1;
    }
    
    g_sequencer_grid_volumes[step][column] = volume;
    prnt("🔊 [VOLUME] Cell [%d,%d] volume set to %.2f", step, column, volume);
    
    // Debug: show what sample is in this cell
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        prnt("🔍 [DEBUG] Cell [%d,%d] contains sample %d", step, column, sample_in_cell);
    } else {
        prnt("🔍 [DEBUG] Cell [%d,%d] is empty", step, column);
    }
    return 0;
}

float get_cell_volume(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [VOLUME] Invalid step: %d", step);
        return 0.0f;
    }
    
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [VOLUME] Invalid column: %d", column);
        return 0.0f;
    }
    
    float volume = g_sequencer_grid_volumes[step][column];
    prnt("🔍 [DEBUG] Get cell [%d,%d] volume = %.2f", step, column, volume);
    return volume;
}

// Pitch control functions
int set_sample_bank_pitch(int bank, float pitch) {
    if (bank < 0 || bank >= MAX_SLOTS) {
        prnt_err("🔴 [PITCH] Invalid sample bank: %d", bank);
        return -1;
    }
    
    if (pitch < 0.03125f || pitch > 32.0f) {
        prnt_err("🔴 [PITCH] Invalid pitch: %f (must be 0.03125-32.0 for C0-C10)", pitch);
        return -1;
    }
    
    audio_slot_t* s = &g_slots[bank];
    s->pitch = pitch;
    
    // NOTE: Don't apply pitch immediately to playing samples
    // Pitch will be applied when cells are triggered during sequencer playback
    
    prnt("🎵 [PITCH] Sample bank %d pitch set to %.2f (will apply on next trigger)", bank, pitch);
    return 0;
}

float get_sample_bank_pitch(int bank) {
    if (bank < 0 || bank >= MAX_SLOTS) {
        prnt_err("🔴 [PITCH] Invalid sample bank: %d", bank);
        return 1.0f;
    }
    
    return g_slots[bank].pitch;
}

int set_cell_pitch(int step, int column, float pitch) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [PITCH] Invalid step: %d", step);
        return -1;
    }
    
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [PITCH] Invalid column: %d", column);
        return -1;
    }
    
    if (pitch < 0.03125f || pitch > 32.0f) {
        prnt_err("🔴 [PITCH] Invalid pitch: %f (must be 0.03125-32.0 for C0-C10)", pitch);
        return -1;
    }
    
    g_sequencer_grid_pitches[step][column] = pitch;
    prnt("🎵 [PITCH] Cell [%d,%d] pitch set to %.2f", step, column, pitch);
    
    // Debug: show what sample is in this cell
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        prnt("🔍 [DEBUG] Cell [%d,%d] contains sample %d", step, column, sample_in_cell);
    } else {
        prnt("🔍 [DEBUG] Cell [%d,%d] is empty", step, column);
    }
    return 0;
}

float get_cell_pitch(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [PITCH] Invalid step: %d", step);
        return 1.0f;
    }
    
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [PITCH] Invalid column: %d", column);
        return 1.0f;
    }
    
    float pitch = g_sequencer_grid_pitches[step][column];
    prnt("🔍 [DEBUG] Get cell [%d,%d] pitch = %.2f", step, column, pitch);
    return pitch;
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