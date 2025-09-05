#include "playback.h"
#include "table.h"
#include "sample_bank.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Platform-specific includes and logging
#ifdef __APPLE__
    #include "log.h"
    // iOS Audio Session for Bluetooth routing
    #import <AVFoundation/AVFoundation.h>
    
    // Configure miniaudio implementation for iOS (CoreAudio only)
    #define MA_NO_AVFOUNDATION          // CRITICAL: Prevent miniaudio from setting DefaultToSpeaker
    #define MA_NO_RUNTIME_LINKING       
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_COREAUDIO         
    #define MA_ENABLE_NULL              
    
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
    
#elif defined(__ANDROID__)
    #include "log.h"
    
    // Configure miniaudio for Android
    #define MA_NO_RUNTIME_LINKING
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_AAUDIO           
    #define MA_ENABLE_OPENSL           
    #define MA_ENABLE_NULL             
    
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
    
#else
    // Other platforms
    #define MA_NO_RUNTIME_LINKING
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
#endif

// Include miniaudio headers only. Implementation is compiled in miniaudio_impl.mm
#include "miniaudio/miniaudio.h"

// Utility macros
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

// Global playback state
static ma_device g_device;
static ma_node_graph g_nodeGraph;
static int g_initialized = 0;

// Column nodes (A/B switching per column)
static ColumnNodes g_column_nodes[MAX_SEQUENCER_COLS];

// Playback state
static int g_sequencer_playing = 0;
static int g_sequencer_bpm = 120;
static int g_current_step = 0;
static uint64_t g_frames_per_step = 0;
static uint64_t g_step_frame_counter = 0;

// Playback region and mode
static PlaybackRegion g_playback_region = {0, 16};
static int g_song_mode = 0;  // 0=loop, 1=song

// Read-only snapshot exposed to Flutter
static PublicPlaybackState g_public_playback_state;

static inline void public_state_write_begin() {
    g_public_playback_state.version++; // odd = write in progress
}

static inline void public_state_write_end() {
    g_public_playback_state.version++; // even = stable
}

static inline void public_state_update() {
    g_public_playback_state.is_playing = g_sequencer_playing;
    g_public_playback_state.current_step = g_current_step;
    g_public_playback_state.bpm = g_sequencer_bpm;
    g_public_playback_state.region_start = g_playback_region.start;
    g_public_playback_state.region_end = g_playback_region.end;
    g_public_playback_state.song_mode = g_song_mode;
}

// Forward declarations
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);
static void run_sequencer(ma_uint32 frameCount);
static void play_samples_for_step(int step);
static void setup_column_node(int column, int node_index, int sample_slot, float volume, float pitch);
static void update_volume_smoothing(void);
static float calculate_smoothing_alpha(float time_ms);
static float apply_exponential_smoothing(float current, float target, float alpha);

// Initialize playback system
int playback_init(void) {
    if (g_initialized) {
        prnt("⚠️ [PLAYBACK] Already initialized");
        return 0;
    }
    
    prnt("🎵 [PLAYBACK] Initializing playback system");
    
    // Initialize sample bank
    sample_bank_init();
    
    // Initialize column nodes
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        g_column_nodes[col].active_node = -1;  // No active node
        g_column_nodes[col].next_node = 0;     // Start with node A
        
        for (int i = 0; i < 2; i++) {
            ColumnNode* node = &g_column_nodes[col].nodes[i];
            node->column = col;
            node->index = i;
            node->node_initialized = 0;
            node->sample_slot = -1;
            node->decoder = NULL;
            node->node = NULL;
            node->user_volume = 1.0f;
            node->current_volume = 0.0f;
            node->target_volume = 0.0f;
            node->volume_rise_coeff = calculate_smoothing_alpha(VOLUME_RISE_TIME_MS);
            node->volume_fall_coeff = calculate_smoothing_alpha(VOLUME_FALL_TIME_MS);
            node->id = 0;
        }
    }
    
    // Initialize miniaudio node graph
    ma_node_graph_config nodeGraphConfig = ma_node_graph_config_init(CHANNELS);
    ma_result result = ma_node_graph_init(&nodeGraphConfig, NULL, &g_nodeGraph);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize node graph: %d", result);
        return -1;
    }
    
    // Initialize audio device
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = ma_format_f32;
    deviceConfig.playback.channels = CHANNELS;
    deviceConfig.sampleRate = SAMPLE_RATE;
    deviceConfig.dataCallback = audio_callback;
    deviceConfig.pUserData = NULL;
    
    result = ma_device_init(NULL, &deviceConfig, &g_device);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize device: %d", result);
        ma_node_graph_uninit(&g_nodeGraph, NULL);
        return -1;
    }
    
    // Start the device
    result = ma_device_start(&g_device);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to start device: %d", result);
        ma_device_uninit(&g_device);
        ma_node_graph_uninit(&g_nodeGraph, NULL);
        return -1;
    }
    
    // Calculate initial frames per step
    g_frames_per_step = (SAMPLE_RATE * 60) / (g_sequencer_bpm * 4); // 1/16 note frames
    
    // Initialize exposed playback state snapshot
    g_public_playback_state.version = 0;
    public_state_write_begin();
    public_state_update();
    public_state_write_end();

    g_initialized = 1;
    prnt("✅ [PLAYBACK] Playback system initialized (BPM: %d, frames/step: %llu)", 
         g_sequencer_bpm, g_frames_per_step);
    
    return 0;
}

