#include "sequencer.h"

// -----------------------------------------------------------------------------
// Android Systrace/Atrace Integration for Performance Analysis
// -----------------------------------------------------------------------------
#ifdef __ANDROID__
    #include <android/trace.h>
    #define ATRACE_TAG ATRACE_TAG_AUDIO
    #define TRACE_BEGIN(name) ATrace_beginSection(name)
    #define TRACE_END() ATrace_endSection()
    #define TRACE_ASYNC_BEGIN(name, cookie) ATrace_beginAsyncSection(name, cookie)
    #define TRACE_ASYNC_END(name, cookie) ATrace_endAsyncSection(name, cookie)
    // ATrace_setCounter is only available in Android API 29+
    #if __ANDROID_API__ >= 29
        #define TRACE_INT(name, value) ATrace_setCounter(name, value)
    #else
        #define TRACE_INT(name, value) // No-op for older Android versions
    #endif
#else
    #define TRACE_BEGIN(name)
    #define TRACE_END()
    #define TRACE_ASYNC_BEGIN(name, cookie)
    #define TRACE_ASYNC_END(name, cookie)
    #define TRACE_INT(name, value)
#endif

// -----------------------------------------------------------------------------
// Pitch Shifting Implementation Selection
// -----------------------------------------------------------------------------
// Runtime pitch approach selection (cleaner than compile-time #if statements)

typedef enum {
    PITCH_METHOD_MINIAUDIO = 0,     // Miniaudio resampler (fast, reliable, real-time)
    PITCH_METHOD_SOUNDTOUCH_REALTIME = 1,  // SoundTouch real-time (high quality, may have issues with multiple instances)  
    PITCH_METHOD_SOUNDTOUCH_PREPROCESSING = 2  // SoundTouch offline preprocessing (highest quality, cached)
} pitch_method_t;

// Current pitch method (can be changed at runtime if needed)
static pitch_method_t g_current_pitch_method = PITCH_METHOD_SOUNDTOUCH_PREPROCESSING;

// SoundTouch includes (needed for both realtime and preprocessing)
// Mobile-optimized SoundTouch configuration (must be before includes)
#define SOUNDTOUCH_FLOAT_SAMPLES                     1  // Use floating point (better on ARM64)
#define SOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION  1  // Enable ARM NEON optimizations
#define SOUNDTOUCH_DISABLE_X86_OPTIMIZATIONS         1  // Force disable x86 optimizations
#undef  SOUNDTOUCH_INTEGER_SAMPLES                      // Explicitly disable integer samples

// SoundTouch includes for high-quality pitch shifting
#include "soundtouch/SoundTouch.h"

// Include SoundTouch implementation directly (like MINIAUDIO_IMPLEMENTATION)
#include "soundtouch/cpu_detect_arm.cpp"    // ARM-compatible CPU detection (must be first)
#include "soundtouch/SoundTouch.cpp"
#include "soundtouch/TDStretch.cpp"  
#include "soundtouch/RateTransposer.cpp"
#include "soundtouch/FIRFilter.cpp"
#include "soundtouch/AAFilter.cpp"
#include "soundtouch/FIFOSampleBuffer.cpp"
#include "soundtouch/InterpolateLinear.cpp"
#include "soundtouch/InterpolateCubic.cpp"
#include "soundtouch/InterpolateShannon.cpp"
#include "soundtouch/PeakFinder.cpp"
// Skip BPMDetect.cpp - not needed for pitch shifting

using namespace soundtouch;

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

// Utility macros
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif


#define MAX_SLOTS 1024
#define SAMPLE_FORMAT   ma_format_f32
#define CHANNEL_COUNT   2
#define SAMPLE_RATE     48000

// Memory safety limits
#define MAX_MEMORY_SLOTS 128                          // Up to 128 fully memory-loaded sounds
#define MAX_MEMORY_FILE_SIZE (50 * 1024 * 1024)      // 50MB per individual file
#define MAX_TOTAL_MEMORY_USAGE (500 * 1024 * 1024)   // 500MB total memory usage limit

// Unified pitch data source wrapper supporting all three implementations
typedef struct {
    ma_data_source_base ds;
    ma_data_source* original_ds;
    float pitch_ratio;
    ma_uint32 channels;
    ma_uint32 sample_rate;
    pitch_method_t approach;  // Which approach this instance uses
    
    // Miniaudio resampler fields (used by MINIAUDIO and PREPROCESSING fallback)
    ma_resampler resampler;
    int resampler_initialized;
    ma_uint32 target_sample_rate;  // Calculated from pitch ratio
    float* temp_input_buffer;      // Instance-specific temp buffer for thread safety
    size_t temp_input_buffer_size; // Size of temp buffer in samples
    
    // SoundTouch real-time fields (used by SOUNDTOUCH_REALTIME)
    SoundTouch* soundtouch_processor;
    int soundtouch_initialized;
    float* temp_buffer;            // Internal processing buffer
    size_t temp_buffer_size;       // Size of temp buffer in samples
    ma_uint64 input_frames_pending; // Frames waiting for processing
    
    // SoundTouch preprocessing fields (used by SOUNDTOUCH_PREPROCESSING)
    int sample_slot;               // Which sample this is for (for cache lookup)
    ma_decoder* preprocessed_decoder; // Decoder for preprocessed audio data
    int uses_preprocessed_data;    // Whether this instance uses cached data
} ma_pitch_data_source;

// Pitch data source vtable is defined later in the file

// -----------------------------------------------------------------------------
// Preprocessed Pitch System - Process samples offline, store in RAM
// (Used when method is PITCH_METHOD_SOUNDTOUCH_PREPROCESSING)
// -----------------------------------------------------------------------------

// Hash function for pitch ratios (quantized to avoid float precision issues)
static uint32_t hash_pitch_ratio(float pitch_ratio) {
    // Quantize to nearest 0.001 to avoid float precision issues
    uint32_t quantized = (uint32_t)(pitch_ratio * 1000.0f + 0.5f);
    return quantized;
}

// Preprocessed sample entry
typedef struct {
    int source_slot;                    // Which slot this was preprocessed from
    float pitch_ratio;                  // The pitch ratio used
    uint32_t pitch_hash;               // Hash of pitch ratio for fast lookup
    
    void* processed_data;              // Processed audio data
    size_t processed_size;             // Size in bytes
    ma_uint64 processed_frames;        // Length in frames
    
    int in_use;                        // 1 if currently in use
    uint64_t last_accessed;            // For LRU cache management
    uint64_t creation_time;            // When this was created
} preprocessed_sample_t;

// Preprocessed sample cache
#define MAX_PREPROCESSED_SAMPLES 64    // Cache up to 64 preprocessed samples
static preprocessed_sample_t g_preprocessed_cache[MAX_PREPROCESSED_SAMPLES];
static uint64_t g_preprocessed_access_counter = 0;  // For LRU tracking
static uint64_t g_total_preprocessed_memory = 0;    // Track memory usage

// Function declarations for preprocessed system
static int preprocess_sample_with_pitch(int source_slot, float pitch_ratio);
static preprocessed_sample_t* find_preprocessed_sample(int source_slot, float pitch_ratio);
static void cleanup_preprocessed_cache(void);
static void evict_oldest_preprocessed_sample(void);

// Audio slot structure - separate systems for different playback scenarios
typedef struct {
    // Shared sample data
    void* memory_data;         // NULL for file mode, allocated buffer for memory mode
    size_t memory_size;        // 0 for file mode, actual size for memory mode
    int loaded;
    char* file_path;
    
    // Sample bank playback (when user clicks play on a sample bank)
    ma_decoder sample_bank_decoder;        // Independent decoder for sample bank playback
    ma_pitch_data_source sample_bank_pitch_ds; // Pitch data source for sample bank playback
    ma_data_source_node sample_bank_node;  // Node for sample bank playback
    int sample_bank_node_initialized;      // 1 when sample bank node is initialized
    int sample_bank_pitch_ds_initialized;  // 1 when sample bank pitch data source is initialized
    int sample_bank_active;                // 1 when sample bank is playing
    int sample_bank_at_end;                // 1 when sample bank playback finished
    
    // Sequencer grid playback (automated sequencer triggers)
    ma_decoder sequencer_decoder;     // Independent decoder for sequencer
    ma_pitch_data_source sequencer_pitch_ds; // Pitch data source for sequencer playback
    ma_data_source_node sequencer_node; // Node for sequencer playback
    int sequencer_node_initialized;   // 1 when sequencer node is initialized
    int sequencer_pitch_ds_initialized; // 1 when sequencer pitch data source is initialized
    int sequencer_active;             // 1 when sequencer is playing this slot
    int sequencer_at_end;             // 1 when sequencer playback finished
    
    // Volume control
    float volume;              // Sample bank volume (0.0 to 1.0)
    
    // Pitch control
    float pitch;               // Sample bank pitch (0.03125 to 32.0, 1.0 = normal, covers C0-C10)
} audio_slot_t;

// Global preview systems (separate from sample banks)
typedef struct {
    ma_decoder decoder;
    ma_pitch_data_source pitch_ds;
    ma_data_source_node node;
    int node_initialized;
    int pitch_ds_initialized;
    int active;
    char* file_path;
} preview_system_t;

// Global preview instances
static preview_system_t g_sample_preview;  // For previewing samples before adding to banks
static preview_system_t g_cell_preview;    // For previewing individual grid cells

// Preview system helper functions
static void cleanup_preview_system(preview_system_t* preview) {
    if (preview->node_initialized) {
        ma_data_source_node_uninit(&preview->node, NULL);
        preview->node_initialized = 0;
    }
    
    if (preview->pitch_ds_initialized) {
#if PITCH_APPROACH_MINIAUDIO
        // Clean up resampler if initialized
        if (preview->pitch_ds.resampler_initialized) {
            ma_resampler_uninit(&preview->pitch_ds.resampler, NULL);
            preview->pitch_ds.resampler_initialized = 0;
        }
#elif PITCH_APPROACH_SOUNDTOUCH_REALTIME
        // Clean up SoundTouch
        if (preview->pitch_ds.soundtouch_processor) {
            delete preview->pitch_ds.soundtouch_processor;
            preview->pitch_ds.soundtouch_processor = nullptr;
        }
        if (preview->pitch_ds.temp_buffer) {
            free(preview->pitch_ds.temp_buffer);
            preview->pitch_ds.temp_buffer = nullptr;
        }
#elif PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
        // Clean up preprocessing resources
        if (preview->pitch_ds.uses_preprocessed_data && preview->pitch_ds.preprocessed_decoder) {
            ma_decoder_uninit(preview->pitch_ds.preprocessed_decoder);
            free(preview->pitch_ds.preprocessed_decoder);
            preview->pitch_ds.preprocessed_decoder = NULL;
            preview->pitch_ds.uses_preprocessed_data = 0;
        }
        // Clean up fallback resampler
        if (preview->pitch_ds.resampler_initialized) {
            ma_resampler_uninit(&preview->pitch_ds.resampler, NULL);
            preview->pitch_ds.resampler_initialized = 0;
        }
#endif
        ma_data_source_uninit(&preview->pitch_ds.ds);
        preview->pitch_ds_initialized = 0;
    }
    
    ma_decoder_uninit(&preview->decoder);
    
    if (preview->file_path) {
        free(preview->file_path);
        preview->file_path = NULL;
    }
    
    preview->active = 0;
}

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
#define MAX_ACTIVE_CELL_NODES 512  // Maximum number of simultaneously active cell nodes

// Individual cell node structure - each active cell gets its own audio node
typedef struct {
    int active;                        // 1 if this cell node is currently active
    int step;                          // Grid position (step)
    int column;                        // Grid position (column)
    int sample_slot;                   // Which sample this cell plays
    
    ma_decoder decoder;                // Independent decoder for this cell
    ma_audio_buffer audio_buffer;      // Audio buffer for preprocessed data
    int uses_audio_buffer;             // 1 if using audio_buffer, 0 if using decoder
    ma_uint64 audio_buffer_frame_count; // Frame count for audio buffer (stored since miniaudio doesn't provide getter)
    ma_pitch_data_source pitch_ds;     // Cell-specific pitch control
    ma_data_source_node node;          // Individual node in graph
    int node_initialized;              // 1 when node is initialized
    int pitch_ds_initialized;          // 1 when pitch data source is initialized
    int audio_buffer_initialized;      // 1 when audio buffer is initialized
    
    float volume;                      // Cell-specific volume
    float pitch;                       // Cell-specific pitch
    
    int is_fading_out;                 // 1 if currently fading out to prevent clicks
    uint64_t fade_start_frame;         // When fade out started
    int is_fading_in;                  // 1 if currently fading in to prevent clicks
    uint64_t fade_in_start_frame;      // When fade in started
    float current_volume;              // Current actual volume (smoothed) 
    float target_volume;               // Target volume we're smoothing towards
    float volume_rise_coeff;           // Smoothing coefficient for fade-in
    float volume_fall_coeff;           // Smoothing coefficient for fade-out
    int is_volume_smoothing;           // 1 if volume is currently being smoothed
    
    uint64_t start_frame;              // When playback started (for lifecycle tracking)
    uint64_t id;                       // Unique ID for this cell node instance
} cell_node_t;

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
static int g_step_just_changed = 0; // Flag to handle immediate step playback

// Per-cell node management
static cell_node_t g_cell_nodes[MAX_ACTIVE_CELL_NODES];  // Pool of cell nodes
static uint64_t g_next_cell_node_id = 1;                 // Unique ID counter for cell nodes
static uint64_t g_current_frame = 0;                     // Global frame counter for lifecycle tracking

// Track currently playing node per column
static cell_node_t* currently_playing_nodes_per_col[MAX_TOTAL_COLUMNS];

// Exponential volume smoothing for click elimination
#define VOLUME_RISE_TIME_MS 6.0f      // 6ms fade-in time
#define VOLUME_FALL_TIME_MS 12.0f     // 12ms fade-out time  
#define VOLUME_THRESHOLD 0.0001f      // Convergence threshold 

// Forward declarations for pitch data source functions
static ma_result ma_pitch_data_source_init(ma_pitch_data_source* pPitch, ma_data_source* pOriginalDataSource, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate);
static void ma_pitch_data_source_uninit(ma_pitch_data_source* pPitch);
static ma_result ma_pitch_data_source_set_pitch(ma_pitch_data_source* pPitch, float pitchRatio);
#if PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
static ma_result ma_pitch_data_source_init_with_preprocessing(ma_pitch_data_source* pPitch, ma_data_source* pOriginalDataSource, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate, int sample_slot);
#endif

// Forward declarations for cell node functions
static cell_node_t* create_cell_node(int step, int column, int sample_slot, float volume, float pitch);
static void set_target_volume(cell_node_t* cell, float new_target_volume);

