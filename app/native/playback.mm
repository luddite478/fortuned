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
#include "pitch.h"
#include "undo_redo.h"

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
static MAColumnNodes g_ma_column_nodes[MAX_SEQUENCER_COLS];

// Playback state
static int g_sequencer_playing = 0;        // transient
static int g_current_step = 0;             // transient
static uint64_t g_frames_per_step = 0;     // derived from bpm
static uint64_t g_step_frame_counter = 0;  // transient

// Playback region and mode
// Unified live/snapshot state
static PlaybackState g_playback_state;  // zero-initialized

// Section loops and tracking (transient counters)
// current_section/current_section_loop live in g_playback_state

// No separate public snapshot; PlaybackState is FFI-visible (prefix fields)
static inline void state_write_begin() { g_playback_state.version++; }
static inline void state_write_end()   { g_playback_state.version++; }
static inline void state_update_prefix() {
    g_playback_state.is_playing = g_sequencer_playing;
    g_playback_state.current_step = g_current_step;
    g_playback_state.sections_loops_num = &g_playback_state.sections_loops_num_storage[0];
}

// Output recording globals
static int g_is_output_recording = 0;
static int g_output_encoder_initialized = 0;
static ma_encoder g_output_encoder;

// Forward declarations
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount);
static void run_sequencer(ma_uint32 frameCount);
static void play_samples_for_step(int step);
static void setup_column_node(int column, int node_index, int sample_slot, float volume, float pitch);
static void update_volume_smoothing(void);
static float calculate_smoothing_alpha(float time_ms);
static float apply_exponential_smoothing(float current, float target, float alpha);
static void handle_song_mode_looping(void);

// Initialize playback system
int playback_init(void) {
    // Make init idempotent: cleanup previous state if already initialized
    if (g_initialized) {
        prnt("🔄 [PLAYBACK] Re-initializing: running cleanup first");
        playback_cleanup();
    }
    
    prnt("🎵 [PLAYBACK] Initializing playback system");
    
    // Initialize sample bank (will internally cleanup)
    sample_bank_init();

    // Reset core playback state
    g_sequencer_playing = 0;
    g_playback_state.bpm = 120;
    g_current_step = -1;
    g_step_frame_counter = 0;
    g_playback_state.song_mode = 0;
    g_playback_state.current_section = 0;
    g_playback_state.current_section_loop = 0;
    g_playback_state.region_start = 0;
    g_playback_state.region_end = 16;
    
    // Initialize sections loops with default values
    for (int i = 0; i < MAX_SECTIONS; i++) g_playback_state.sections_loops_num_storage[i] = DEFAULT_SECTION_LOOPS;
    
    // Initialize column nodes
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        g_ma_column_nodes[col].active_node = -1;  // No active node
        g_ma_column_nodes[col].next_node = 0;     // Start with node A
        
        for (int i = 0; i < MA_NODES_PER_COLUMN; i++) {
            MAColumnNode* node = &g_ma_column_nodes[col].nodes[i];
            node->column = col;
            node->index = i;
            node->node_initialized = 0;
            node->sample_slot = -1;
            node->decoder = NULL;
            node->node = NULL;
            node->pitch_ds = NULL;
            node->pitch_ds_initialized = 0;
            node->user_volume = 1.0f;
            node->current_volume = 0.0f;
            node->target_volume = 0.0f;
            node->volume_rise_coeff = calculate_smoothing_alpha(VOLUME_RISE_TIME_MS);
            node->volume_fall_coeff = calculate_smoothing_alpha(VOLUME_FALL_TIME_MS);
            node->id = 0;
            node->pitch = 1.0f;
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
    g_frames_per_step = (SAMPLE_RATE * 60) / (g_playback_state.bpm * 4); // 1/16 note frames
    
    // Initialize FFI-visible prefix
    g_playback_state.version = 0;
    state_write_begin();
    state_update_prefix();
    state_write_end();

    g_initialized = 1;
    prnt("✅ [PLAYBACK] Playback system initialized (BPM: %d, frames/step: %llu)", 
         g_playback_state.bpm, g_frames_per_step);

    // Seed undo/redo baseline for playback
    UndoRedoManager_record();
    
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
            MAColumnNode* node = &g_ma_column_nodes[col].nodes[i];
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
                if (node->pitch_ds_initialized && node->pitch_ds) {
                    pitch_ds_uninit((ma_pitch_data_source*)node->pitch_ds);
                    free(node->pitch_ds);
                    node->pitch_ds = NULL;
                    node->pitch_ds_initialized = 0;
                }
                node->node_initialized = 0;
            }
        }
    }
    
    // Stop and cleanup device
    ma_device_stop(&g_device);
    // Stop recording if active
    if (g_is_output_recording) {
        g_is_output_recording = 0;
    }
    if (g_output_encoder_initialized) {
        ma_encoder_uninit(&g_output_encoder);
        g_output_encoder_initialized = 0;
    }
    ma_device_uninit(&g_device);
    ma_node_graph_uninit(&g_nodeGraph, NULL);
    
    g_initialized = 0;
    // Mark as not playing in snapshot
    state_write_begin();
    g_sequencer_playing = 0;
    state_update_prefix();
    state_write_end();
    prnt("✅ [PLAYBACK] Cleanup complete");
}