// Cleanup playback system
void playback_cleanup(void) {
    if (!g_initialized) return;
    
    prnt("🧹 [PLAYBACK] Cleaning up playback system");
    
    // Stop playback
    playback_stop();
    
    // Cleanup sample bank
    sample_bank_cleanup();
    
    // Cleanup column nodes
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        for (int i = 0; i < 2; i++) {
            ColumnNode* node = &g_column_nodes[col].nodes[i];
            if (node->node_initialized) {
                if (node->node) {
                    ma_node_uninit((ma_node_base*)node->node, NULL);
                    free(node->node);
                    node->node = NULL;
                }
                if (node->decoder) {
                    ma_decoder_uninit((ma_decoder*)node->decoder);
                    free(node->decoder);
                    node->decoder = NULL;
                }
                node->node_initialized = 0;
            }
        }
    }
    
    // Stop and cleanup device
    ma_device_stop(&g_device);
    ma_device_uninit(&g_device);
    ma_node_graph_uninit(&g_nodeGraph, NULL);
    
    g_initialized = 0;
    // Mark as not playing in snapshot
    public_state_write_begin();
    g_sequencer_playing = 0;
    public_state_update();
    public_state_write_end();
    prnt("✅ [PLAYBACK] Cleanup complete");
}

// Start sequencer playback
int playback_start(int bpm, int start_step) {
    if (!g_initialized) {
        prnt_err("❌ [PLAYBACK] Not initialized");
        return -1;
    }
    
    if (bpm > 0 && bpm <= 300) {
        g_sequencer_bpm = bpm;
        g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
    }
    
    g_current_step = start_step;
    g_step_frame_counter = 0;
    g_sequencer_playing = 1;
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
    
    prnt("▶️ [PLAYBACK] Started sequencer (BPM: %d, start step: %d)", bpm, start_step);
    return 0;
}

// Stop sequencer playback
void playback_stop(void) {
    g_sequencer_playing = 0;
    g_step_frame_counter = 0;
    
    // Stop all column nodes
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        for (int i = 0; i < 2; i++) {
            ColumnNode* node = &g_column_nodes[col].nodes[i];
            if (node->node_initialized && node->node) {
                ma_node_set_state((ma_node_base*)node->node, ma_node_state_stopped);
                node->target_volume = 0.0f;
            }
        }
    }
    
    prnt("⏹️ [PLAYBACK] Stopped sequencer");
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
}

// Check if sequencer is playing
int playback_is_playing(void) {
    return g_sequencer_playing;
}

// Set BPM
void playback_set_bpm(int bpm) {
    if (bpm > 0 && bpm <= 300) {
        g_sequencer_bpm = bpm;
        g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
        prnt("🎵 [PLAYBACK] BPM changed to %d (%llu frames per step)", bpm, g_frames_per_step);
        public_state_write_begin();
        public_state_update();
        public_state_write_end();
    } else {
        prnt_err("❌ [PLAYBACK] Invalid BPM: %d", bpm);
    }
}