// Debug function to check SoundTouch instance isolation
#if PITCH_APPROACH_SOUNDTOUCH_REALTIME
static void debug_soundtouch_instance(const char* context, ma_pitch_data_source* pPitch) {
    if (pPitch->approach != PITCH_METHOD_SOUNDTOUCH_REALTIME || !pPitch->soundtouch_initialized) return;
    
    static int debug_counter = 0;
    debug_counter++;
    
    // Only log every 100th call to avoid spam
    if (debug_counter % 100 == 0) {
        prnt("🔍 [ST_DEBUG] %s: Instance %p, processor %p, buffer %p, initialized %d, pitch %.3f (call #%d)", 
             context, 
             (void*)pPitch, 
             (void*)pPitch->soundtouch_processor,
             (void*)pPitch->temp_buffer,
             pPitch->soundtouch_initialized,
             pPitch->pitch_ratio,
             debug_counter);
             
        // Additional instance state verification
        if (pPitch->soundtouch_processor) {
            try {
                uint available = pPitch->soundtouch_processor->numSamples();
                prnt("🔍 [ST_DEBUG] Instance %p has %u samples available", (void*)pPitch, available);
            } catch (...) {
                prnt_err("🔴 [ST_DEBUG] Instance %p numSamples() failed", (void*)pPitch);
            }
        }
    }
}
#else
// Stub for non-SoundTouch approaches
static void debug_soundtouch_instance(const char* context, ma_pitch_data_source* pPitch) {
    // No-op for approaches that don't use SoundTouch real-time processing
}
#endif

// Cell node management functions
static cell_node_t* find_available_cell_node(void) {
    int total_checked = 0;
    int active_count = 0;
    
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        total_checked++;
        if (g_cell_nodes[i].active) {
            active_count++;
        } else {
            // Found available node
            prnt("♻️ [CELL POOL] Found available node #%d (pool: %d/%d active)", 
                 i, active_count, MAX_ACTIVE_CELL_NODES);
            return &g_cell_nodes[i];
        }
    }
    
    prnt_err("🔴 [CELL POOL] POOL EXHAUSTED! %d/%d nodes active. Consider increasing MAX_ACTIVE_CELL_NODES", 
             active_count, MAX_ACTIVE_CELL_NODES);
    return NULL;
}

static void cleanup_cell_node(cell_node_t* cell) {
    if (!cell || !cell->active) return;
    
    prnt("🗑️ [CELL NODE] Cleaning up cell [%d,%d] with sample %d (ID: %llu)", 
         cell->step, cell->column, cell->sample_slot, cell->id);
    
    // Cleanup node (detach first, then uninit)
    if (cell->node_initialized) {
        // Detach the node from the graph before uninitializing
        ma_node_detach_output_bus(&cell->node, 0);
        ma_data_source_node_uninit(&cell->node, NULL);
        cell->node_initialized = 0;
    }
    
    // Cleanup pitch data source
    if (cell->pitch_ds_initialized) {
        ma_pitch_data_source_uninit(&cell->pitch_ds);
        cell->pitch_ds_initialized = 0;
    }
    
    // Cleanup decoder or audio buffer based on what was used
    if (cell->uses_audio_buffer && cell->audio_buffer_initialized) {
        ma_audio_buffer_uninit(&cell->audio_buffer);
        cell->audio_buffer_initialized = 0;
    } else {
        ma_decoder_uninit(&cell->decoder);
    }
    
    // Reset cell state
    memset(cell, 0, sizeof(cell_node_t));
}

// Count active cell nodes for diagnostics
static int count_active_cell_nodes(void) {
    int count = 0;
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active) count++;
    }
    return count;
}

// Check if volume has converged to target
static bool volume_has_converged(float current, float target) {
    return fabsf(current - target) < VOLUME_THRESHOLD;
}

// Apply exponential smoothing step
static float apply_exponential_smoothing(float current, float target, float alpha) {
    return current + alpha * (target - current);
}

// Update volume smoothing for all active nodes
static void update_volume_smoothing(void) {
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        cell_node_t* cell = &g_cell_nodes[i];
        if (!cell->active || !cell->node_initialized || !cell->is_volume_smoothing) continue;
        
        if (volume_has_converged(cell->current_volume, cell->target_volume)) {
            cell->current_volume = cell->target_volume;
            cell->is_volume_smoothing = 0;
        } else {
            float alpha = (cell->current_volume < cell->target_volume) ? 
                         cell->volume_rise_coeff : cell->volume_fall_coeff;
            cell->current_volume = apply_exponential_smoothing(
                cell->current_volume, cell->target_volume, alpha);
        }
        
        ma_node_set_output_bus_volume(&cell->node, 0, cell->current_volume);
    }
}

// Calculate alpha coefficient for exponential smoothing
static float calculate_smoothing_alpha(float time_ms) {
    float callback_dt = 512.0f / (float)SAMPLE_RATE;  // ~10.7ms at 48kHz
    float time_sec = time_ms / 1000.0f;
    return 1.0f - expf(-callback_dt / time_sec);
}

// Default values indicating "no override" (use sample bank setting)
#define DEFAULT_CELL_VOLUME -1.0f   // Special value meaning "use sample bank volume"
#define DEFAULT_CELL_PITCH -1.0f    // Special value meaning "use sample bank pitch"

// Convert UI pitch value (0.0-1.0) to pitch ratio (0.03125-32.0)
// UI: 0.0 = -12 semitones, 0.5 = 0 semitones, 1.0 = +12 semitones
// Native: pow(2.0, (ui_value * 24 - 12) / 12) = pow(2.0, ui_value * 2 - 1)
static float ui_pitch_to_ratio(float ui_pitch) {
    if (ui_pitch < 0.0f || ui_pitch > 1.0f) return 1.0f; // Fallback to original pitch
    
    // Convert: UI 0.0→-12 semitones, 0.5→0 semitones, 1.0→+12 semitones
    float semitones = ui_pitch * 24.0f - 12.0f;
    return powf(2.0f, semitones / 12.0f);
}

// Convert pitch ratio (0.03125-32.0) to UI pitch value (0.0-1.0)
static float ratio_to_ui_pitch(float ratio) {
    if (ratio <= 0.0f) return 0.5f; // Fallback to center
    
    // Convert: ratio → semitones → UI value
    float semitones = 12.0f * log2f(ratio);
    return (semitones + 12.0f) / 24.0f;
}

// Resolve current volume for a cell (sample bank volume or cell override)
static float resolve_cell_volume(int step, int column, int sample_slot) {
    audio_slot_t* sample = &g_slots[sample_slot];
    float bank_volume = sample->volume;
    float cell_volume = g_sequencer_grid_volumes[step][column];
    return (cell_volume != DEFAULT_CELL_VOLUME) ? cell_volume : bank_volume;
}

// Resolve current pitch for a cell (sample bank pitch or cell override)
static float resolve_cell_pitch(int step, int column, int sample_slot) {
    audio_slot_t* sample = &g_slots[sample_slot];
    float bank_pitch = sample->pitch;
    float cell_pitch = g_sequencer_grid_pitches[step][column];
    return (cell_pitch != DEFAULT_CELL_PITCH) ? cell_pitch : bank_pitch;
}

// Update pitch for a cell node
static void update_cell_pitch(cell_node_t* cell, float new_pitch) {
    if (!cell || !cell->pitch_ds_initialized) return;
    
    cell->pitch = new_pitch;
    ma_pitch_data_source_set_pitch(&cell->pitch_ds, new_pitch);
}

// Find existing node for specific cell (step, column, sample)
static cell_node_t* find_node_for_cell(int step, int column, int sample_slot) {
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        cell_node_t* cell = &g_cell_nodes[i];
        if (cell->active && 
            cell->step == step && 
            cell->column == column && 
            cell->sample_slot == sample_slot) {
            return cell;
        }
    }
    return NULL;  // No existing node found for this cell
}

// Update volume/pitch for existing nodes when settings change
static void update_existing_nodes_for_cell(int step, int column, int sample_slot) {
    cell_node_t* existing_node = find_node_for_cell(step, column, sample_slot);
    if (existing_node) {
        float resolved_pitch = resolve_cell_pitch(step, column, sample_slot);
        float resolved_volume = resolve_cell_volume(step, column, sample_slot);
        
        if (g_current_pitch_method == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING) {
            // For preprocessing approach: if pitch changed, we need to recreate the node
            // because preprocessed data can't be changed in real-time
            if (fabs(existing_node->pitch - resolved_pitch) > 0.001f) {
                prnt("🔄 [UPDATE] Pitch changed for preprocessed node [%d,%d] sample %d (%.3f → %.3f) - recreating node", 
                     step, column, sample_slot, existing_node->pitch, resolved_pitch);
                
                // Remember if this was the currently playing node
                bool was_currently_playing = (currently_playing_nodes_per_col[column] == existing_node);
                
                // Clean up existing node
                cleanup_cell_node(existing_node);
                
                // Create new node with new pitch
                cell_node_t* new_node = create_cell_node(step, column, sample_slot, resolved_volume, resolved_pitch);
                if (new_node) {
                    // If this was the currently playing node, update the tracking and start playing
                    if (was_currently_playing) {
                        currently_playing_nodes_per_col[column] = new_node;
                        set_target_volume(new_node, resolved_volume);
                        prnt("🔄 [UPDATE] Recreated and activated node [%d,%d] sample %d (vol: %.2f, pitch: %.3f)", 
                             step, column, sample_slot, resolved_volume, resolved_pitch);
                    } else {
                        // Start silenced
                        ma_node_set_output_bus_volume(&new_node->node, 0, 0.0f);
                        prnt("🔄 [UPDATE] Recreated silent node [%d,%d] sample %d (vol: %.2f, pitch: %.3f)", 
                             step, column, sample_slot, resolved_volume, resolved_pitch);
                    }
                } else {
                    prnt_err("🔴 [UPDATE] Failed to recreate node for pitch change [%d,%d] sample %d", 
                             step, column, sample_slot);
                }
            } else {
                // Pitch didn't change, just update volume
                existing_node->volume = resolved_volume;
                prnt("🔄 [UPDATE] Updated volume for existing node [%d,%d] sample %d (vol: %.2f, pitch unchanged: %.3f)", 
                     step, column, sample_slot, resolved_volume, resolved_pitch);
            }
        } else {
            // For real-time pitch methods: update pitch directly
            update_cell_pitch(existing_node, resolved_pitch);
            existing_node->volume = resolved_volume;
            
            prnt("🔄 [UPDATE] Updated existing node [%d,%d] sample %d (vol: %.2f, pitch: %.3f)", 
                 step, column, sample_slot, resolved_volume, resolved_pitch);
        }
    }
}

// Set target volume with exponential smoothing
static void set_target_volume(cell_node_t* cell, float new_target_volume) {
    if (!cell) return;
    
    if (volume_has_converged(cell->current_volume, new_target_volume)) {
        cell->target_volume = new_target_volume;
        cell->current_volume = new_target_volume;
        cell->is_volume_smoothing = 0;
        return;
    }
    
    cell->target_volume = new_target_volume;
    cell->is_volume_smoothing = 1;
    cell->volume_rise_coeff = calculate_smoothing_alpha(VOLUME_RISE_TIME_MS);
    cell->volume_fall_coeff = calculate_smoothing_alpha(VOLUME_FALL_TIME_MS);
}

static cell_node_t* create_cell_node(int step, int column, int sample_slot, float volume, float pitch) {
    if (sample_slot < 0 || sample_slot >= MAX_SLOTS) {
        prnt_err("🔴 [CELL NODE] Invalid sample slot: %d", sample_slot);
        return NULL;
    }
    
    audio_slot_t* sample = &g_slots[sample_slot];
    if (!sample->loaded || !sample->file_path) {
        prnt_err("🔴 [CELL NODE] Sample %d not loaded or missing file path", sample_slot);
        return NULL;
    }
    
    cell_node_t* cell = find_available_cell_node();
    if (!cell) return NULL;
    
    // Initialize cell metadata
    cell->active = 1;
    cell->step = step;
    cell->column = column;
    cell->sample_slot = sample_slot;
    cell->volume = volume;
    cell->pitch = pitch;
    cell->is_fading_out = 0;
    cell->fade_start_frame = 0;
    cell->is_fading_in = 0;
    cell->fade_in_start_frame = 0;
    cell->current_volume = 0.0f;          // Start silent, will fade in when triggered
    cell->target_volume = volume;         // Target is desired volume
    cell->volume_rise_coeff = 0.0f;       // Will be calculated when smoothing starts
    cell->volume_fall_coeff = 0.0f;       // Will be calculated when smoothing starts
    cell->is_volume_smoothing = 0;        // No smoothing initially
    cell->start_frame = g_current_frame;
    cell->id = g_next_cell_node_id++;
    
    ma_result result;
    ma_data_source_node_config nodeConfig; // Declare once outside conditional blocks
    preprocessed_sample_t* preprocessed = NULL; // Declare outside to avoid scope issues
    
    // Configure decoder properly with format, channels, and sample rate
    ma_decoder_config decoderConfig = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    
    if (g_current_pitch_method == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING) {
        // Check for preprocessed sample first
        preprocessed = find_preprocessed_sample(sample_slot, pitch);
        if (!preprocessed && fabs(pitch - 1.0f) > 0.001f) {
            // Automatically preprocess on demand if not cached and pitch is needed
            prnt("⚡ [PREPROCESS] Auto-preprocessing sample %d at pitch %.3f (not cached)", sample_slot, pitch);
            if (preprocess_sample_with_pitch(sample_slot, pitch) == 0) {
                preprocessed = find_preprocessed_sample(sample_slot, pitch);
            }
        }
        
        if (preprocessed) {
            // Use preprocessed sample data (already pitch-processed) with ma_audio_buffer
            // Create audio buffer config for raw PCM data
            ma_audio_buffer_config bufferConfig = ma_audio_buffer_config_init(
                SAMPLE_FORMAT, CHANNEL_COUNT, preprocessed->processed_frames, 
                preprocessed->processed_data, NULL
            );
            
            result = ma_audio_buffer_init(&bufferConfig, &cell->audio_buffer);
            if (result != MA_SUCCESS) {
                prnt_err("🔴 [CELL NODE] Failed to initialize audio buffer from preprocessed data: %d", result);
                cleanup_cell_node(cell);
                return NULL;
            }
            
            cell->audio_buffer_initialized = 1;
            cell->uses_audio_buffer = 1;
            cell->audio_buffer_frame_count = preprocessed->processed_frames;
            
            // NO pitch data source needed - sample is already pitch-processed
            cell->pitch_ds_initialized = 0;
            
            // Create data source node directly from audio buffer (audio_buffer → data_source_node)
            nodeConfig = ma_data_source_node_config_init(&cell->audio_buffer);
            
            prnt("🎯 [CELL NODE] Using preprocessed sample: slot %d, pitch %.3f (%.2f MB)", 
                 sample_slot, pitch, preprocessed->processed_size / (1024.0 * 1024.0));
        } else if (fabs(pitch - 1.0f) <= 0.001f) {
            // Close to original pitch - use original sample directly
            if (sample->memory_data) {
                result = ma_decoder_init_memory(sample->memory_data, sample->memory_size, &decoderConfig, &cell->decoder);
            } else {
                result = ma_decoder_init_file(sample->file_path, &decoderConfig, &cell->decoder);
            }
            
            if (result != MA_SUCCESS) {
                prnt_err("🔴 [CELL NODE] Failed to initialize decoder for sample %d: %d", sample_slot, result);
                cleanup_cell_node(cell);
                return NULL;
            }
            
            cell->uses_audio_buffer = 0;  // Using decoder, not audio buffer
            cell->audio_buffer_initialized = 0;
            
            // NO pitch data source needed - using original sample
            cell->pitch_ds_initialized = 0;
            
            // Create data source node directly from decoder
            nodeConfig = ma_data_source_node_config_init(&cell->decoder);
            
            prnt("🎯 [CELL NODE] Using original sample (no preprocessing needed): slot %d, pitch %.3f", sample_slot, pitch);
        } else {
            // Significant pitch change but preprocessing failed - this shouldn't happen with auto-preprocessing
            prnt_err("🔴 [CELL NODE] Preprocessing failed for significant pitch change: slot %d, pitch %.3f", sample_slot, pitch);
            cleanup_cell_node(cell);
            return NULL;
        }
    } else {
        // Use real-time pitch processing (for other methods)
        
        // Initialize decoder from sample file or memory
        if (sample->memory_data) {
            result = ma_decoder_init_memory(sample->memory_data, sample->memory_size, &decoderConfig, &cell->decoder);
        } else {
            result = ma_decoder_init_file(sample->file_path, &decoderConfig, &cell->decoder);
        }
        
        if (result != MA_SUCCESS) {
            prnt_err("🔴 [CELL NODE] Failed to initialize decoder for sample %d: %d", sample_slot, result);
            cleanup_cell_node(cell);
            return NULL;
        }
        
        cell->uses_audio_buffer = 0;  // Using decoder, not audio buffer
        cell->audio_buffer_initialized = 0;
        
        // Initialize pitch data source around decoder (decoder → pitch_data_source)
        result = ma_pitch_data_source_init(&cell->pitch_ds, &cell->decoder, pitch, CHANNEL_COUNT, SAMPLE_RATE);
        if (result != MA_SUCCESS) {
            prnt_err("🔴 [CELL NODE] Failed to initialize pitch data source: %d", result);
            ma_decoder_uninit(&cell->decoder);
            cleanup_cell_node(cell);
            return NULL;
        }
        cell->pitch_ds_initialized = 1;
        
        // Initialize data source node from pitch data source (pitch_data_source → data_source_node)
        nodeConfig = ma_data_source_node_config_init(&cell->pitch_ds);
        
        prnt("🔄 [CELL NODE] Using real-time pitch processing: slot %d, pitch %.3f", sample_slot, pitch);
    }
    
    result = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &cell->node);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [CELL NODE] Failed to initialize node: %d", result);
        ma_pitch_data_source_uninit(&cell->pitch_ds);
        cell->pitch_ds_initialized = 0;
        ma_decoder_uninit(&cell->decoder);
        cleanup_cell_node(cell);
        return NULL;
    }
    cell->node_initialized = 1;
    
    // Connect the node to the node graph endpoint (this is crucial!)
    ma_node_attach_output_bus(&cell->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    
    // Set initial volume (start silent, will ramp to target when triggered)
    ma_node_set_output_bus_volume(&cell->node, 0, 0.0f);
    
    prnt("✅ [CELL NODE] Created cell [%d,%d] with sample %d (vol: %.2f, pitch: %.2f, ID: %llu)", 
         step, column, sample_slot, volume, pitch, cell->id);
    
    return cell;
}