// Start sequencer playback
int playback_start(int bpm, int start_step) {
    if (!g_initialized) {
        prnt_err("❌ [PLAYBACK] Not initialized");
        return -1;
    }
    
    if (bpm > MIN_BPM && bpm <= MAX_BPM) {
        g_playback_state.bpm = bpm;
        g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
    }
    
    g_current_step = start_step;
    g_step_frame_counter = 0;
    g_sequencer_playing = 1;
    
    if (g_playback_state.song_mode) {
        g_playback_state.current_section = table_get_section_at_step(start_step);
        g_playback_state.current_section_loop = 0;
    }

    play_samples_for_step(g_current_step);

    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    prnt("▶️ [PLAYBACK] Started sequencer (BPM: %d, start step: %d)", bpm, start_step);
    return 0;
}

// Stop sequencer playback
void playback_stop(void) {
    g_sequencer_playing = 0;
    g_step_frame_counter = 0;
    g_current_step = -1; 
    
    // Stop all column nodes
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        for (int i = 0; i < 2; i++) {
            MAColumnNode* node = &g_ma_column_nodes[col].nodes[i];
            if (node->node_initialized && node->node) {
                ma_node_set_state((ma_node_base*)node->node, ma_node_state_stopped);
                node->target_volume = 0.0f;
            }
        }
    }
    
    prnt("⏹️ [PLAYBACK] Stopped sequencer");
    state_write_begin();
    state_update_prefix();
    state_write_end();
}

int get_total_steps() {
    int total_steps = 0;
    int sections_count = table_get_sections_count();
    for (int i = 0; i < sections_count; i++) {
        total_steps += table_get_section_step_count(i);
    }
    return total_steps;
}

void playback_set_bpm(int bpm) {
    if (bpm > 0 && bpm <= 300) {
        g_playback_state.bpm = bpm;
        g_frames_per_step = (SAMPLE_RATE * 60) / (bpm * 4); // 1/16 note frames
        prnt("🎵 [PLAYBACK] BPM changed to %d (%llu frames per step)", bpm, g_frames_per_step);
        state_write_begin();
        state_update_prefix();
        state_write_end();
    } else {
        prnt_err("❌ [PLAYBACK] Invalid BPM: %d", bpm);
    }
    // Record snapshot after mutation
    UndoRedoManager_record();
}

void playback_set_region(int start, int end) {
    g_playback_state.region_start = start;
    g_playback_state.region_end = end;
    prnt("🎭 [PLAYBACK] Set playback region: %d to %d", start, end);
    state_write_begin();
    state_update_prefix();
    state_write_end();
    UndoRedoManager_record();
}

void playback_set_mode(int song_mode) {
    g_playback_state.song_mode = song_mode;
    prnt("🎵 [PLAYBACK] Set mode to %s", song_mode ? "song" : "loop");
    state_write_begin();
    state_update_prefix();
    state_write_end();
    UndoRedoManager_record();
}

void switch_to_section(int section_index) {
    int sections_count = table_get_sections_count();
    if (section_index < 0) section_index = 0;
    if (section_index >= sections_count) section_index = sections_count - 1;

    int was_playing = g_sequencer_playing;
    if (was_playing) {
        playback_stop();
    }

    g_playback_state.current_section = section_index;
    g_playback_state.current_section_loop = 0;
    int section_start_step = table_get_section_start_step(g_playback_state.current_section);
    // Only set current_step when actively playing; keep -1 when stopped
    g_current_step = was_playing ? section_start_step : -1;

    // Always set region to current section; song mode progression is handled at region end.
    int section_steps_num = table_get_section_step_count(g_playback_state.current_section);
    playback_set_region(section_start_step, section_start_step + section_steps_num);

    state_write_begin();
    state_update_prefix();
    state_write_end();

    prnt("🎯 [PLAYBACK] Switched to section %d", g_playback_state.current_section);

    if (was_playing) {
        playback_start(g_playback_state.bpm, g_current_step);
    }
    UndoRedoManager_record();
}