// Get current BPM
int playback_get_bpm(void) {
    return g_sequencer_bpm;
}

// Set playback region
void playback_set_region(int start, int end) {
    g_playback_region.start = start;
    g_playback_region.end = end;
    prnt("🎭 [PLAYBACK] Set playback region: %d to %d", start, end);
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
}

// Set playback mode (song/loop)
void playback_set_mode(int song_mode) {
    g_song_mode = song_mode;
    
    if (song_mode) {
        // Song mode: play all sections (calculate total from all sections)
        int total_steps = 0;
        int sections_count = table_get_sections_count();
        for (int i = 0; i < sections_count; i++) {
            total_steps += table_get_section_step_count(i);
        }
        playback_set_region(0, total_steps);
    } else {
        // Loop mode: use section 0 for now (can be made configurable)
        int section_start = table_get_section_start_step(0);
        int section_steps = table_get_section_step_count(0);
        playback_set_region(section_start, section_start + section_steps);
    }
    
    prnt("🎵 [PLAYBACK] Set mode to %s", song_mode ? "song" : "loop");
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
}

// Get current step
int playback_get_current_step(void) {
    return g_current_step;
}

// Calculate smoothing alpha coefficient
static float calculate_smoothing_alpha(float time_ms) {
    float callback_dt = 512.0f / SAMPLE_RATE;  // ~10.7ms at 48kHz
    float time_sec = time_ms / 1000.0f;
    return 1.0f - expf(-callback_dt / time_sec);
}

// Apply exponential smoothing step
static float apply_exponential_smoothing(float current, float target, float alpha) {
    return current + alpha * (target - current);
}

// Update volume smoothing for all nodes
static void update_volume_smoothing(void) {
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        for (int i = 0; i < 2; i++) {
            ColumnNode* node = &g_column_nodes[col].nodes[i];
            if (!node->node_initialized || !node->node) continue;
            
            // Choose appropriate smoothing coefficient
            float alpha = (node->current_volume < node->target_volume) ? 
                         node->volume_rise_coeff : node->volume_fall_coeff;
            
            // Apply smoothing
            node->current_volume = apply_exponential_smoothing(
                node->current_volume, node->target_volume, alpha);
            
            // Set volume on miniaudio node
            ma_node_set_output_bus_volume((ma_node_base*)node->node, 0, node->current_volume);
            
            // Stop node if volume is very low
            if (node->target_volume <= VOLUME_THRESHOLD && 
                node->current_volume <= VOLUME_THRESHOLD) {
                ma_node_set_state((ma_node_base*)node->node, ma_node_state_stopped);
            }
        }
    }
}