static void monitor_cell_nodes(void) {
    static uint64_t cleanup_call_count = 0;
    static uint64_t last_cleanup_log = 0;
    
    cleanup_call_count++;
    
    int active_nodes = 0;
    int finished_nodes = 0;
    
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        cell_node_t* cell = &g_cell_nodes[i];
        if (!cell->active) continue;
        
        active_nodes++;
        
        // Check if playback has finished
        ma_bool32 at_end = MA_FALSE;
        if (cell->node_initialized) {
            if (cell->uses_audio_buffer && cell->audio_buffer_initialized) {
                // For audio buffer (preprocessed data), check cursor position
                ma_uint64 cursor;
                ma_result result = ma_data_source_get_cursor_in_pcm_frames(&cell->audio_buffer, &cursor);
                if (result == MA_SUCCESS && cell->audio_buffer_frame_count > 0) {
                    at_end = (cursor >= cell->audio_buffer_frame_count);
                }
            } else if (cell->pitch_ds_initialized) {
                // For decoder with pitch data source
                ma_uint64 cursor;
                ma_result result = ma_decoder_get_cursor_in_pcm_frames(&cell->decoder, &cursor);
                if (result == MA_SUCCESS) {
                    ma_uint64 length;
                    result = ma_decoder_get_length_in_pcm_frames(&cell->decoder, &length);
                    if (result == MA_SUCCESS && length > 0) {
                        at_end = (cursor >= length);
                    }
                }
            }
        }
        
        if (at_end) {
            // Just log that sample finished - rewinding handled when triggered
            // prnt("🏁 [FINISHED] Node #%d [%d,%d] sample %d finished playing (ID: %llu)", 
                //  i, cell->step, cell->column, cell->sample_slot, cell->id);
            finished_nodes++;
        }
    }
    
    // Log cleanup stats every 1000 calls or when nodes finish
    if (finished_nodes > 0 || (cleanup_call_count % 1000 == 0 && cleanup_call_count > last_cleanup_log)) {
        // prnt("📊 [MONITOR] Call #%llu: %d active nodes, %d finished playing", 
            //  cleanup_call_count, active_nodes, finished_nodes);
        last_cleanup_log = cleanup_call_count;
    }
}

// -----------------------------------------------------------------------------
// Zero-Crossing Detection for Click-Free Audio Transitions
// -----------------------------------------------------------------------------

#define ZERO_CROSSING_SEARCH_FRAMES 4800   // Search up to ~100ms at 48kHz for zero crossing
#define ZERO_THRESHOLD 0.01f               // Consider values below this as "zero" (1% of max amplitude)

// Global flag to enable/disable zero-crossing detection (for A/B testing)
// NOTE: We use exponential volume smoothing which is superior to zero-crossing detection
// Set to 1 to enable zero-crossing, 0 to use exponential smoothing (recommended)
static int g_zero_crossing_enabled = 0;  // Use exponential smoothing by default

// Find nearest zero-crossing point in audio data
static ma_uint64 find_zero_crossing(float* samples, ma_uint64 start_frame, ma_uint64 max_frames, ma_uint32 channels, bool search_forward) {
    if (!samples || channels == 0 || max_frames == 0) return start_frame;
    
    ma_uint64 best_frame = start_frame;
    float best_amplitude = FLT_MAX;
    ma_uint64 search_count = 0;
    
    // Determine search bounds
    ma_uint64 search_start, search_end;
    if (search_forward) {
        search_start = start_frame;
        search_end = (start_frame + ZERO_CROSSING_SEARCH_FRAMES < max_frames) ? 
                     start_frame + ZERO_CROSSING_SEARCH_FRAMES : max_frames;
    } else {
        search_start = (start_frame > ZERO_CROSSING_SEARCH_FRAMES) ? 
                       start_frame - ZERO_CROSSING_SEARCH_FRAMES : 0;
        search_end = start_frame;
    }
    
    // Get initial sample for sign comparison
    float prev_sample = 0.0f;
    if (search_start < max_frames) {
        prev_sample = samples[search_start * channels]; // Use first channel
    }
    
    // Search for zero crossings
    for (ma_uint64 frame = search_start; frame < search_end && frame < max_frames; frame++) {
        search_count++;
        
        float current_sample = samples[frame * channels]; // Use first channel
        float abs_amplitude = fabsf(current_sample);
        
        // Check for zero crossing (sign change) or very low amplitude
        bool is_zero_crossing = false;
        
        // Method 1: True zero crossing (sign change)
        if (prev_sample * current_sample <= 0.0f && (fabsf(prev_sample) > ZERO_THRESHOLD || abs_amplitude > ZERO_THRESHOLD)) {
            is_zero_crossing = true;
        }
        
        // Method 2: Very low amplitude (close to zero)
        if (abs_amplitude < ZERO_THRESHOLD) {
            is_zero_crossing = true;
        }
        
        if (is_zero_crossing && abs_amplitude < best_amplitude) {
            best_frame = frame;
            best_amplitude = abs_amplitude;
            
            // If we found a perfect zero or very close, use it immediately
            if (abs_amplitude < ZERO_THRESHOLD / 10.0f) {
                prnt("🎯 [ZERO-CROSS] Found perfect zero at frame %llu (amplitude: %.6f)", frame, abs_amplitude);
                break;
            }
        }
        
        prev_sample = current_sample;
    }
    
    prnt("🔍 [ZERO-CROSS] Searched %llu frames, start=%llu, found best at %llu (amplitude: %.6f)", 
         search_count, start_frame, best_frame, best_amplitude);
    
    return best_frame;
}

// Find zero-crossing point for decoder start position
static ma_uint64 find_decoder_start_zero_crossing(ma_decoder* decoder) {
    if (!decoder) return 0;
    
    // Read some audio data from the beginning
    float temp_buffer[ZERO_CROSSING_SEARCH_FRAMES * 2]; // Stereo support
    ma_uint64 frames_read = 0;
    
    // Save current position
    ma_uint64 original_cursor;
    ma_decoder_get_cursor_in_pcm_frames(decoder, &original_cursor);
    
    // Seek to start and read data
    ma_decoder_seek_to_pcm_frame(decoder, 0);
    ma_result result = ma_decoder_read_pcm_frames(decoder, temp_buffer, ZERO_CROSSING_SEARCH_FRAMES, &frames_read);
    
    ma_uint64 zero_frame = 0;
    if (result == MA_SUCCESS && frames_read > 0) {
        ma_format format;
        ma_uint32 channels;
        ma_uint32 sample_rate;
        ma_decoder_get_data_format(decoder, &format, &channels, &sample_rate, NULL, 0);
        
        prnt("🔍 [ZERO-CROSS] Analyzing start: format=%d, channels=%d, frames_read=%llu", 
             format, channels, frames_read);
        
        zero_frame = find_zero_crossing(temp_buffer, 0, frames_read, channels, true);
        
        // Fallback: if zero-crossing didn't find a better position, skip the first few frames
        if (zero_frame == 0 && frames_read > 48) {
            zero_frame = 48; // Skip first 1ms to avoid potential click at exact start
            prnt("🔄 [ZERO-CROSS] Using fallback: skipping to frame %llu", zero_frame);
        }
    }
    
    // Restore original position
    ma_decoder_seek_to_pcm_frame(decoder, original_cursor);
    
    return zero_frame;
}

// Find zero-crossing point for fade-out (current position)
static ma_uint64 find_decoder_fadeout_zero_crossing(ma_decoder* decoder) {
    if (!decoder) return 0;
    
    // Get current position
    ma_uint64 current_cursor;
    ma_decoder_get_cursor_in_pcm_frames(decoder, &current_cursor);
    
    // For fadeout, we want to find a zero-crossing close to the current position
    // But not too far ahead to avoid disrupting the audio flow
    ma_uint64 search_window = 480; // 10ms at 48kHz - shorter window for fadeout
    
    // Read some audio data around current position
    float temp_buffer[960 * 2]; // 20ms stereo buffer
    ma_uint64 frames_read = 0;
    
    // Read from current position forward
    ma_result result = ma_decoder_read_pcm_frames(decoder, temp_buffer, search_window, &frames_read);
    
    ma_uint64 zero_frame = current_cursor;
    if (result == MA_SUCCESS && frames_read > 0) {
        ma_format format;
        ma_uint32 channels;
        ma_uint32 sample_rate;
        ma_decoder_get_data_format(decoder, &format, &channels, &sample_rate, NULL, 0);
        
        prnt("🔍 [ZERO-CROSS] Analyzing fadeout: current=%llu, search_window=%llu, frames_read=%llu", 
             current_cursor, search_window, frames_read);
        
        // Find zero crossing from current position forward
        ma_uint64 relative_zero = find_zero_crossing(temp_buffer, 0, frames_read, channels, true);
        zero_frame = current_cursor + relative_zero;
        
        // Fallback: if no good zero-crossing found, just use current position
        if (relative_zero == 0) {
            zero_frame = current_cursor;
            prnt("🔄 [ZERO-CROSS] Using current position for fadeout: %llu", zero_frame);
        }
    }
    
    // Restore original position
    ma_decoder_seek_to_pcm_frame(decoder, current_cursor);
    
    return zero_frame;
}

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

// -----------------------------------------------------------------------------
// Modular Pitch Processing Functions - Clean separation of approaches
// -----------------------------------------------------------------------------

// Approach 1: Miniaudio resampler pitch processing
static ma_result pitch_read_miniaudio(ma_pitch_data_source* pPitch, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    // If resampler is not initialized or pitch ratio is 1.0 (no change), pass through
    if (!pPitch->resampler_initialized || pPitch->pitch_ratio == 1.0f) {
        return ma_data_source_read_pcm_frames(pPitch->original_ds, pFramesOut, frameCount, pFramesRead);
    }
    
    // Use miniaudio resampler for pitch shifting
    const ma_uint64 tempCapacityInFrames = pPitch->temp_input_buffer_size / pPitch->channels;
    
    // For pitch shifting, estimate input frames needed based on pitch ratio
    // INVERTED: Higher pitch = need fewer input frames, lower pitch = need more input frames
    ma_uint64 inputFramesNeeded = (ma_uint64)(frameCount / pPitch->pitch_ratio);
    if (inputFramesNeeded < 1) inputFramesNeeded = 1; // Always read at least 1 frame
    if (inputFramesNeeded > tempCapacityInFrames) {
        inputFramesNeeded = tempCapacityInFrames;
    }
    
    // Read input frames from original data source using instance-specific buffer
    ma_uint64 inputFramesRead = 0;
    ma_result result = ma_data_source_read_pcm_frames(pPitch->original_ds, pPitch->temp_input_buffer, inputFramesNeeded, &inputFramesRead);
    
    if (result != MA_SUCCESS || inputFramesRead == 0) {
        return result;
    }
    
    // Process through the resampler
    ma_uint64 inputFramesToProcess = inputFramesRead;
    ma_uint64 outputFramesProcessed = frameCount;
    result = ma_resampler_process_pcm_frames(&pPitch->resampler, pPitch->temp_input_buffer, &inputFramesToProcess, pFramesOut, &outputFramesProcessed);
    
    if (result == MA_SUCCESS) {
        *pFramesRead = outputFramesProcessed;
    }
    
    return result;
}