// Handle song mode section advancement and loop counting
static void handle_song_mode_looping(void) {
    g_playback_state.current_section_loop++;
    
    if (g_playback_state.current_section_loop >= g_playback_state.sections_loops_num_storage[g_playback_state.current_section]) {
        int sections_count = table_get_sections_count();
        int is_last_section = (g_playback_state.current_section >= sections_count - 1);

        if (is_last_section) {
            g_playback_state.current_section_loop = g_playback_state.sections_loops_num_storage[g_playback_state.current_section] - 1;
            playback_stop();
            return;
        } else {
            g_playback_state.current_section++;
            g_playback_state.current_section_loop = 0;

            int section_start = table_get_section_start_step(g_playback_state.current_section);
            int section_steps = table_get_section_step_count(g_playback_state.current_section);
            playback_set_region(section_start, section_start + section_steps);
        }
    }
    
    g_current_step = g_playback_state.region_start;
}

void playback_set_section_loops_num(int section, int loops) {
    if (section < 0 || section >= MAX_SECTIONS) {
        prnt_err("❌ [PLAYBACK] Invalid section index: %d", section);
        return;
    }
    
    if (loops < MIN_SECTION_LOOPS || loops > MAX_SECTION_LOOPS) {
        prnt_err("❌ [PLAYBACK] Invalid loop count: %d (must be %d-%d)", loops, MIN_SECTION_LOOPS, MAX_SECTION_LOOPS);
        return;
    }
    
    g_playback_state.sections_loops_num_storage[section] = loops;
    
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    prnt("🔁 [PLAYBACK] Set section %d loops to %d", section, loops);
    UndoRedoManager_record();
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
            MAColumnNode* node = &g_ma_column_nodes[col].nodes[i];
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
    
    MAColumnNode* node = &g_ma_column_nodes[column].nodes[node_index];
    
    // If this node is already initialized with the same sample, handle according to pitch method.
    if (node->node_initialized && node->sample_slot == sample_slot) {
        int must_rebuild = 1;
        if (node->pitch_ds_initialized && node->pitch_ds) {
            must_rebuild = pitch_should_rebuild_for_change((ma_pitch_data_source*)node->pitch_ds, node->pitch, pitch);
        }
        if (!must_rebuild) {
            if (node->pitch_ds_initialized && node->pitch_ds) {
                pitch_ds_seek_to_start((ma_pitch_data_source*)node->pitch_ds);
            } else if (node->decoder) {
                ma_decoder_seek_to_pcm_frame((ma_decoder*)node->decoder, 0);
            }
            ma_node_set_state((ma_node_base*)node->node, ma_node_state_started);
            node->user_volume = volume;
            node->current_volume = 0.0f;
            node->target_volume = volume;
            return;
        }
        // Fallthrough to rebuild below to pick up cache/new pitch
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
        if (node->pitch_ds_initialized && node->pitch_ds) {
            pitch_ds_uninit((ma_pitch_data_source*)node->pitch_ds);
            free(node->pitch_ds);
            node->pitch_ds = NULL;
            node->pitch_ds_initialized = 0;
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
    
    // Initialize pitch data source first (preprocessing default; kick async if needed)
    node->pitch_ds = pitch_ds_create((ma_data_source*)node->decoder,
                                     pitch,
                                     CHANNELS,
                                     SAMPLE_RATE,
                                     sample_slot);
    if (!node->pitch_ds) {
        prnt_err("❌ [PLAYBACK] Failed to allocate pitch data source");
        ma_decoder_uninit((ma_decoder*)node->decoder);
        free(node->decoder);
        node->decoder = NULL;
        return;
    }
    node->pitch_ds_initialized = 1;

    // Start async preprocessing if method is preprocessing and pitch != 1.0
    if (pitch_get_method() == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && fabsf(pitch - 1.0f) > 0.001f) {
        pitch_start_async_preprocessing(sample_slot, pitch);
        prnt("⚙️ [PLAYBACK] Preprocess requested (slot=%d, pitch=%.3f)", sample_slot, pitch);
    }

    // Allocate data source node
    node->node = malloc(sizeof(ma_data_source_node));
    if (!node->node) {
        prnt_err("❌ [PLAYBACK] Failed to allocate data source node");
        if (node->pitch_ds_initialized && node->pitch_ds) {
            pitch_ds_destroy((ma_pitch_data_source*)node->pitch_ds);
            node->pitch_ds = NULL;
            node->pitch_ds_initialized = 0;
        }
        ma_decoder_uninit((ma_decoder*)node->decoder);
        free(node->decoder);
        node->decoder = NULL;
        return;
    }
    
    // Initialize data source node using pitch data source (wraps either decoder or preprocessed buffer)
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(
        (ma_data_source*)pitch_ds_as_data_source((ma_pitch_data_source*)node->pitch_ds)
    );
    result = ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, (ma_data_source_node*)node->node);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize data source node: %d", result);
        if (node->pitch_ds_initialized && node->pitch_ds) {
            pitch_ds_destroy((ma_pitch_data_source*)node->pitch_ds);
            node->pitch_ds = NULL;
            node->pitch_ds_initialized = 0;
        }
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
    node->pitch = pitch;
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
        MAColumnNodes* column_nodes = &g_ma_column_nodes[col];
        
        // Stop current active node (smooth fade out)
        if (column_nodes->active_node >= 0) {
            MAColumnNode* active = &column_nodes->nodes[column_nodes->active_node];
            active->target_volume = 0.0f; // Fade out
        }
        
        // Setup next node with resolved pitch (cell override or sample bank default)
        int next_node = column_nodes->next_node;
        float resolved_pitch = cell->settings.pitch;
        if (resolved_pitch == DEFAULT_CELL_PITCH) {
            resolved_pitch = sample_bank_get_sample(cell->sample_slot)->settings.pitch;
        }
        setup_column_node(col, next_node, cell->sample_slot, cell->settings.volume, resolved_pitch);
        
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
            g_current_step++;
            
            if (g_current_step >= g_playback_state.region_end) {
                if (g_playback_state.song_mode) {
                    handle_song_mode_looping();
                    if (!g_sequencer_playing) {
                        return;
                    }
                } else {
                    g_current_step = g_playback_state.region_start;
                }
            }
            
            play_samples_for_step(g_current_step);

            state_write_begin();
            state_update_prefix();
            state_write_end();
        }
    }
}