// Setup column node with sample
static void setup_column_node(int column, int node_index, int sample_slot, float volume, float pitch) {
    if (column < 0 || column >= MAX_SEQUENCER_COLS || node_index < 0 || node_index > 1) {
        return;
    }
    
    ColumnNode* node = &g_column_nodes[column].nodes[node_index];
    
    // Skip if already playing this sample
    if (node->sample_slot == sample_slot && node->node_initialized) {
        return;
    }
    
    // Cleanup previous node if needed
    if (node->node_initialized) {
        if (node->node) {
            ma_node_uninit((ma_node_base*)node->node, NULL);
            free(node->node);
            node->node = NULL;
        }
        if (node->decoder) {
            ma_decoder_uninit((ma_decoder*)node->decoder);
            free(node->decoder);
            node->decoder = NULL;
        }
        node->node_initialized = 0;
    }
    
    // Check if sample is loaded
    if (!sample_bank_is_loaded(sample_slot)) {
        prnt_err("❌ [PLAYBACK] Sample slot %d not loaded", sample_slot);
        return;
    }
    
    // Get decoder from sample bank  
    struct ma_decoder* sample_decoder = sample_bank_get_decoder(sample_slot);
    if (!sample_decoder) {
        prnt_err("❌ [PLAYBACK] No decoder for sample slot %d", sample_slot);
        return;
    }
    
    // Allocate a new decoder for this node (each node needs its own playback position)
    node->decoder = malloc(sizeof(ma_decoder));
    if (!node->decoder) {
        prnt_err("❌ [PLAYBACK] Failed to allocate decoder");
        return;
    }
    
    // Initialize decoder with the same file as the sample bank
    const char* file_path = sample_bank_get_file_path(sample_slot);
    ma_decoder_config decoderConfig = ma_decoder_config_init(ma_format_f32, CHANNELS, SAMPLE_RATE);
    ma_result result = ma_decoder_init_file(file_path, &decoderConfig, (ma_decoder*)node->decoder);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize decoder for %s: %d", file_path, result);
        free(node->decoder);
        node->decoder = NULL;
        return;
    }
    
    // Allocate data source node
    node->node = malloc(sizeof(ma_data_source_node));
    if (!node->node) {
        prnt_err("❌ [PLAYBACK] Failed to allocate data source node");
        ma_decoder_uninit((ma_decoder*)node->decoder);
        free(node->decoder);
        node->decoder = NULL;
        return;
    }
    
    // Initialize data source node
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init((ma_data_source*)node->decoder);
    result = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, (ma_data_source_node*)node->node);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize data source node: %d", result);
        ma_decoder_uninit((ma_decoder*)node->decoder);
        free(node->decoder);
        free(node->node);
        node->decoder = NULL;
        node->node = NULL;
        return;
    }
    
    // Attach to endpoint
    ma_node_attach_output_bus((ma_node_base*)node->node, 0, 
                              ma_node_graph_get_endpoint(&g_nodeGraph), 0);
    
    // Setup volume and state
    node->sample_slot = sample_slot;
    node->user_volume = volume;
    node->current_volume = 0.0f;  // Start silent
    node->target_volume = volume; // Fade to target
    node->node_initialized = 1;
    
    // Start playing
    ma_node_set_state((ma_node_base*)node->node, ma_node_state_started);
    
    prnt("🎵 [PLAYBACK] Setup node [%d,%d] for sample slot %d", column, node_index, sample_slot);
}

// Play samples for current step
static void play_samples_for_step(int step) {
    int max_cols = table_get_max_cols();
    
    for (int col = 0; col < max_cols; col++) {
        Cell* cell = table_get_cell(step, col);
        if (!cell || cell->sample_slot == -1) {
            continue; // Empty cell
        }
        
        // Get column nodes
        ColumnNodes* column_nodes = &g_column_nodes[col];
        
        // Stop current active node (smooth fade out)
        if (column_nodes->active_node >= 0) {
            ColumnNode* active = &column_nodes->nodes[column_nodes->active_node];
            active->target_volume = 0.0f; // Fade out
        }
        
        // Setup next node
        int next_node = column_nodes->next_node;
        setup_column_node(col, next_node, cell->sample_slot, cell->volume, cell->pitch);
        
        // Switch active node
        column_nodes->active_node = next_node;
        column_nodes->next_node = (next_node + 1) % 2; // Toggle A/B
    }
}

// Run sequencer timing logic
static void run_sequencer(ma_uint32 frameCount) {
    if (!g_sequencer_playing) return;
    
    for (ma_uint32 frame = 0; frame < frameCount; frame++) {
        g_step_frame_counter++;
        
        // Time to move to the next step?
        if (g_step_frame_counter >= g_frames_per_step) {
            g_step_frame_counter = 0;
            
            // Advance step
            g_current_step++;
            
            // Handle playback region wrapping
            if (g_current_step >= g_playback_region.end) {
                g_current_step = g_playback_region.start;
            }
            
            // Play samples for this step
            play_samples_for_step(g_current_step);

            // Update snapshot for new step
            public_state_write_begin();
            g_public_playback_state.current_step = g_current_step;
            g_public_playback_state.is_playing = g_sequencer_playing;
            public_state_write_end();
        }
    }
}

// Main audio callback
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput; // Unused
    (void)pDevice; // Unused
    run_sequencer(frameCount);
    update_volume_smoothing();
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
}

// Expose pointer to playback state snapshot
const PublicPlaybackState* playback_get_state_ptr(void) {
    return &g_public_playback_state;
}