// Approach 2: SoundTouch real-time pitch processing
static ma_result pitch_read_soundtouch_realtime(ma_pitch_data_source* pPitch, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    // Bypass SoundTouch for normal pitch (no processing needed) or if not initialized
    if (!pPitch->soundtouch_initialized || fabs(pPitch->pitch_ratio - 1.0f) < 0.001f) {
        return ma_data_source_read_pcm_frames(pPitch->original_ds, pFramesOut, frameCount, pFramesRead);
    }
    
    // Skip processing for very small frame counts to reduce overhead
    if (frameCount < 128) {  // Increased from 64 to 128 for better isolation
        return ma_data_source_read_pcm_frames(pPitch->original_ds, pFramesOut, frameCount, pFramesRead);
    }
    
    float* outputBuffer = (float*)pFramesOut;
    ma_uint64 totalFramesRead = 0;
    ma_uint64 framesToProcess = frameCount;
    
    try {
        // Process audio through SoundTouch in chunks for mobile efficiency
        while (totalFramesRead < frameCount && framesToProcess > 0) {
            // Debug instance state every 100 calls
            debug_soundtouch_instance("READ_PCM", pPitch);
            
            // ISOLATION CHECK: Verify instance integrity before processing
            if (!pPitch->soundtouch_processor) {
                prnt_err("🔴 [PITCH] SoundTouch processor became null during processing");
                break;
            }
            
            // Try to get processed samples from SoundTouch first
            uint outputSamplesAvailable = pPitch->soundtouch_processor->numSamples();
            
            if (outputSamplesAvailable > 0) {
                // Get available processed samples from SoundTouch
                uint framesToReceive = (uint)MIN(framesToProcess, outputSamplesAvailable);
                uint samplesReceived = pPitch->soundtouch_processor->receiveSamples(
                    outputBuffer + (totalFramesRead * pPitch->channels), 
                    framesToReceive
                );
                
                totalFramesRead += samplesReceived;
                framesToProcess -= samplesReceived;
                
                if (samplesReceived == 0) break; // No more output available
            }
            
            // If we need more output, feed more input to SoundTouch
            if (framesToProcess > 0) {
                // BUFFER SAFETY: Ensure temp buffer is valid and isolated
                if (!pPitch->temp_buffer || pPitch->temp_buffer_size == 0) {
                    prnt_err("🔴 [PITCH] Invalid temp buffer for instance %p", (void*)pPitch);
                    break;
                }
                
                // Read input frames from original data source - use very small chunks for real-time
                ma_uint64 inputFramesToRead = MIN(128, pPitch->temp_buffer_size / pPitch->channels); // Ultra-small chunks for isolation
                ma_uint64 inputFramesRead = 0;
                
                ma_result result = ma_data_source_read_pcm_frames(
                    pPitch->original_ds, 
                    pPitch->temp_buffer, 
                    inputFramesToRead, 
                    &inputFramesRead
                );
                
                if (result != MA_SUCCESS || inputFramesRead == 0) {
                    // No more input available, flush remaining samples
                    pPitch->soundtouch_processor->flush();
                    break;
                }
                
                // ISOLATION: Verify processor is still valid before feeding data
                if (!pPitch->soundtouch_processor) {
                    prnt_err("🔴 [PITCH] SoundTouch processor became null before putSamples");
                    break;
                }
                
                // Feed input samples to SoundTouch
                pPitch->soundtouch_processor->putSamples(pPitch->temp_buffer, (uint)inputFramesRead);
                pPitch->input_frames_pending += inputFramesRead;
            }
        }
        
        *pFramesRead = totalFramesRead;
        return (totalFramesRead > 0) ? MA_SUCCESS : MA_AT_END;
        
    } catch (...) {
        prnt_err("🔴 [PITCH] SoundTouch processing error");
        return MA_ERROR;
    }
}

// Approach 3: SoundTouch preprocessing pitch processing
static ma_result pitch_read_soundtouch_preprocessing(ma_pitch_data_source* pPitch, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    // Check if this instance uses preprocessed data
    if (pPitch->uses_preprocessed_data && pPitch->preprocessed_decoder) {
        // Read directly from preprocessed decoder (no real-time processing)
        return ma_data_source_read_pcm_frames((ma_data_source*)pPitch->preprocessed_decoder, pFramesOut, frameCount, pFramesRead);
    }
    
    // Fallback to miniaudio resampler if no cached data available
    return pitch_read_miniaudio(pPitch, pFramesOut, frameCount, pFramesRead);
}

// Pitch data source callbacks
static ma_result ma_pitch_data_source_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL || pFramesOut == NULL || pFramesRead == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // Initialize pFramesRead to 0
    *pFramesRead = 0;
    
    // Runtime method selection - clean and modular
    switch (pPitch->approach) {
        case PITCH_METHOD_MINIAUDIO:
            return pitch_read_miniaudio(pPitch, pFramesOut, frameCount, pFramesRead);
            
        case PITCH_METHOD_SOUNDTOUCH_REALTIME:
            return pitch_read_soundtouch_realtime(pPitch, pFramesOut, frameCount, pFramesRead);
            
        case PITCH_METHOD_SOUNDTOUCH_PREPROCESSING:
            return pitch_read_soundtouch_preprocessing(pPitch, pFramesOut, frameCount, pFramesRead);
            
        default:
            prnt_err("🔴 [PITCH] Unknown pitch method: %d", pPitch->approach);
            return MA_INVALID_ARGS;
    }
}

static ma_result ma_pitch_data_source_seek(ma_data_source* pDataSource, ma_uint64 frameIndex) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
#if PITCH_APPROACH_MINIAUDIO
    // miniaudio resampler - no special handling needed
#elif PITCH_APPROACH_SOUNDTOUCH_REALTIME
    // SoundTouch implementation - clear processor state on seek
    if (pPitch->soundtouch_initialized && pPitch->soundtouch_processor) {
        try {
            pPitch->soundtouch_processor->clear();
            pPitch->input_frames_pending = 0;
        } catch (...) {
            prnt_err("🔴 [PITCH] SoundTouch seek error");
        }
    }
#elif PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // Preprocessing approach - seek preprocessed decoder if available
    if (pPitch->uses_preprocessed_data && pPitch->preprocessed_decoder) {
        return ma_data_source_seek_to_pcm_frame((ma_data_source*)pPitch->preprocessed_decoder, frameIndex);
    }
    // Otherwise no special handling needed for fallback resampler
#endif
    
    // Seek the original data source 
    return ma_data_source_seek_to_pcm_frame(pPitch->original_ds, frameIndex);
}

static ma_result ma_pitch_data_source_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap) {
    ma_pitch_data_source* pPitch = (ma_pitch_data_source*)pDataSource;
    
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
#if PITCH_APPROACH_SOUNDTOUCH_REALTIME || PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // SoundTouch: always return the same format as input
    return ma_data_source_get_data_format(pPitch->original_ds, pFormat, pChannels, pSampleRate, pChannelMap, channelMapCap);
#else
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
#endif
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
    
    if (result == MA_SUCCESS && pPitch->approach == PITCH_METHOD_MINIAUDIO) {
        // If using resampler, adjust the length based on the pitch ratio
        // INVERTED: Higher pitch = shorter duration, lower pitch = longer duration
        if (pPitch->resampler_initialized && pPitch->pitch_ratio != 1.0f) {
            *pLength = (ma_uint64)(*pLength * pPitch->pitch_ratio);
        }
    }
    // For SoundTouch approaches: length stays the same regardless of pitch
    
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

// -----------------------------------------------------------------------------
// Modular Pitch Initialization Functions - Clean separation of approaches
// -----------------------------------------------------------------------------

// Initialize for miniaudio resampler approach
static ma_result pitch_init_miniaudio(ma_pitch_data_source* pPitch, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate) {
    pPitch->resampler_initialized = 0;
    pPitch->temp_input_buffer = NULL;
    pPitch->temp_input_buffer_size = 0;
    
    if (pitchRatio != 1.0f) {
        // Calculate target sample rate for pitch shifting
        pPitch->target_sample_rate = (ma_uint32)(sampleRate / pitchRatio);
        
        // Clamp to reasonable range
        if (pPitch->target_sample_rate < 8000) pPitch->target_sample_rate = 8000;
        if (pPitch->target_sample_rate > 192000) pPitch->target_sample_rate = 192000;
        
        // Allocate temp buffer
        pPitch->temp_input_buffer_size = 4096 * channels;
        pPitch->temp_input_buffer = (float*)malloc(pPitch->temp_input_buffer_size * sizeof(float));
        
        if (!pPitch->temp_input_buffer) {
            prnt_err("🔴 [PITCH] Failed to allocate temp input buffer");
            return MA_OUT_OF_MEMORY;
        }
        
        // Configure resampler
        ma_resampler_config resamplerConfig = ma_resampler_config_init(
            SAMPLE_FORMAT, channels, sampleRate, pPitch->target_sample_rate, ma_resample_algorithm_linear
        );
        
        ma_result result = ma_resampler_init(&resamplerConfig, NULL, &pPitch->resampler);
        if (result == MA_SUCCESS) {
            pPitch->resampler_initialized = 1;
            prnt("✅ [PITCH] Initialized miniaudio resampler: %.2fx pitch", pitchRatio);
        } else {
            prnt_err("🔴 [PITCH] Failed to initialize resampler: %s", ma_result_description(result));
            free(pPitch->temp_input_buffer);
            pPitch->temp_input_buffer = NULL;
            return result;
        }
    }
    return MA_SUCCESS;
}

// Initialize for SoundTouch real-time approach
static ma_result pitch_init_soundtouch_realtime(ma_pitch_data_source* pPitch, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate) {
    pPitch->soundtouch_processor = NULL;
    pPitch->soundtouch_initialized = 0;
    pPitch->temp_buffer = NULL;
    pPitch->temp_buffer_size = 0;
    pPitch->input_frames_pending = 0;
    
    // Only create SoundTouch for significant pitch changes
    if (fabs(pitchRatio - 1.0f) > 0.10f) {
        try {
            pPitch->soundtouch_processor = new SoundTouch();
            pPitch->soundtouch_processor->setSampleRate(sampleRate);
            pPitch->soundtouch_processor->setChannels(channels);
            pPitch->soundtouch_processor->clear();
            
            // Mobile-optimized settings
            pPitch->soundtouch_processor->setSetting(SETTING_USE_QUICKSEEK, 1);
            pPitch->soundtouch_processor->setSetting(SETTING_USE_AA_FILTER, 0);
            pPitch->soundtouch_processor->setSetting(SETTING_SEQUENCE_MS, 10);
            pPitch->soundtouch_processor->setSetting(SETTING_SEEKWINDOW_MS, 4);
            pPitch->soundtouch_processor->setSetting(SETTING_OVERLAP_MS, 2);
            
            pPitch->soundtouch_processor->setPitch(pitchRatio);
            
            pPitch->temp_buffer_size = 256 * channels;
            pPitch->temp_buffer = (float*)malloc(pPitch->temp_buffer_size * sizeof(float));
            
            if (pPitch->temp_buffer) {
                pPitch->soundtouch_initialized = 1;
                prnt("✅ [PITCH] Initialized SoundTouch realtime: %.2fx pitch", pitchRatio);
            } else {
                delete pPitch->soundtouch_processor;
                pPitch->soundtouch_processor = NULL;
                return MA_OUT_OF_MEMORY;
            }
        } catch (...) {
            prnt_err("🔴 [PITCH] Failed to initialize SoundTouch processor");
            return MA_ERROR;
        }
    } else {
        prnt("✅ [PITCH] Skipping SoundTouch for small pitch change: %.2fx", pitchRatio);
    }
    return MA_SUCCESS;
}

// Initialize for SoundTouch preprocessing approach
static ma_result pitch_init_soundtouch_preprocessing(ma_pitch_data_source* pPitch, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate) {
    pPitch->sample_slot = -1;
    pPitch->preprocessed_decoder = NULL;
    pPitch->uses_preprocessed_data = 0;
    
    // Initialize fallback miniaudio resampler
    ma_result result = pitch_init_miniaudio(pPitch, pitchRatio, channels, sampleRate);
    if (result == MA_SUCCESS) {
        prnt("✅ [PITCH] Initialized preprocessing with fallback resampler: %.2fx pitch", pitchRatio);
    }
    return result;
}

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
    pPitch->approach = g_current_pitch_method;  // Use global method setting
    
    // Initialize fields based on current pitch method
    switch (pPitch->approach) {
        case PITCH_METHOD_MINIAUDIO:
            return pitch_init_miniaudio(pPitch, pitchRatio, channels, sampleRate);
            
        case PITCH_METHOD_SOUNDTOUCH_REALTIME:
            return pitch_init_soundtouch_realtime(pPitch, pitchRatio, channels, sampleRate);
            
        case PITCH_METHOD_SOUNDTOUCH_PREPROCESSING:
            return pitch_init_soundtouch_preprocessing(pPitch, pitchRatio, channels, sampleRate);
            
        default:
            prnt_err("🔴 [PITCH] Unknown pitch method: %d", pPitch->approach);
            return MA_INVALID_ARGS;
    }
}

// Special init function for preprocessing approach with sample slot info
#if PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
static ma_result ma_pitch_data_source_init_with_preprocessing(ma_pitch_data_source* pPitch, ma_data_source* pOriginalDataSource, float pitchRatio, ma_uint32 channels, ma_uint32 sampleRate, int sample_slot) {
    ma_result result = ma_pitch_data_source_init(pPitch, pOriginalDataSource, pitchRatio, channels, sampleRate);
    if (result != MA_SUCCESS) {
        return result;
    }
    
    pPitch->sample_slot = sample_slot;
    
    // Check for preprocessed data
    preprocessed_sample_t* preprocessed = find_preprocessed_sample(sample_slot, pitchRatio);
    if (preprocessed) {
        // Create decoder for preprocessed data
        pPitch->preprocessed_decoder = (ma_decoder*)malloc(sizeof(ma_decoder));
        if (pPitch->preprocessed_decoder) {
            ma_decoder_config decoderConfig = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
            result = ma_decoder_init_memory(preprocessed->processed_data, preprocessed->processed_size, &decoderConfig, pPitch->preprocessed_decoder);
            if (result == MA_SUCCESS) {
                pPitch->uses_preprocessed_data = 1;
                prnt("✅ [PITCH] Using preprocessed data for sample %d at %.2fx pitch", sample_slot, pitchRatio);
            } else {
                free(pPitch->preprocessed_decoder);
                pPitch->preprocessed_decoder = NULL;
                prnt_err("🔴 [PITCH] Failed to create decoder for preprocessed data");
            }
        }
    }
    
    return MA_SUCCESS;
}
#endif

// Update pitch ratio
static ma_result ma_pitch_data_source_set_pitch(ma_pitch_data_source* pPitch, float pitchRatio) {
    if (pPitch == NULL) {
        return MA_INVALID_ARGS;
    }
    
    // If pitch ratio hasn't changed significantly, don't recreate converter
    if (fabs(pPitch->pitch_ratio - pitchRatio) < 0.001f) {
        return MA_SUCCESS;
    }
    
    pPitch->pitch_ratio = pitchRatio;
    
#if PITCH_APPROACH_MINIAUDIO
    // ========================================================================
    // APPROACH 1: Miniaudio Resampler
    // ========================================================================
    
    // Clean up existing resampler and temp buffer
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    if (pPitch->temp_input_buffer) {
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
    }
    
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
    
    // Allocate instance-specific temp buffer
    pPitch->temp_input_buffer_size = 4096 * pPitch->channels;
    pPitch->temp_input_buffer = (float*)malloc(pPitch->temp_input_buffer_size * sizeof(float));
    
    if (!pPitch->temp_input_buffer) {
        prnt_err("🔴 [PITCH] Failed to allocate temp input buffer");
        return MA_OUT_OF_MEMORY;
    }
    
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
        prnt("🎵 [PITCH] Updated miniaudio resampler: %.2fx pitch (rate: %d -> %d Hz, buffer: %zu samples)", 
             pitchRatio, pPitch->sample_rate, pPitch->target_sample_rate, pPitch->temp_input_buffer_size);
    } else {
        prnt_err("🔴 [PITCH] Failed to initialize resampler: %s", ma_result_description(result));
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
        return result;
    }