// Main audio callback
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput; // Unused
    (void)pDevice; // Unused
    run_sequencer(frameCount);
    update_volume_smoothing();
    // Render mixed output
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
    // Optional: record rendered output (float32 interleaved)
    if (g_is_output_recording && g_output_encoder_initialized) {
        ma_encoder_write_pcm_frames(&g_output_encoder, pOutput, frameCount, NULL);
    }
}

// Expose pointer to playback state snapshot
const PlaybackState* playback_get_state_ptr(void) { return &g_playback_state; }

// Unified playback state accessor
const PlaybackState* playback_state_get_ptr(void) { return &g_playback_state; }

void playback_apply_state(const PlaybackState* state) {
    if (state == NULL) return;
    state_write_begin();
    g_playback_state.bpm = state->bpm;
    g_playback_state.region_start = state->region_start;
    g_playback_state.region_end = state->region_end;
    g_playback_state.song_mode = state->song_mode;
    g_playback_state.current_section = state->current_section;
    g_playback_state.current_section_loop = state->current_section_loop;
    for (int i = 0; i < MAX_SECTIONS; i++) g_playback_state.sections_loops_num_storage[i] = state->sections_loops_num_storage[i];
    g_frames_per_step = (SAMPLE_RATE * 60) / (g_playback_state.bpm * 4);
    state_update_prefix();
    state_write_end();
}

// Start/stop/isActive output recording (WAV)
int recording_start(const char* file_path) {
    if (!g_initialized) {
        prnt_err("❌ [RECORDING] Not initialized");
        return -1;
    }
    if (g_is_output_recording) {
        prnt_err("❌ [RECORDING] Already active");
        return -2;
    }
    ma_result res;
    ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, CHANNELS, SAMPLE_RATE);
    res = ma_encoder_init_file(file_path, &cfg, &g_output_encoder);
    if (res != MA_SUCCESS) {
        prnt_err("❌ [RECORDING] Failed to init encoder: %d", res);
        return -3;
    }
    g_output_encoder_initialized = 1;
    g_is_output_recording = 1;
    prnt("🎙️ [RECORDING] Started → %s", file_path);
    return 0;
}

void recording_stop(void) {
    if (!g_is_output_recording) return;
    g_is_output_recording = 0;
    if (g_output_encoder_initialized) {
        ma_encoder_uninit(&g_output_encoder);
        g_output_encoder_initialized = 0;
    }
    prnt("⏹️ [RECORDING] Stopped");
}

int recording_is_active(void) {
    return g_is_output_recording;
}