#elif PITCH_APPROACH_SOUNDTOUCH_REALTIME
    // ========================================================================
    // APPROACH 2: SoundTouch Real-time
    // ========================================================================
    
    // If new pitch change is small (<10%), clean up SoundTouch to save resources
    if (fabs(pitchRatio - 1.0f) <= 0.10f) {
        if (pPitch->soundtouch_initialized) {
            // Clean up existing SoundTouch processor
            if (pPitch->soundtouch_processor) {
                delete pPitch->soundtouch_processor;
                pPitch->soundtouch_processor = NULL;
            }
            if (pPitch->temp_buffer) {
                free(pPitch->temp_buffer);
                pPitch->temp_buffer = NULL;
            }
            pPitch->soundtouch_initialized = 0;
            pPitch->temp_buffer_size = 0;
            pPitch->input_frames_pending = 0;
            prnt("🗑️ [PITCH] Cleaned up SoundTouch for small pitch change: %.2fx (using passthrough)", pitchRatio);
        }
        return MA_SUCCESS;
    }
    
    // If we have SoundTouch and it's for a significant pitch change, just update it
    if (pPitch->soundtouch_initialized && pPitch->soundtouch_processor) {
        try {
            // Update pitch ratio in SoundTouch (real-time)
            pPitch->soundtouch_processor->setPitch(pitchRatio);
            
            // Clear any pending samples to avoid artifacts
            pPitch->soundtouch_processor->clear();
            pPitch->input_frames_pending = 0;
            
            prnt("🎵 [PITCH] Updated SoundTouch pitch: %.2fx", pitchRatio);
            return MA_SUCCESS;
        } catch (...) {
            prnt_err("🔴 [PITCH] Failed to update SoundTouch pitch");
            return MA_ERROR;
        }
    }
    
    // Need to create new SoundTouch for significant pitch change
    if (fabs(pitchRatio - 1.0f) > 0.10f) {
        try {
            // Create SoundTouch processor for significant pitch changes
            pPitch->soundtouch_processor = new SoundTouch();
            
            // Configure for mobile performance
            pPitch->soundtouch_processor->setSampleRate(pPitch->sample_rate);
            pPitch->soundtouch_processor->setChannels(pPitch->channels);
            
            // Extremely aggressive real-time mobile settings
            pPitch->soundtouch_processor->setSetting(SETTING_USE_QUICKSEEK, 1);
            pPitch->soundtouch_processor->setSetting(SETTING_USE_AA_FILTER, 0);
            pPitch->soundtouch_processor->setSetting(SETTING_SEQUENCE_MS, 15);
            pPitch->soundtouch_processor->setSetting(SETTING_SEEKWINDOW_MS, 6);
            pPitch->soundtouch_processor->setSetting(SETTING_OVERLAP_MS, 3);
            
            // Set pitch
            pPitch->soundtouch_processor->setPitch(pitchRatio);
            
            // Allocate temp buffer
            pPitch->temp_buffer_size = 512 * pPitch->channels;
            pPitch->temp_buffer = (float*)malloc(pPitch->temp_buffer_size * sizeof(float));
            
            if (pPitch->temp_buffer) {
                pPitch->soundtouch_initialized = 1;
                pPitch->input_frames_pending = 0;
                prnt("✅ [PITCH] Created new SoundTouch: %.2fx pitch (aggressive mobile optimized)", pitchRatio);
            } else {
                delete pPitch->soundtouch_processor;
                pPitch->soundtouch_processor = NULL;
                prnt_err("🔴 [PITCH] Failed to allocate SoundTouch buffer");
                return MA_OUT_OF_MEMORY;
            }
        } catch (...) {
            prnt_err("🔴 [PITCH] Failed to create SoundTouch processor");
            return MA_ERROR;
        }
    }

#elif PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // ========================================================================
    // APPROACH 3: SoundTouch Preprocessing
    // ========================================================================
    
    // For preprocessing approach, pitch changes require re-processing the sample
    // For now, we'll just update the fallback resampler
    
    // Clean up existing fallback resampler
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    if (pPitch->temp_input_buffer) {
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
    }
    
    // If pitch ratio is 1.0 (no change), don't create resampler
    if (pitchRatio == 1.0f) {
        prnt("🎵 [PITCH] Reset to normal pitch (preprocessing will handle this)");
        return MA_SUCCESS;
    }
    
    // Setup fallback resampler for real-time changes
    pPitch->target_sample_rate = (ma_uint32)(pPitch->sample_rate / pitchRatio);
    if (pPitch->target_sample_rate < 8000) pPitch->target_sample_rate = 8000;
    if (pPitch->target_sample_rate > 192000) pPitch->target_sample_rate = 192000;
    
    pPitch->temp_input_buffer_size = 4096 * pPitch->channels;
    pPitch->temp_input_buffer = (float*)malloc(pPitch->temp_input_buffer_size * sizeof(float));
    
    if (!pPitch->temp_input_buffer) {
        prnt_err("🔴 [PITCH] Failed to allocate fallback temp buffer");
        return MA_OUT_OF_MEMORY;
    }
    
    ma_resampler_config resamplerConfig = ma_resampler_config_init(
        SAMPLE_FORMAT, pPitch->channels, pPitch->sample_rate, pPitch->target_sample_rate, ma_resample_algorithm_linear
    );
    
    ma_result result = ma_resampler_init(&resamplerConfig, NULL, &pPitch->resampler);
    if (result == MA_SUCCESS) {
        pPitch->resampler_initialized = 1;
        prnt("🎵 [PITCH] Updated preprocessing fallback resampler: %.2fx pitch", pitchRatio);
    } else {
        prnt_err("🔴 [PITCH] Failed to initialize fallback resampler: %s", ma_result_description(result));
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
        return result;
    }
#endif
    
    return MA_SUCCESS;
}

// Uninitialize pitch data source
static void ma_pitch_data_source_uninit(ma_pitch_data_source* pPitch) {
    if (pPitch == NULL) {
        return;
    }
    
#if PITCH_APPROACH_MINIAUDIO
    // ========================================================================
    // APPROACH 1: Miniaudio Resampler cleanup
    // ========================================================================
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    if (pPitch->temp_input_buffer) {
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
    }

#elif PITCH_APPROACH_SOUNDTOUCH_REALTIME
    // ========================================================================
    // APPROACH 2: SoundTouch Real-time cleanup
    // ========================================================================
    if (pPitch->soundtouch_initialized) {
        if (pPitch->soundtouch_processor) {
            delete pPitch->soundtouch_processor;
            pPitch->soundtouch_processor = NULL;
        }
        if (pPitch->temp_buffer) {
            free(pPitch->temp_buffer);
            pPitch->temp_buffer = NULL;
        }
        pPitch->soundtouch_initialized = 0;
        pPitch->temp_buffer_size = 0;
        pPitch->input_frames_pending = 0;
    }

#elif PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // ========================================================================
    // APPROACH 3: SoundTouch Preprocessing cleanup
    // ========================================================================
    if (pPitch->uses_preprocessed_data && pPitch->preprocessed_decoder) {
        ma_decoder_uninit(pPitch->preprocessed_decoder);
        free(pPitch->preprocessed_decoder);
        pPitch->preprocessed_decoder = NULL;
        pPitch->uses_preprocessed_data = 0;
    }
    
    // Clean up fallback resampler
    if (pPitch->resampler_initialized) {
        ma_resampler_uninit(&pPitch->resampler, NULL);
        pPitch->resampler_initialized = 0;
    }
    if (pPitch->temp_input_buffer) {
        free(pPitch->temp_input_buffer);
        pPitch->temp_input_buffer = NULL;
        pPitch->temp_input_buffer_size = 0;
    }
    
    pPitch->sample_slot = -1;
#endif
    
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
    
    // Create dual decoders from memory (one for sample bank, one for sequencer)
    ma_result ma_res_sample_bank = ma_decoder_init_memory(slot->memory_data, slot->memory_size, config, &slot->sample_bank_decoder);
    if (ma_res_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sample bank decoder from memory for slot %d: %s", 
                 slot_index, ma_result_description(ma_res_sample_bank));
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    
    ma_result ma_res_sequencer = ma_decoder_init_memory(slot->memory_data, slot->memory_size, config, &slot->sequencer_decoder);
    if (ma_res_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sequencer decoder from memory for slot %d: %s", 
                 slot_index, ma_result_description(ma_res_sequencer));
        ma_decoder_uninit(&slot->sample_bank_decoder);
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
    // Initialize pitch data sources for both sample bank and sequencer
    // -------------------------------------------------------------
    ma_result pitchRes_sample_bank = ma_pitch_data_source_init(&slot->sample_bank_pitch_ds, &slot->sample_bank_decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sample bank pitch data source for slot %d: %s", slot_index, ma_result_description(pitchRes_sample_bank));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    slot->sample_bank_pitch_ds_initialized = 1;
    
    ma_result pitchRes_sequencer = ma_pitch_data_source_init(&slot->sequencer_pitch_ds, &slot->sequencer_decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sequencer pitch data source for slot %d: %s", slot_index, ma_result_description(pitchRes_sequencer));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }
    slot->sequencer_pitch_ds_initialized = 1;
    
    // -------------------------------------------------------------
    // Create data source nodes for both systems
    // -------------------------------------------------------------
    ma_data_source_node_config nodeConfig_sample_bank = ma_data_source_node_config_init(&slot->sample_bank_pitch_ds);
    ma_result nodeRes_sample_bank = ma_data_source_node_init(&g_nodeGraph, &nodeConfig_sample_bank, NULL, &slot->sample_bank_node);
    if (nodeRes_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sample bank data source node for slot %d: %s", slot_index, ma_result_description(nodeRes_sample_bank));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_pitch_data_source_uninit(&slot->sequencer_pitch_ds);
        slot->sequencer_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }

    ma_data_source_node_config nodeConfig_sequencer = ma_data_source_node_config_init(&slot->sequencer_pitch_ds);
    ma_result nodeRes_sequencer = ma_data_source_node_init(&g_nodeGraph, &nodeConfig_sequencer, NULL, &slot->sequencer_node);
    if (nodeRes_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sequencer data source node for slot %d: %s", slot_index, ma_result_description(nodeRes_sequencer));
        // Roll back everything
        slot->loaded = 0;
        g_total_memory_used -= slot->memory_size;
        ma_data_source_node_uninit(&slot->sample_bank_node, NULL);
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_pitch_data_source_uninit(&slot->sequencer_pitch_ds);
        slot->sequencer_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        free(slot->memory_data);
        slot->memory_data = NULL;
        slot->memory_size = 0;
        return -1;
    }

    // Attach both nodes to the endpoint (both start muted)
    ma_node_attach_output_bus(&slot->sample_bank_node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&slot->sample_bank_node, 0, 0.0f);
    slot->sample_bank_node_initialized = 1;
    
    ma_node_attach_output_bus(&slot->sequencer_node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&slot->sequencer_node, 0, 0.0f);
    slot->sequencer_node_initialized = 1;
    
    prnt("✅ [MINIAUDIO] Slot %d loaded to memory (%.2f MB) [%d/%d memory slots, %.2f/%.2f MB total]", 
         slot_index, slot->memory_size / (1024.0 * 1024.0),
         get_current_memory_slot_count(), MAX_MEMORY_SLOTS,
         g_total_memory_used / (1024.0 * 1024.0), 
         MAX_TOTAL_MEMORY_USAGE / (1024.0 * 1024.0));
    
    return 0;
}

static int load_sound_from_file(audio_slot_t* slot, const char* file_path, ma_decoder_config* config, int slot_index) {
    // Initialize dual decoders from the same file
    ma_result ma_res_sample_bank = ma_decoder_init_file(file_path, config, &slot->sample_bank_decoder);
    if (ma_res_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sample bank decoder for slot %d: %s", 
                 slot_index, ma_result_description(ma_res_sample_bank));
        return -1;
    }
    
    ma_result ma_res_sequencer = ma_decoder_init_file(file_path, config, &slot->sequencer_decoder);
    if (ma_res_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sequencer decoder for slot %d: %s", 
                 slot_index, ma_result_description(ma_res_sequencer));
        ma_decoder_uninit(&slot->sample_bank_decoder);
        return -1;
    }
    
    slot->loaded = 1;
    
    // Initialize default pitch and volume
    slot->pitch = 1.0f;              // Default pitch (no change)
    slot->volume = 1.0f;             // Default volume (full)
    
    // Initialize dual pitch data source wrappers
    ma_result pitchRes_sample_bank = ma_pitch_data_source_init(&slot->sample_bank_pitch_ds, &slot->sample_bank_decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sample bank pitch data source for slot %d (streaming): %s", slot_index, ma_result_description(pitchRes_sample_bank));
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        slot->loaded = 0;
        return -1;
    }
    slot->sample_bank_pitch_ds_initialized = 1;
    
    ma_result pitchRes_sequencer = ma_pitch_data_source_init(&slot->sequencer_pitch_ds, &slot->sequencer_decoder, slot->pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (pitchRes_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to initialize sequencer pitch data source for slot %d (streaming): %s", slot_index, ma_result_description(pitchRes_sequencer));
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        slot->loaded = 0;
        return -1;
    }
    slot->sequencer_pitch_ds_initialized = 1;
    
    // Create and attach data source nodes to the graph (both muted initially)
    ma_data_source_node_config nodeConfig_sample_bank = ma_data_source_node_config_init(&slot->sample_bank_pitch_ds);
    ma_result nodeRes_sample_bank = ma_data_source_node_init(&g_nodeGraph, &nodeConfig_sample_bank, NULL, &slot->sample_bank_node);
    if (nodeRes_sample_bank != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sample bank data source node for slot %d (streaming): %s", slot_index, ma_result_description(nodeRes_sample_bank));
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_pitch_data_source_uninit(&slot->sequencer_pitch_ds);
        slot->sequencer_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        slot->loaded = 0;
        return -1;
    }
    
    ma_data_source_node_config nodeConfig_sequencer = ma_data_source_node_config_init(&slot->sequencer_pitch_ds);
    ma_result nodeRes_sequencer = ma_data_source_node_init(&g_nodeGraph, &nodeConfig_sequencer, NULL, &slot->sequencer_node);
    if (nodeRes_sequencer != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to create sequencer data source node for slot %d (streaming): %s", slot_index, ma_result_description(nodeRes_sequencer));
        ma_data_source_node_uninit(&slot->sample_bank_node, NULL);
        ma_pitch_data_source_uninit(&slot->sample_bank_pitch_ds);
        slot->sample_bank_pitch_ds_initialized = 0;
        ma_pitch_data_source_uninit(&slot->sequencer_pitch_ds);
        slot->sequencer_pitch_ds_initialized = 0;
        ma_decoder_uninit(&slot->sample_bank_decoder);
        ma_decoder_uninit(&slot->sequencer_decoder);
        slot->loaded = 0;
        return -1;
    }
    
    // Attach both nodes to the endpoint (both start muted)
    ma_node_attach_output_bus(&slot->sample_bank_node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&slot->sample_bank_node, 0, 0.0f);
    slot->sample_bank_node_initialized = 1;
    
    ma_node_attach_output_bus(&slot->sequencer_node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&slot->sequencer_node, 0, 0.0f);
    slot->sequencer_node_initialized = 1;
    
    prnt("✅ [MINIAUDIO] Slot %d loaded for streaming with sample bank + sequencer nodes", slot_index);
    return 0;
}


// Play all samples that should trigger on this step across all columns (NEW: Per-cell nodes)
// Silence all active cell nodes in a specific column (for column-based replacement)
// Sets volume to 0 but keeps nodes active for logging purposes
static void silence_cell_nodes_in_column(int column) {
    int silenced_count = 0;
    int total_active_in_column = 0;
    
    // First pass: count all active nodes in this column
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active && g_cell_nodes[i].column == column) {
            total_active_in_column++;
        }
    }
    
    if (total_active_in_column > 0) {
        prnt("🔇 [SILENCE] Column %d has %d active nodes to silence", column, total_active_in_column);
    }
    
    // Second pass: silence them (original behavior - just set volume to 0)
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        cell_node_t* cell = &g_cell_nodes[i];
        if (cell->active && cell->column == column && cell->node_initialized) {
            // Set volume to 0 to silence immediately without audio artifacts
            ma_node_set_output_bus_volume(&cell->node, 0, 0.0f);
            
            prnt("🔇 [SILENCE] Node #%d: [%d,%d] sample %d (ID: %llu) → volume=0 (still active)", 
                 i, cell->step, cell->column, cell->sample_slot, cell->id);
            silenced_count++;
        }
    }
    
    if (silenced_count > 0) {
        prnt("🔇 [SILENCE] Column %d: silenced %d/%d nodes (volume=0, kept active)", 
             column, silenced_count, total_active_in_column);
    }
}

static void play_samples_for_step(int step) {
    if (step < 0 || step >= g_sequencer_steps) return;
    
    // prnt("🎵 [SEQUENCER] Step: %d", step);
    
    // Process all columns - just volume control, no node creation/deletion
    for (int column = 0; column < g_columns; column++) {
        int sample_to_play = g_sequencer_grid[step][column];
        
        // Is there a sample in this grid cell?
        if (sample_to_play >= 0 && sample_to_play < MAX_SLOTS) {
            audio_slot_t* sample = &g_slots[sample_to_play];
            if (sample->loaded) {
                // Find the node we want to play
                cell_node_t* target_node = find_node_for_cell(step, column, sample_to_play);
                
                if (target_node) {
                    // Check if this is the same node as currently playing
                    bool is_same_node = (currently_playing_nodes_per_col[column] == target_node);
                    
                                        if (!is_same_node) {
                        // Fade out previous node, fade in new node
                        if (currently_playing_nodes_per_col[column]) {
                            set_target_volume(currently_playing_nodes_per_col[column], 0.0f);
                        }
                        
                        // Seek to beginning based on data source type
                        if (target_node->uses_audio_buffer && target_node->audio_buffer_initialized) {
                            ma_data_source_seek_to_pcm_frame(&target_node->audio_buffer, 0);
                        } else {
                            ma_decoder_seek_to_pcm_frame(&target_node->decoder, 0);
                        }
                        
                        // Use current resolved volume and pitch (sample bank or cell override)
                        float resolved_volume = resolve_cell_volume(step, column, sample_to_play);
                        float resolved_pitch = resolve_cell_pitch(step, column, sample_to_play);
                        update_cell_pitch(target_node, resolved_pitch);
                        set_target_volume(target_node, resolved_volume);
                        currently_playing_nodes_per_col[column] = target_node;
                        
                        prnt("▶️ [START] Node [%d,%d] sample %d (vol: %.2f, ID: %llu) - tracking in column", 
                             step, column, sample_to_play, resolved_volume, target_node->id);
                    } else {
                        // Same node - restart from beginning
                        if (target_node->uses_audio_buffer && target_node->audio_buffer_initialized) {
                            ma_data_source_seek_to_pcm_frame(&target_node->audio_buffer, 0);
                        } else {
                            ma_decoder_seek_to_pcm_frame(&target_node->decoder, 0);
                        }
                        
                        // Use current resolved volume and pitch (sample bank or cell override)
                        float resolved_volume = resolve_cell_volume(step, column, sample_to_play);
                        float resolved_pitch = resolve_cell_pitch(step, column, sample_to_play);
                        update_cell_pitch(target_node, resolved_pitch);
                        set_target_volume(target_node, resolved_volume);
                        
                        prnt("🔄 [RESTART] Node [%d,%d] sample %d (vol: %.2f, ID: %llu)", 
                             step, column, sample_to_play, resolved_volume, target_node->id);
                    }
                } else {
                    prnt("⚠️ [SEQUENCER] No existing node found for [%d,%d] sample %d - need to create via grid management", 
                         step, column, sample_to_play);
                    
                    // Debug: Show what nodes exist
                    int active_count = 0;
                    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
                        if (g_cell_nodes[i].active) {
                            active_count++;
                            if (active_count <= 3) { // Show first 3 active nodes
                                prnt("  🔍 [DEBUG] Active node #%d: [%d,%d] sample %d (ID: %llu)", 
                                     i, g_cell_nodes[i].step, g_cell_nodes[i].column, 
                                     g_cell_nodes[i].sample_slot, g_cell_nodes[i].id);
                            }
                        }
                    }
                    prnt("  🔍 [DEBUG] Total active nodes: %d", active_count);
                }
            }
        }
        // If grid cell is empty, keep previous node playing (don't silence)
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
                prnt("🔄 [SEQUENCER] Looping back to step 0 (cell nodes continue independently)");
                // With per-cell nodes, we don't need to track column state
                // Each cell node plays independently until completion
            }
            
            // Play samples for the new step
            play_samples_for_step(g_current_step);
        }
    }
}

// Audio performance tracking
static uint64_t g_callback_count = 0;
static uint64_t g_total_callback_time_us = 0;
static uint64_t g_max_callback_time_us = 0;
static uint64_t g_last_performance_log = 0;

// Performance testing mode for diagnostic purposes
static int g_perf_test_mode = 0; // 0=normal, 1=skip_soundtouch, 2=skip_monitor, 3=skip_smoothing

// Get time in microseconds (cross-platform)
static uint64_t get_time_microseconds(void) {
#ifdef __APPLE__
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000ULL;
#elif defined(__ANDROID__)
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000ULL;
#else
    // Fallback for other platforms
    return 0;
#endif
}



// Main audio callback - called by miniaudio every ~11ms to fill the audio buffer
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    TRACE_BEGIN("audio_callback");
    uint64_t callback_start = get_time_microseconds();
    uint64_t step_start, step_end;
    
    // Track individual step timings for detailed profiling
    uint64_t timing_1_sequencer = 0;
    uint64_t timing_2_volume = 0; 
    uint64_t timing_3_monitor = 0;
    uint64_t timing_4_mixing = 0;
    uint64_t timing_5_recording = 0;
    
    // 1. Update global frame counter for cell node lifecycle tracking
    g_current_frame += frameCount;
    
    // 2. Run the sequencer (timing + sample triggering)
    TRACE_BEGIN("sequencer");
    step_start = get_time_microseconds();
    run_sequencer(frameCount);
    step_end = get_time_microseconds();
    timing_1_sequencer = step_end - step_start;
    TRACE_END();
    
    // 3. Update volume smoothing to prevent clicks
    TRACE_BEGIN("volume_smoothing");
    step_start = get_time_microseconds();
    if (g_perf_test_mode != 3) {
        update_volume_smoothing();
    }
    step_end = get_time_microseconds();
    timing_2_volume = step_end - step_start;
    TRACE_END();
    
    // 4. Monitor cell nodes  
    TRACE_BEGIN("monitor_nodes");
    step_start = get_time_microseconds();
    if (g_perf_test_mode != 2) {
        monitor_cell_nodes();
    }
    step_end = get_time_microseconds();
    timing_3_monitor = step_end - step_start;
    TRACE_END();
    
    // 5. Mix all playing samples into the output buffer (includes all active cell nodes)
    TRACE_BEGIN("audio_mixing");
    step_start = get_time_microseconds();
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
    step_end = get_time_microseconds();
    timing_4_mixing = step_end - step_start;
    TRACE_END();

    // 6. If recording, save the mixed audio to file
    TRACE_BEGIN("recording");
    step_start = get_time_microseconds();
    if (g_is_output_recording) {
        ma_encoder_write_pcm_frames(&g_output_encoder, pOutput, frameCount, NULL);
        g_total_frames_written += frameCount;
    }
    step_end = get_time_microseconds();
    timing_5_recording = step_end - step_start;
    TRACE_END();

    // 7. Performance tracking and diagnostics
    uint64_t callback_end = get_time_microseconds();
    uint64_t callback_duration = callback_end - callback_start;
    
    g_callback_count++;
    g_total_callback_time_us += callback_duration;
    if (callback_duration > g_max_callback_time_us) {
        g_max_callback_time_us = callback_duration;
    }
    
    // Log performance every 5 seconds and when callback is slow
    uint64_t now = callback_end / 1000000; // Convert to seconds
    if (now > g_last_performance_log + 5 || callback_duration > 8000) { // 8ms = 73% of 11ms budget
        int active_nodes = count_active_cell_nodes();
        double avg_callback_time = (double)g_total_callback_time_us / g_callback_count;
        
        if (callback_duration > 8000) {
            prnt_err("⚠️ [PERF] SLOW CALLBACK: %llu μs (%.1f%% of 11ms budget), active nodes: %d", 
                     callback_duration, (callback_duration / 110.0), active_nodes);
            
            // Log detailed breakdown when callback is slow
            prnt_err("🔍 [PERF BREAKDOWN] seq:%lluμs vol:%lluμs mon:%lluμs mix:%lluμs rec:%lluμs", 
                     timing_1_sequencer, timing_2_volume, timing_3_monitor, 
                     timing_4_mixing, timing_5_recording);
            
            // Calculate percentages of slow operations
            if (timing_4_mixing > 2000) {
                prnt_err("🔴 [PERF] MIXING BOTTLENECK: %lluμs (%.1f%% of callback)", 
                         timing_4_mixing, (timing_4_mixing * 100.0) / callback_duration);
            }
            if (timing_1_sequencer > 1000) {
                prnt_err("🔴 [PERF] SEQUENCER BOTTLENECK: %lluμs (%.1f%% of callback)", 
                         timing_1_sequencer, (timing_1_sequencer * 100.0) / callback_duration);
            }
            if (timing_5_recording > 1000) {
                prnt_err("🔴 [PERF] RECORDING BOTTLENECK: %lluμs (%.1f%% of callback)", 
                         timing_5_recording, (timing_5_recording * 100.0) / callback_duration);
            }
        }
        
        // Export performance counters to systrace for visual analysis
        TRACE_INT("audio_callback_us", (int32_t)callback_duration);
        TRACE_INT("audio_mixing_us", (int32_t)timing_4_mixing);
        TRACE_INT("active_nodes", active_nodes);
        
        prnt("📊 [PERF] Callback stats: avg=%.1fμs, max=%lluμs, active_nodes=%d, callbacks=%llu", 
             avg_callback_time, g_max_callback_time_us, active_nodes, g_callback_count);
        
        g_last_performance_log = now;
        
        // Reset max after logging
        g_max_callback_time_us = 0;
    }

    (void)pInput;
    (void)pDevice;
    TRACE_END(); // Close audio_callback trace
}

static void free_slot_resources(int slot) {
    audio_slot_t* s = &g_slots[slot];

    // Clean up sample bank playback system
    if (s->sample_bank_node_initialized) {
        ma_data_source_node_uninit(&s->sample_bank_node, NULL);
        s->sample_bank_node_initialized = 0;
    }
    if (s->sample_bank_pitch_ds_initialized) {
        ma_pitch_data_source_uninit(&s->sample_bank_pitch_ds);
        s->sample_bank_pitch_ds_initialized = 0;
    }
    if (s->loaded) {
        ma_decoder_uninit(&s->sample_bank_decoder);
    }

    // Clean up sequencer playback system
    if (s->sequencer_node_initialized) {
        ma_data_source_node_uninit(&s->sequencer_node, NULL);
        s->sequencer_node_initialized = 0;
    }
    if (s->sequencer_pitch_ds_initialized) {
        ma_pitch_data_source_uninit(&s->sequencer_pitch_ds);
        s->sequencer_pitch_ds_initialized = 0;
    }
    if (s->loaded) {
        ma_decoder_uninit(&s->sequencer_decoder);
        s->loaded = 0;
    }

    // Clean up shared memory/file resources
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

    // Reset state flags
    s->sample_bank_active = 0;
    s->sample_bank_at_end = 0;
    s->sequencer_active = 0;
    s->sequencer_at_end = 0;
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
    
    // Initialize preview systems
    memset(&g_sample_preview, 0, sizeof(preview_system_t));
    memset(&g_cell_preview, 0, sizeof(preview_system_t));
    
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
                    g_sequencer_grid_volumes[step][col] = DEFAULT_CELL_VOLUME; // Default: use sample bank volume
        g_sequencer_grid_pitches[step][col] = DEFAULT_CELL_PITCH; // Default: use sample bank pitch
        }
    }
    
    // Initialize cell node pool
    memset(g_cell_nodes, 0, sizeof(g_cell_nodes));
    g_next_cell_node_id = 1;
    g_current_frame = 0;
    
    // Initialize column tracking
    memset(currently_playing_nodes_per_col, 0, sizeof(currently_playing_nodes_per_col));
    
#if PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // Initialize preprocessed pitch cache
    memset(g_preprocessed_cache, 0, sizeof(g_preprocessed_cache));
    g_preprocessed_access_counter = 0;
    g_total_preprocessed_memory = 0;
    prnt("✅ [PREPROCESS] Preprocessed pitch cache initialized");
#endif
    
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
        s->sample_bank_active = 0;
        s->sample_bank_at_end = 0;
        s->sequencer_active = 0;
        s->sequencer_at_end = 0;
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
    
    // Seek sample bank decoder to beginning for sample bank playback
    ma_result ma_res = ma_decoder_seek_to_pcm_frame(&s->sample_bank_decoder, 0);
    if (ma_res != MA_SUCCESS) {
        prnt_err("🔴 [MINIAUDIO] Failed to seek sample bank decoder for slot %d: %s", slot, ma_result_description(ma_res));
        return -1;
    }
    
    // Update pitch on sample bank pitch data source
    if (s->sample_bank_pitch_ds_initialized) {
#if PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
        // For preprocessing approach, check if we should preprocess this sample
        if (fabs(s->pitch - 1.0f) > 0.001f) {
            // Try to use preprocessing for manual sample playback too
            preprocessed_sample_t* preprocessed = find_preprocessed_sample(slot, s->pitch);
            if (!preprocessed) {
                prnt("⚡ [PREPROCESS] Auto-preprocessing sample %d at pitch %.3f for manual playback", slot, s->pitch);
                if (preprocess_sample_with_pitch(slot, s->pitch) == 0) {
                    preprocessed = find_preprocessed_sample(slot, s->pitch);
                }
            }
            if (preprocessed) {
                prnt("🎯 [SAMPLE BANK] Using preprocessed data for manual playback: slot %d, pitch %.3f", slot, s->pitch);
            } else {
                prnt("⚠️ [SAMPLE BANK] Preprocessing failed, using fallback for manual playback: slot %d, pitch %.3f", slot, s->pitch);
                ma_pitch_data_source_set_pitch(&s->sample_bank_pitch_ds, s->pitch);
            }
        } else {
            prnt("🎯 [SAMPLE BANK] Using original pitch for manual playback: slot %d, pitch %.3f", slot, s->pitch);
        }
#else
        ma_pitch_data_source_set_pitch(&s->sample_bank_pitch_ds, s->pitch);
#endif
    }
    
    // Success - start sample bank playback
    s->sample_bank_active = 1;
    s->sample_bank_at_end = 0;
    if (s->sample_bank_node_initialized) {
        ma_node_set_output_bus_volume(&s->sample_bank_node, 0, s->volume);
    }
    prnt("▶️ [SAMPLE BANK] Slot %d started sample bank playback (%s) at volume %.2f, pitch %.2f", 
         slot, s->memory_data ? "memory" : "file", s->volume, s->pitch);
    
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
    s->sample_bank_active = 0;
    if (s->sample_bank_node_initialized) {
        ma_node_set_output_bus_volume(&s->sample_bank_node, 0, 0.0f);
    }
    prnt("⏹️ [SAMPLE BANK] Slot %d sample bank playback stopped", slot);
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
    
    prnt("⏹️ [MINIAUDIO] Stopping all sounds (sample bank + sequencer + previews + cell nodes)");
    
    // Stop and cleanup all active cell nodes
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active) {
            cleanup_cell_node(&g_cell_nodes[i]);
        }
    }
    
    // Stop preview systems
    g_sample_preview.active = 0;
    if (g_sample_preview.node_initialized) {
        ma_node_set_output_bus_volume(&g_sample_preview.node, 0, 0.0f);
    }
    
    g_cell_preview.active = 0;
    if (g_cell_preview.node_initialized) {
        ma_node_set_output_bus_volume(&g_cell_preview.node, 0, 0.0f);
    }
    
    // Stop all sample slots
    for (int i = 0; i < MAX_SLOTS; ++i) {
        audio_slot_t* s = &g_slots[i];
        
        // Stop sample bank playback
        s->sample_bank_active = 0;
        if (s->sample_bank_node_initialized) {
            ma_node_set_output_bus_volume(&s->sample_bank_node, 0, 0.0f);
        }
        
        // Stop sequencer playback
        s->sequencer_active = 0;
        if (s->sequencer_node_initialized) {
            ma_node_set_output_bus_volume(&s->sequencer_node, 0, 0.0f);
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

// -----------------------------------------------------------------------------
// Preview System Functions
// -----------------------------------------------------------------------------

int preview_sample(const char* file_path, float pitch, float volume) {
    if (!g_is_initialized) {
        prnt_err("🔴 [PREVIEW] Device not initialized");
        return -1;
    }
    if (file_path == NULL || strlen(file_path) == 0) {
        prnt_err("🔴 [PREVIEW] Invalid file path");
        return -1;
    }
    
    // Stop any existing preview
    if (g_sample_preview.active) {
        ma_node_set_output_bus_volume(&g_sample_preview.node, 0, 0.0f);
        g_sample_preview.active = 0;
    }
    
    // Clean up existing resources
    if (g_sample_preview.node_initialized) {
        cleanup_preview_system(&g_sample_preview);
    }
    
    prnt("🔍 [PREVIEW] Starting sample preview: %s (pitch: %.2f, volume: %.2f)", file_path, pitch, volume);
    
    // Initialize decoder
    ma_decoder_config decoderConfig = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    ma_result result = ma_decoder_init_file(file_path, &decoderConfig, &g_sample_preview.decoder);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [PREVIEW] Failed to initialize decoder: %s", ma_result_description(result));
        return -1;
    }
    
    // Initialize pitch data source
    result = ma_pitch_data_source_init(&g_sample_preview.pitch_ds, &g_sample_preview.decoder, pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [PREVIEW] Failed to initialize pitch data source: %s", ma_result_description(result));
        ma_decoder_uninit(&g_sample_preview.decoder);
        return -1;
    }
    g_sample_preview.pitch_ds_initialized = 1;
    
    // Create and attach node
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&g_sample_preview.pitch_ds);
    result = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &g_sample_preview.node);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [PREVIEW] Failed to create data source node: %s", ma_result_description(result));
        ma_pitch_data_source_uninit(&g_sample_preview.pitch_ds);
        g_sample_preview.pitch_ds_initialized = 0;
        ma_decoder_uninit(&g_sample_preview.decoder);
        return -1;
    }
    
    // Attach to endpoint and start playing
    ma_node_attach_output_bus(&g_sample_preview.node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&g_sample_preview.node, 0, volume);
    g_sample_preview.node_initialized = 1;
    g_sample_preview.active = 1;
    g_sample_preview.file_path = strdup(file_path);
    
    prnt("✅ [PREVIEW] Sample preview started successfully");
    return 0;
}

int preview_cell(int step, int column, float pitch, float volume) {
    if (!g_is_initialized) {
        prnt_err("🔴 [CELL PREVIEW] Device not initialized");
        return -1;
    }
    if (step < 0 || step >= g_sequencer_steps || column < 0 || column >= g_columns) {
        prnt_err("🔴 [CELL PREVIEW] Invalid cell coordinates: step %d, column %d", step, column);
        return -1;
    }
    
    int sample_index = g_sequencer_grid[step][column];
    if (sample_index < 0 || sample_index >= MAX_SLOTS) {
        prnt_err("🔴 [CELL PREVIEW] No sample in cell [%d][%d]", step, column);
        return -1;
    }
    
    audio_slot_t* sample = &g_slots[sample_index];
    if (!sample->loaded) {
        prnt_err("🔴 [CELL PREVIEW] Sample %d not loaded", sample_index);
        return -1;
    }
    
    // Stop any existing preview
    if (g_cell_preview.active) {
        ma_node_set_output_bus_volume(&g_cell_preview.node, 0, 0.0f);
        g_cell_preview.active = 0;
    }
    
    // Clean up existing resources
    if (g_cell_preview.node_initialized) {
        cleanup_preview_system(&g_cell_preview);
    }
    
    prnt("🔍 [CELL PREVIEW] Previewing cell [%d][%d] sample %d (pitch: %.2f, volume: %.2f)", 
         step, column, sample_index, pitch, volume);
    
    // Initialize decoder from same source as the sample
    ma_decoder_config decoderConfig = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    ma_result result;
    
    if (sample->memory_data) {
        // Use memory data
        result = ma_decoder_init_memory(sample->memory_data, sample->memory_size, &decoderConfig, &g_cell_preview.decoder);
    } else {
        // Use file path
        result = ma_decoder_init_file(sample->file_path, &decoderConfig, &g_cell_preview.decoder);
    }
    
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [CELL PREVIEW] Failed to initialize decoder: %s", ma_result_description(result));
        return -1;
    }
    
    // Initialize pitch data source
    result = ma_pitch_data_source_init(&g_cell_preview.pitch_ds, &g_cell_preview.decoder, pitch, CHANNEL_COUNT, SAMPLE_RATE);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [CELL PREVIEW] Failed to initialize pitch data source: %s", ma_result_description(result));
        ma_decoder_uninit(&g_cell_preview.decoder);
        return -1;
    }
    g_cell_preview.pitch_ds_initialized = 1;
    
    // Create and attach node
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&g_cell_preview.pitch_ds);
    result = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &g_cell_preview.node);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [CELL PREVIEW] Failed to create data source node: %s", ma_result_description(result));
        ma_pitch_data_source_uninit(&g_cell_preview.pitch_ds);
        g_cell_preview.pitch_ds_initialized = 0;
        ma_decoder_uninit(&g_cell_preview.decoder);
        return -1;
    }
    
    // Attach to endpoint and start playing
    ma_node_attach_output_bus(&g_cell_preview.node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    ma_node_set_output_bus_volume(&g_cell_preview.node, 0, volume);
    g_cell_preview.node_initialized = 1;
    g_cell_preview.active = 1;
    
    prnt("✅ [CELL PREVIEW] Cell preview started successfully");
    return 0;
}

void stop_sample_preview(void) {
    if (g_sample_preview.active) {
        ma_node_set_output_bus_volume(&g_sample_preview.node, 0, 0.0f);
        g_sample_preview.active = 0;
        prnt("⏹️ [PREVIEW] Sample preview stopped");
    }
}

void stop_cell_preview(void) {
    if (g_cell_preview.active) {
        ma_node_set_output_bus_volume(&g_cell_preview.node, 0, 0.0f);
        g_cell_preview.active = 0;
        prnt("⏹️ [CELL PREVIEW] Cell preview stopped");
    }
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

// Diagnostic functions for monitoring performance
int get_active_cell_node_count(void) {
    return count_active_cell_nodes();
}

int get_max_cell_node_count(void) {
    return MAX_ACTIVE_CELL_NODES;
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
    
    // Stop and cleanup all active cell nodes to prevent background processing
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active) {
            cleanup_cell_node(&g_cell_nodes[i]);
        }
    }
    
    // Clear column tracking since nothing is currently playing
    memset(currently_playing_nodes_per_col, 0, sizeof(currently_playing_nodes_per_col));
    
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
    
    // If removing sample from cell (sample_slot = -1)
    if (sample_slot == -1) {
        // Find and cleanup existing node for this cell
        cell_node_t* existing_node = find_node_for_cell(step, column, g_sequencer_grid[step][column]);
        if (existing_node) {
            prnt("🗑️ [GRID] Removing node for cell [%d,%d] (ID: %llu)", step, column, existing_node->id);
            cleanup_cell_node(existing_node);
        }
        g_sequencer_grid[step][column] = -1;
        prnt("🗑️ [SEQUENCER] Cleared cell [%d,%d]", step, column);
        return;
    }
    
    // Adding/changing sample in cell
    audio_slot_t* sample = &g_slots[sample_slot];
    if (!sample->loaded) {
        prnt_err("🔴 [SEQUENCER] Sample %d not loaded", sample_slot);
        return;
    }
    
    // Remove existing node if there was a different sample in this cell
    int old_sample = g_sequencer_grid[step][column];
    if (old_sample >= 0 && old_sample != sample_slot) {
        cell_node_t* old_node = find_node_for_cell(step, column, old_sample);
        if (old_node) {
            prnt("🗑️ [GRID] Replacing node for cell [%d,%d] old sample %d (ID: %llu)", 
                 step, column, old_sample, old_node->id);
            cleanup_cell_node(old_node);
        }
        
        // Reset cell volume and pitch to defaults when sample changes
        g_sequencer_grid_volumes[step][column] = DEFAULT_CELL_VOLUME;
        g_sequencer_grid_pitches[step][column] = DEFAULT_CELL_PITCH;
        prnt("🔄 [GRID] Reset cell [%d,%d] volume/pitch to defaults for new sample %d", 
             step, column, sample_slot);
    }
    
    // Create new node for this cell (if it doesn't exist)
    cell_node_t* existing_node = find_node_for_cell(step, column, sample_slot);
    if (!existing_node) {
        // Use the resolution functions for consistent logic
        float final_volume = resolve_cell_volume(step, column, sample_slot);
        float final_pitch = resolve_cell_pitch(step, column, sample_slot);
        
        // Create node for this cell (starts silenced)
        cell_node_t* new_node = create_cell_node(step, column, sample_slot, final_volume, final_pitch);
        if (new_node) {
            // Start silenced - sequencer will control volume during playback
            ma_node_set_output_bus_volume(&new_node->node, 0, 0.0f);
            prnt("✅ [GRID] Created node for cell [%d,%d] sample %d (vol: %.2f, pitch: %.2f, ID: %llu)", 
                 step, column, sample_slot, final_volume, final_pitch, new_node->id);
        } else {
            prnt_err("🔴 [GRID] Failed to create node for cell [%d,%d] sample %d", step, column, sample_slot);
            return;
        }
    }
    
    g_sequencer_grid[step][column] = sample_slot;
    prnt("🎹 [SEQUENCER] Set cell [%d,%d] = %d", step, column, sample_slot);
}

void clear_cell(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) return;
    if (column < 0 || column >= MAX_TOTAL_COLUMNS) return;
    
    // Find and cleanup existing node for this cell
    int old_sample = g_sequencer_grid[step][column];
    if (old_sample >= 0) {
        cell_node_t* existing_node = find_node_for_cell(step, column, old_sample);
        if (existing_node) {
            prnt("🗑️ [GRID] Removing node for cell [%d,%d] (ID: %llu)", step, column, existing_node->id);
            cleanup_cell_node(existing_node);
        }
        
        // Reset cell volume and pitch overrides when clearing cell
        g_sequencer_grid_volumes[step][column] = DEFAULT_CELL_VOLUME;
        g_sequencer_grid_pitches[step][column] = DEFAULT_CELL_PITCH;
        prnt("🔄 [GRID] Reset cell [%d,%d] volume/pitch overrides when clearing", step, column);
    }
    
    g_sequencer_grid[step][column] = -1;
    prnt("🗑️ [SEQUENCER] Cleared cell [%d,%d]", step, column);
}

void clear_all_cells(void) {
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
            g_sequencer_grid[step][col] = -1;
                g_sequencer_grid_volumes[step][col] = DEFAULT_CELL_VOLUME; // Reset to use sample bank volume
    g_sequencer_grid_pitches[step][col] = DEFAULT_CELL_PITCH; // Reset to use sample bank pitch
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
    
    // Update existing nodes that use this sample bank (if they don't have cell overrides)
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
            if (g_sequencer_grid[step][col] == bank) {
                // Only update if this cell doesn't have a volume override
                if (g_sequencer_grid_volumes[step][col] == DEFAULT_CELL_VOLUME) {
                    update_existing_nodes_for_cell(step, col, bank);
                }
            }
        }
    }
    
    prnt("🔊 [VOLUME] Sample bank %d volume set to %.2f", bank, volume);
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
    
    // Update existing node for this cell if it exists
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        update_existing_nodes_for_cell(step, column, sample_in_cell);
    }
    
    prnt("🔊 [VOLUME] Cell [%d,%d] volume set to %.2f", step, column, volume);
    return 0;
}

int reset_cell_volume(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [VOLUME] Invalid step: %d", step);
        return -1;
    }

    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [VOLUME] Invalid column: %d", column);
        return -1;
    }

    g_sequencer_grid_volumes[step][column] = DEFAULT_CELL_VOLUME;

    // Update existing node for this cell if it exists
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        update_existing_nodes_for_cell(step, column, sample_in_cell);
    }

    prnt("🔊 [VOLUME] Cell [%d,%d] volume reset to use sample bank default", step, column);
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
    
    return g_sequencer_grid_volumes[step][column];
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
    
    // Update existing nodes that use this sample bank (if they don't have cell overrides)
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_TOTAL_COLUMNS; col++) {
            if (g_sequencer_grid[step][col] == bank) {
                // Only update if this cell doesn't have a pitch override
                if (g_sequencer_grid_pitches[step][col] == DEFAULT_CELL_PITCH) {
                    update_existing_nodes_for_cell(step, col, bank);
                }
            }
        }
    }
    
    prnt("🎵 [PITCH] Sample bank %d pitch set to %.2f", bank, pitch);
    return 0;
}

float get_sample_bank_pitch(int bank) {
    if (bank < 0 || bank >= MAX_SLOTS) {
        prnt_err("🔴 [PITCH] Invalid sample bank: %d", bank);
        return 1.0f;
    }
    
    return g_slots[bank].pitch;
}

int set_cell_pitch(int step, int column, float pitch_ratio) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [PITCH] Invalid step: %d", step);
        return -1;
    }

    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [PITCH] Invalid column: %d", column);
        return -1;
    }

    if (pitch_ratio < 0.03125f || pitch_ratio > 32.0f) {
        prnt_err("🔴 [PITCH] Invalid pitch: %f (must be 0.03125-32.0 for C0-C10)", pitch_ratio);
        return -1;
    }

    g_sequencer_grid_pitches[step][column] = pitch_ratio;

    // Update existing node for this cell if it exists
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        update_existing_nodes_for_cell(step, column, sample_in_cell);
    }

    prnt("🎵 [PITCH] Cell [%d,%d] pitch set to %.3f", step, column, pitch_ratio);
    return 0;
}

int reset_cell_pitch(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [PITCH] Invalid step: %d", step);
        return -1;
    }

    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [PITCH] Invalid column: %d", column);
        return -1;
    }

    g_sequencer_grid_pitches[step][column] = DEFAULT_CELL_PITCH;

    // Update existing node for this cell if it exists
    int sample_in_cell = g_sequencer_grid[step][column];
    if (sample_in_cell >= 0) {
        update_existing_nodes_for_cell(step, column, sample_in_cell);
    }

    prnt("🎵 [PITCH] Cell [%d,%d] pitch reset to use sample bank default", step, column);
    return 0;
}

float get_cell_pitch(int step, int column) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [PITCH] Invalid step: %d", step);
        return 1.0f; // Return default pitch ratio
    }

    if (column < 0 || column >= MAX_TOTAL_COLUMNS) {
        prnt_err("🔴 [PITCH] Invalid column: %d", column);
        return 1.0f; // Return default pitch ratio
    }

    float pitch_ratio = g_sequencer_grid_pitches[step][column];
    
    // If it's the default value, return 1.0 (original pitch)
    if (pitch_ratio == DEFAULT_CELL_PITCH) {
        return 1.0f; 
    }
    
    return pitch_ratio;
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
    
    // Clean up preview systems
    if (g_sample_preview.node_initialized) {
        cleanup_preview_system(&g_sample_preview);
        prnt("🗑️ [PREVIEW] Sample preview system cleaned up");
    }
    
    if (g_cell_preview.node_initialized) {
        cleanup_preview_system(&g_cell_preview);
        prnt("🗑️ [PREVIEW] Cell preview system cleaned up");
    }
    
#if PITCH_APPROACH_SOUNDTOUCH_PREPROCESSING
    // Clean up preprocessed pitch cache
    cleanup_preprocessed_cache();
#endif
    
    // Uninitialize device
    ma_device_uninit(&g_device);
    
    // Uninitialize the node graph (after all nodes have been freed)
    ma_node_graph_uninit(&g_nodeGraph, NULL);
    
    g_total_memory_used = 0;
    g_is_initialized = 0;
    prnt("✅ [MINIAUDIO] Cleanup completed successfully");
}

// -----------------------------------------------------------------------------
// Preprocessed Pitch System Implementation
// -----------------------------------------------------------------------------

// Find cached preprocessed sample
static preprocessed_sample_t* find_preprocessed_sample(int source_slot, float pitch_ratio) {
    uint32_t pitch_hash = hash_pitch_ratio(pitch_ratio);
    
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        preprocessed_sample_t* entry = &g_preprocessed_cache[i];
        if (entry->in_use && 
            entry->source_slot == source_slot && 
            entry->pitch_hash == pitch_hash) {
            // Update access time for LRU
            entry->last_accessed = ++g_preprocessed_access_counter;
            prnt("✅ [PREPROCESS] Found cached sample: slot %d, pitch %.3f", source_slot, pitch_ratio);
            return entry;
        }
    }
    return NULL; // Not found
}

// Evict oldest preprocessed sample to make space
static void evict_oldest_preprocessed_sample(void) {
    int oldest_index = -1;
    uint64_t oldest_time = UINT64_MAX;
    
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (g_preprocessed_cache[i].in_use && 
            g_preprocessed_cache[i].last_accessed < oldest_time) {
            oldest_time = g_preprocessed_cache[i].last_accessed;
            oldest_index = i;
        }
    }
    
    if (oldest_index >= 0) {
        preprocessed_sample_t* entry = &g_preprocessed_cache[oldest_index];
        prnt("🗑️ [PREPROCESS] Evicting old sample: slot %d, pitch %.3f (%.2f MB)", 
             entry->source_slot, entry->pitch_ratio, entry->processed_size / (1024.0 * 1024.0));
        
        if (entry->processed_data) {
            g_total_preprocessed_memory -= entry->processed_size;
            free(entry->processed_data);
        }
        memset(entry, 0, sizeof(preprocessed_sample_t));
    }
}

// Process entire sample with SoundTouch and store result
static int preprocess_sample_with_pitch(int source_slot, float pitch_ratio) {
    if (source_slot < 0 || source_slot >= MAX_SLOTS) {
        prnt_err("🔴 [PREPROCESS] Invalid source slot: %d", source_slot);
        return -1;
    }
    
    audio_slot_t* source = &g_slots[source_slot];
    if (!source->loaded) {
        prnt_err("🔴 [PREPROCESS] Source slot %d not loaded", source_slot);
        return -1;
    }
    
    // Skip preprocessing for normal pitch (1.0)
    if (fabs(pitch_ratio - 1.0f) < 0.001f) {
        prnt("⚠️ [PREPROCESS] Skipping preprocessing for normal pitch %.3f", pitch_ratio);
        return 0; // Don't cache normal pitch samples
    }
    
    prnt("🔄 [PREPROCESS] Processing slot %d with pitch %.3f...", source_slot, pitch_ratio);
    
    // Find empty cache slot or evict oldest
    int cache_index = -1;
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (!g_preprocessed_cache[i].in_use) {
            cache_index = i;
            break;
        }
    }
    
    if (cache_index == -1) {
        evict_oldest_preprocessed_sample();
        // Try again to find empty slot
        for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
            if (!g_preprocessed_cache[i].in_use) {
                cache_index = i;
                break;
            }
        }
    }
    
    if (cache_index == -1) {
        prnt_err("🔴 [PREPROCESS] No cache slots available");
        return -1;
    }
    
    // Create temporary decoder for processing
    ma_decoder temp_decoder;
    ma_decoder_config config = ma_decoder_config_init(SAMPLE_FORMAT, CHANNEL_COUNT, SAMPLE_RATE);
    ma_result result;
    
    if (source->memory_data) {
        result = ma_decoder_init_memory(source->memory_data, source->memory_size, &config, &temp_decoder);
    } else {
        result = ma_decoder_init_file(source->file_path, &config, &temp_decoder);
    }
    
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [PREPROCESS] Failed to create temp decoder: %s", ma_result_description(result));
        return -1;
    }
    
    // Get sample length
    ma_uint64 total_frames;
    result = ma_decoder_get_length_in_pcm_frames(&temp_decoder, &total_frames);
    if (result != MA_SUCCESS) {
        prnt_err("🔴 [PREPROCESS] Failed to get sample length: %s", ma_result_description(result));
        ma_decoder_uninit(&temp_decoder);
        return -1;
    }
    
    prnt("📏 [PREPROCESS] Sample length: %llu frames (%.2f seconds)", 
         total_frames, (double)total_frames / SAMPLE_RATE);
    
    // Create SoundTouch processor for offline processing
    SoundTouch processor;
    processor.setSampleRate(SAMPLE_RATE);
    processor.setChannels(CHANNEL_COUNT);
    processor.setPitch(pitch_ratio);
    
    // Use high-quality settings for offline processing (we have time)
    processor.setSetting(SETTING_USE_QUICKSEEK, 0);        // Use high quality
    processor.setSetting(SETTING_USE_AA_FILTER, 1);        // Enable anti-aliasing
    processor.setSetting(SETTING_SEQUENCE_MS, 40);         // Longer sequences for quality
    processor.setSetting(SETTING_SEEKWINDOW_MS, 15);       // Larger search window
    processor.setSetting(SETTING_OVERLAP_MS, 8);           // More overlap for quality
    
    // Allocate output buffer (estimate 1.5x input size for worst case)
    ma_uint64 estimated_output_frames = total_frames + (total_frames / 2);
    size_t output_buffer_size = estimated_output_frames * CHANNEL_COUNT * sizeof(float);
    float* output_buffer = (float*)malloc(output_buffer_size);
    
    if (!output_buffer) {
        prnt_err("🔴 [PREPROCESS] Failed to allocate output buffer (%.2f MB)", 
                 output_buffer_size / (1024.0 * 1024.0));
        ma_decoder_uninit(&temp_decoder);
        return -1;
    }
    
    // Process in chunks
    const ma_uint64 chunk_size = 4096;
    float chunk_buffer[chunk_size * CHANNEL_COUNT];
    ma_uint64 total_output_frames = 0;
    ma_uint64 frames_read;
    
    // Feed all input to SoundTouch
    ma_decoder_seek_to_pcm_frame(&temp_decoder, 0);
    while (total_output_frames < estimated_output_frames) {
        result = ma_decoder_read_pcm_frames(&temp_decoder, chunk_buffer, chunk_size, &frames_read);
        if (result != MA_SUCCESS || frames_read == 0) break;
        
        // Feed to SoundTouch
        processor.putSamples(chunk_buffer, (uint)frames_read);
        
        // Get processed samples
        uint samples_available = processor.numSamples();
        if (samples_available > 0) {
            uint max_receive = (uint)(estimated_output_frames - total_output_frames);
            if (max_receive > samples_available) max_receive = samples_available;
            
            uint received = processor.receiveSamples(
                output_buffer + (total_output_frames * CHANNEL_COUNT), 
                max_receive
            );
            total_output_frames += received;
        }
    }
    
    // Flush remaining samples
    processor.flush();
    uint samples_available = processor.numSamples();
    if (samples_available > 0 && total_output_frames < estimated_output_frames) {
        uint max_receive = (uint)(estimated_output_frames - total_output_frames);
        if (max_receive > samples_available) max_receive = samples_available;
        
        uint received = processor.receiveSamples(
            output_buffer + (total_output_frames * CHANNEL_COUNT), 
            max_receive
        );
        total_output_frames += received;
    }
    
    ma_decoder_uninit(&temp_decoder);
    
    if (total_output_frames == 0) {
        prnt_err("🔴 [PREPROCESS] No output frames generated");
        free(output_buffer);
        return -1;
    }
    
    // Store in cache
    preprocessed_sample_t* entry = &g_preprocessed_cache[cache_index];
    entry->source_slot = source_slot;
    entry->pitch_ratio = pitch_ratio;
    entry->pitch_hash = hash_pitch_ratio(pitch_ratio);
    entry->processed_data = output_buffer;
    entry->processed_size = total_output_frames * CHANNEL_COUNT * sizeof(float);
    entry->processed_frames = total_output_frames;
    entry->in_use = 1;
    entry->last_accessed = ++g_preprocessed_access_counter;
    entry->creation_time = g_preprocessed_access_counter;
    
    g_total_preprocessed_memory += entry->processed_size;
    
    prnt("✅ [PREPROCESS] Processed slot %d with pitch %.3f: %llu frames → %llu frames (%.2f MB cached)", 
         source_slot, pitch_ratio, total_frames, total_output_frames, 
         entry->processed_size / (1024.0 * 1024.0));
    
    return 0;
}

// Cleanup all preprocessed samples
static void cleanup_preprocessed_cache(void) {
    prnt("🧹 [PREPROCESS] Cleaning up cache...");
    
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (g_preprocessed_cache[i].in_use && g_preprocessed_cache[i].processed_data) {
            free(g_preprocessed_cache[i].processed_data);
        }
    }
    
    memset(g_preprocessed_cache, 0, sizeof(g_preprocessed_cache));
    g_total_preprocessed_memory = 0;
    g_preprocessed_access_counter = 0;
    
    prnt("✅ [PREPROCESS] Cache cleaned up");
}

// Preprocessed pitch system API
int preprocess_sample_pitch(int source_slot, float pitch_ratio) {
    if (!g_is_initialized) {
        prnt_err("🔴 [PREPROCESS] Device not initialized");
        return -1;
    }
    
    // Check if already cached
    preprocessed_sample_t* existing = find_preprocessed_sample(source_slot, pitch_ratio);
    if (existing) {
        prnt("ℹ️ [PREPROCESS] Sample already cached: slot %d, pitch %.3f", source_slot, pitch_ratio);
        return 0; // Already processed
    }
    
    return preprocess_sample_with_pitch(source_slot, pitch_ratio);
}

uint64_t get_preprocessed_memory_usage(void) {
    return g_total_preprocessed_memory;
}

int get_preprocessed_cache_count(void) {
    int count = 0;
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (g_preprocessed_cache[i].in_use) count++;
    }
    return count;
}

void clear_preprocessed_cache(void) {
    cleanup_preprocessed_cache();
    prnt("🗑️ [PREPROCESS] Cache cleared manually");
}

// -----------------------------------------------------------------------------
// Performance Diagnostic Function (for testing bottlenecks)
// -----------------------------------------------------------------------------
void set_performance_test_mode(int mode) {
    g_perf_test_mode = mode;
    switch(mode) {
        case 0: prnt("🧪 [PERF TEST] Normal mode (all operations enabled)"); break;
        case 1: prnt("🧪 [PERF TEST] Skip SoundTouch processing"); break;
        case 2: prnt("🧪 [PERF TEST] Skip cell monitoring"); break;
        case 3: prnt("🧪 [PERF TEST] Skip volume smoothing"); break;
        default: prnt("🧪 [PERF TEST] Unknown mode %d", mode); break;
    }
}

// Export for FFI
extern "C" {
    void set_perf_test_mode(int mode) {
        set_performance_test_mode(mode);
    }
}