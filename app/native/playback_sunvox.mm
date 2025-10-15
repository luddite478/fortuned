#include "playback.h"
#include "sunvox_wrapper.h"
#include "table.h"
#include "sample_bank.h"
#include "undo_redo.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>
#include <unistd.h>

// Include SunVox for sv_rewind
#define SUNVOX_STATIC_LIB
#include "sunvox.h"

// Include miniaudio for audio device (header only, NO implementation - that's in miniaudio_impl.mm)
#include "miniaudio/miniaudio.h"

// Include recording module
#include "recording.h"

// Platform-specific includes and logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PLAYBACK"
#endif

// Playback state
static int g_initialized = 0;
static int g_sequencer_playing = 0;
static int g_current_step = 0;
static PlaybackState g_playback_state;
static int g_consecutive_stopped_count = 0;  // Count consecutive "stopped" detections

// Audio device for output
static ma_device g_audio_device;
static int g_audio_device_initialized = 0;

// Seqlock helpers
static inline void state_write_begin() { g_playback_state.version++; }
static inline void state_write_end()   { g_playback_state.version++; }
static inline void state_update_prefix() {
    g_playback_state.is_playing = g_sequencer_playing;
    g_playback_state.current_step = g_current_step;
    g_playback_state.sections_loops_num = &g_playback_state.sections_loops_num_storage[0];
}

// Audio callback - called by miniaudio device to fill output buffer
// This is the ONLY place where sv_audio_callback() is called - no double consumption!
static void audio_callback(ma_device* device, void* output, const void* input, ma_uint32 frameCount) {
    (void)device;
    (void)input;
    
    float* pOutput = (float*)output;
    
    // Get audio from SunVox (single call - this is the magic!)
    // SunVox is in offline mode, so it only generates audio when we ask for it
    int result = sv_audio_callback(pOutput, frameCount, 0, sv_get_ticks());
    
    if (result < 0) {
        // SunVox failed, output silence
        memset(pOutput, 0, frameCount * 2 * sizeof(float));  // 2 channels
        return;
    }
    
    // If recording is active, write the same buffer to WAV file
    // This is clean - we record exactly what's being played
    recording_write_frames_from_callback(pOutput, frameCount);
    
    // pOutput now contains audio from SunVox
    // miniaudio will automatically output it to speakers
}

// Polling timer for state sync
static pthread_t g_poll_thread;
static int g_poll_thread_running = 0;

// Forward declarations
static void* poll_thread_func(void* arg);
static void update_current_step_from_sunvox(void);
static int sunvox_is_actually_playing(void);
static void audio_callback(ma_device* device, void* output, const void* input, ma_uint32 frameCount);

// Initialize playback system
int playback_init(void) {
    if (g_initialized) {
        prnt("🔄 [PLAYBACK] Re-initializing: running cleanup first");
        playback_cleanup();
    }
    
    prnt("🎵 [PLAYBACK] Initializing playback system (SunVox backend)");
    
    // Initialize sample bank
    sample_bank_init();
    
    // Reset playback state
    g_sequencer_playing = 0;
    g_playback_state.bpm = 120;
    g_current_step = -1;
    g_playback_state.song_mode = 0;
    g_playback_state.current_section = 0;
    g_playback_state.current_section_loop = 0;
    g_playback_state.region_start = 0;
    g_playback_state.region_end = 16;
    
    // Initialize section loops
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_playback_state.sections_loops_num_storage[i] = DEFAULT_SECTION_LOOPS;
    }
    
    // Initialize FFI-visible state
    g_playback_state.version = 0;
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    // Initialize SunVox
    int result = sunvox_wrapper_init();
    if (result < 0) {
        prnt_err("❌ [PLAYBACK] Failed to initialize SunVox");
        return -1;
    }
    
    // Set initial BPM
    sunvox_wrapper_set_bpm(g_playback_state.bpm);
    
    // Create patterns for existing sections (table_init() was called before SunVox init)
    int sections_count = table_get_sections_count();
    for (int i = 0; i < sections_count; i++) {
        int section_length = table_get_section_step_count(i);
        sunvox_wrapper_create_section_pattern(i, section_length);
    }
    
    
    // Initialize audio device
    // This creates the audio output that will call our callback
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = ma_format_f32;      // Float32 (matches SunVox)
    deviceConfig.playback.channels = 2;                 // Stereo
    deviceConfig.sampleRate = 48000;                    // 48kHz (matches SunVox)
    deviceConfig.dataCallback = audio_callback;
    deviceConfig.pUserData = NULL;
    
    ma_result audio_result = ma_device_init(NULL, &deviceConfig, &g_audio_device);
    if (audio_result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to initialize audio device: %d", audio_result);
        sunvox_wrapper_cleanup();
        return -1;
    }
    g_audio_device_initialized = 1;
    
    // Start audio device
    audio_result = ma_device_start(&g_audio_device);
    if (audio_result != MA_SUCCESS) {
        prnt_err("❌ [PLAYBACK] Failed to start audio device: %d", audio_result);
        ma_device_uninit(&g_audio_device);
        g_audio_device_initialized = 0;
        sunvox_wrapper_cleanup();
        return -1;
    }
    
    g_initialized = 1;
    prnt("✅ [PLAYBACK] Playback system initialized (BPM: %d)", g_playback_state.bpm);
    prnt("✅ [PLAYBACK] Audio device started (48kHz, stereo, float32)");
    
    // Seed undo/redo baseline
    UndoRedoManager_record();
    
    // Start polling thread for state sync
    g_poll_thread_running = 1;
    pthread_create(&g_poll_thread, NULL, poll_thread_func, NULL);
    
    return 0;
}

// Cleanup playback system
void playback_cleanup(void) {
    if (!g_initialized) return;
    
    prnt("🧹 [PLAYBACK] Cleaning up playback system");
    
    // Stop playback
    playback_stop();
    
    // Stop recording if active (recording module handles its own cleanup)
    if (recording_is_active()) {
        recording_stop();
    }
    
    // Stop polling thread
    if (g_poll_thread_running) {
        g_poll_thread_running = 0;
        pthread_join(g_poll_thread, NULL);
    }
    
    // Stop and cleanup audio device
    if (g_audio_device_initialized) {
        ma_device_stop(&g_audio_device);
        ma_device_uninit(&g_audio_device);
        g_audio_device_initialized = 0;
        prnt("✅ [PLAYBACK] Audio device stopped and cleaned up");
    }
    
    // Cleanup SunVox
    sunvox_wrapper_cleanup();
    
    // Cleanup sample bank
    sample_bank_cleanup();
    
    g_initialized = 0;
    
    // Update state
    state_write_begin();
    g_sequencer_playing = 0;
    state_update_prefix();
    state_write_end();
    
    prnt("✅ [PLAYBACK] Cleanup complete");
}

// Start sequencer playback
int playback_start(int bpm, int start_step) {
    prnt("▶️ [PLAYBACK START] === START CALLED ===");
    prnt("▶️ [PLAYBACK START] bpm=%d, start_step=%d", bpm, start_step);
    
    if (!g_initialized) {
        prnt_err("❌ [PLAYBACK] Not initialized");
        return -1;
    }
    
    if (bpm >= MIN_BPM && bpm <= MAX_BPM) {
        g_playback_state.bpm = bpm;
        sunvox_wrapper_set_bpm(bpm);
    }
    
    // Use the currently selected section from the global state as the source of truth.
    int section_index = g_playback_state.current_section;
    if (section_index < 0) {
        section_index = 0; // Fallback to the first section if state is invalid.
    }
    
    // The playhead should start at the beginning of this section.
    g_current_step = table_get_section_start_step(section_index);
    
    // Reset loop counter to 0 (displays as "1/X" in UI)
    // This is the ONLY place where we reset the counter after it was preserved at stop
    g_playback_state.current_section_loop = 0;
    prnt("🔄 [PLAYBACK] Reset loop counter to 0 (will display as 1/X)");
    
    // Configure SunVox for song/loop mode, starting with our target section.
    // This will also reset the engine's internal loop counter via sv_set_pattern_loop_count()
    sunvox_wrapper_set_playback_mode(g_playback_state.song_mode, section_index, 0);
    
    // Get the absolute timeline position (line number) for the start of the target section's pattern.
    int timeline_start_line = sunvox_wrapper_get_section_pattern_x(section_index);
    
    prnt("🎯 [PLAYBACK] Starting playback at section %d (timeline line %d)", section_index, timeline_start_line);
    
    // Rewind SunVox to the calculated starting line. This is the crucial fix.
    sv_rewind(0, timeline_start_line);
    
    // Start playback in SunVox
    // Note: sv_play() now preserves single_pattern_play if already set by sv_set_pattern_loop()
    sunvox_wrapper_play();
    
    // THEN set our flag (after SunVox is started)
    // This prevents poll thread from checking before SunVox is ready
    g_sequencer_playing = 1;
    g_consecutive_stopped_count = 0;  // Reset consecutive stopped counter
    
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    prnt("▶️ [PLAYBACK] Started sequencer (BPM: %d, section: %d, mode: %s)", 
         bpm, section_index, g_playback_state.song_mode ? "song" : "loop");
    return 0;
}

// Stop sequencer playback
void playback_stop(void) {
    prnt("⏹️ [PLAYBACK STOP] === STOP CALLED ===");
    prnt("⏹️ [PLAYBACK STOP] Stack trace would show caller (if available)");
    
    g_sequencer_playing = 0;
    g_current_step = -1;
    
    sunvox_wrapper_stop();
    
    prnt("⏹️ [PLAYBACK] Stopped sequencer");
    
    state_write_begin();
    state_update_prefix();
    state_write_end();
}

// Set BPM
void playback_set_bpm(int bpm) {
    if (bpm >= MIN_BPM && bpm <= MAX_BPM) {
        g_playback_state.bpm = bpm;
        sunvox_wrapper_set_bpm(bpm);
        
        prnt("🎵 [PLAYBACK] BPM changed to %d", bpm);
        
        state_write_begin();
        state_update_prefix();
        state_write_end();
        
        UndoRedoManager_record();
    } else {
        prnt_err("❌ [PLAYBACK] Invalid BPM: %d", bpm);
    }
}

// Set playback region
void playback_set_region(int start, int end) {
    g_playback_state.region_start = start;
    g_playback_state.region_end = end;
    
    // In multi-pattern mode, regions are handled via timeline
    // Just update state for UI
    
    prnt("🎭 [PLAYBACK] Set playback region: %d to %d", start, end);
    
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    UndoRedoManager_record();
}

// Set playback mode
void playback_set_mode(int song_mode) {
    int was_loop_mode = !g_playback_state.song_mode;
    
    prnt("🎵 [PLAYBACK] === PLAYBACK MODE CHANGE ===");
    prnt("🎵 [PLAYBACK] Old mode: %s, New mode: %s", 
         was_loop_mode ? "loop" : "song", song_mode ? "song" : "loop");
    prnt("🎵 [PLAYBACK] g_sequencer_playing: %d", g_sequencer_playing);
    prnt("🎵 [PLAYBACK] Counter BEFORE mode change: section=%d, loop=%d", 
         g_playback_state.current_section, g_playback_state.current_section_loop);
    
    // If switching TO loop mode from song mode, determine which section and loop we're currently in
    // Preserve exact position so counter stays frozen at current loop value
    if (!song_mode && !was_loop_mode && g_sequencer_playing) {
        // Song → Loop: Find current section AND loop based on timeline position
        int current_line = sunvox_wrapper_get_current_line();
        if (current_line >= 0) {
            int sections_count = table_get_sections_count();
            int timeline_pos = 0;
            int found = 0;
            
            for (int i = 0; i < sections_count && !found; i++) {
                int section_steps = table_get_section_step_count(i);
                int loops = g_playback_state.sections_loops_num_storage[i];
                int section_total_lines = section_steps * loops;
                
                if (current_line >= timeline_pos && current_line < timeline_pos + section_total_lines) {
                    // We're in section i - now find which loop
                    int offset_in_section = current_line - timeline_pos;
                    int loop_num = offset_in_section / section_steps;
                    
                    g_playback_state.current_section = i;
                    g_playback_state.current_section_loop = loop_num;
                    
                    prnt("🎯 [PLAYBACK] Song→Loop: Detected section %d, loop %d/%d (at line %d)", 
                         i, loop_num + 1, loops, current_line);
                    prnt("🔒 [PLAYBACK] Counter will freeze at %d/%d in loop mode", loop_num + 1, loops);
                    found = 1;
                } else {
                    timeline_pos += section_total_lines;
                }
            }
        }
    }
    
    // CRITICAL: Update SunVox FIRST, before updating our flags
    // This prevents poll thread from seeing new mode while SunVox has old state
    sunvox_wrapper_set_playback_mode(song_mode, g_playback_state.current_section, g_playback_state.current_section_loop);
    
    // Reset consecutive stopped counter (mode change might cause transient state)
    g_consecutive_stopped_count = 0;
    
    // If switching from loop to song mode, calculate the actual loop number from physical position
    // This ensures seamless transition: if we're at line 21 in a 16-line pattern, we're in loop 2/4
    if (song_mode && was_loop_mode && g_sequencer_playing) {
        int current_line = sunvox_wrapper_get_current_line();
        if (current_line >= 0) {
            // Calculate which loop we're physically in
            int section_steps = table_get_section_step_count(g_playback_state.current_section);
            int pattern_x = sunvox_wrapper_get_section_pattern_x(g_playback_state.current_section);
            int offset_from_start = current_line - pattern_x;
            int loop_num = offset_from_start / section_steps;
            
            // Update to the actual loop we're in
            g_playback_state.current_section_loop = loop_num;
            
            prnt("🔄 [PLAYBACK] Loop→Song: Calculated actual loop from position: %d/%d (line=%d, offset=%d, steps=%d)",
                 loop_num + 1, g_playback_state.sections_loops_num_storage[g_playback_state.current_section],
                 current_line, offset_from_start, section_steps);
        }
    }
    
    // NOW update our state flags
    // 
    // Loop counter behavior:
    // - Song→Loop: Counter detected and frozen at current timeline position
    // - Loop→Song: Counter calculated from physical position, then updates naturally
    // - In loop mode: Counter frozen (stays at value when entering loop mode)
    // - In song mode: Counter updates naturally as playhead progresses through timeline
    
    // Update state (after SunVox is updated)
    state_write_begin();
    g_playback_state.song_mode = song_mode;
    // Note: current_section and current_section_loop were updated above based on actual position
    state_update_prefix();
    state_write_end();
    
    prnt("🎵 [PLAYBACK] Counter AFTER mode change: section=%d, loop=%d", 
         g_playback_state.current_section, g_playback_state.current_section_loop);
    prnt("🎵 [PLAYBACK] Mode change complete - NO stop/start called");
    prnt("🎵 [PLAYBACK] === PLAYBACK MODE CHANGE DONE ===");
    
    UndoRedoManager_record();
}

// Switch to section
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
    
    // Only set current_step when actively playing; keep -1 when stopped (hides position bar)
    g_current_step = was_playing ? section_start_step : -1;
    
    int section_steps_num = table_get_section_step_count(g_playback_state.current_section);
    playback_set_region(section_start_step, section_start_step + section_steps_num);
    
    // Update SunVox timeline for this section (this will also rewind to 0)
    sunvox_wrapper_set_playback_mode(g_playback_state.song_mode, section_index, 0);
    
    // Update state so UI reflects new position
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    prnt("🎯 [PLAYBACK] Switched to section %d (step %d)", 
         g_playback_state.current_section, g_current_step);
    
    if (was_playing) {
        playback_start(g_playback_state.bpm, g_current_step);
    }
    
    UndoRedoManager_record();
}

// Set section loops count
void playback_set_section_loops_num(int section, int loops) {
    if (section < 0 || section >= MAX_SECTIONS) {
        prnt_err("❌ [PLAYBACK] Invalid section index: %d", section);
        return;
    }
    
    if (loops < MIN_SECTION_LOOPS || loops > MAX_SECTION_LOOPS) {
        prnt_err("❌ [PLAYBACK] Invalid loop count: %d", loops);
        return;
    }
    
    g_playback_state.sections_loops_num_storage[section] = loops;
    
    state_write_begin();
    state_update_prefix();
    state_write_end();
    
    prnt("🔁 [PLAYBACK] Set section %d loops to %d", section, loops);
    UndoRedoManager_record();
}

// Get playback state pointer
const PlaybackState* playback_get_state_ptr(void) {
    return &g_playback_state;
}

const PlaybackState* playback_state_get_ptr(void) {
    return &g_playback_state;
}

// Apply playback state
void playback_apply_state(const PlaybackState* state) {
    if (state == NULL) return;
    
    state_write_begin();
    g_playback_state.bpm = state->bpm;
    g_playback_state.region_start = state->region_start;
    g_playback_state.region_end = state->region_end;
    g_playback_state.song_mode = state->song_mode;
    g_playback_state.current_section = state->current_section;
    g_playback_state.current_section_loop = state->current_section_loop;
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_playback_state.sections_loops_num_storage[i] = state->sections_loops_num_storage[i];
    }
    state_update_prefix();
    state_write_end();
    
    // Update SunVox settings
    sunvox_wrapper_set_bpm(g_playback_state.bpm);
    sunvox_wrapper_set_region(g_playback_state.region_start, g_playback_state.region_end);
}

// Dummy implementations for compatibility
ma_node_graph* playback_get_node_graph(void) { return NULL; }
void playback_set_smoothing_rise_time(float ms) {}
void playback_set_smoothing_fall_time(float ms) {}
float playback_get_smoothing_rise_time(void) { return DEFAULT_VOLUME_RISE_TIME_MS; }
float playback_get_smoothing_fall_time(void) { return DEFAULT_VOLUME_FALL_TIME_MS; }

// Recording functions are now in recording.mm module

// Helper: Check if SunVox is actually playing (single source of truth)
static int sunvox_is_actually_playing(void) {
    if (!g_initialized || !sunvox_wrapper_is_initialized()) {
        return 0;
    }
    
    // Primary check: sv_end_of_song() - checks the engine's internal playing flag
    // Returns 0 if playing, 1 if stopped
    int stopped = sv_end_of_song(0);
    
    if (stopped) {
        return 0;  // SunVox is stopped
    }
    
    // Secondary check: In song mode with autostop enabled, verify we haven't reached the end
    // This prevents false positives during mode switches
    if (g_playback_state.song_mode) {
        int autostop = sv_get_autostop(0);
        if (autostop) {
            int line = sv_get_current_line(0);
            int song_length = sv_get_song_length_lines(0);
            
            // If we're past the end of the timeline, we should be stopped
            // (but sv_end_of_song might not have updated yet)
            if (line >= song_length) {
                return 0;  // Past end, should be stopped
            }
        }
    }
    
    return 1;  // SunVox is playing
}

// Polling thread function - just updates state from SunVox
static void* poll_thread_func(void* arg) {
    (void)arg;
    
    prnt("🔄 [PLAYBACK] Polling thread started");
    
    int poll_iter = 0;
    while (g_poll_thread_running) {
        poll_iter++;
        
        if (!g_initialized) {
            usleep(16000);
            continue;
        }

        if (!sunvox_wrapper_is_initialized()) {
            usleep(16000);
            continue;
        }
        
        if (g_sequencer_playing) {
            
            // Check if SunVox is actually playing (single source of truth)
            int sunvox_playing = sunvox_is_actually_playing();
            
            if (!sunvox_playing) {
                // SunVox appears stopped - count consecutive occurrences
                g_consecutive_stopped_count++;
                
                // Set current_step to -1 immediately on first detection
                // This ensures UI shows "stopped" state right away
                if (g_consecutive_stopped_count == 1) {
                    state_write_begin();
                    g_current_step = -1;
                    state_update_prefix();
                    state_write_end();
                }
                
                // Only actually stop if we see this for 3 consecutive cycles
                // This filters out transient false positives (e.g., right after start)
                if (g_consecutive_stopped_count >= 3) {
                    prnt("🛑 [PLAYBACK] SunVox stopped (mode=%s, %d consecutive detections)", 
                         g_playback_state.song_mode ? "SONG" : "LOOP",
                         g_consecutive_stopped_count);
                    
                    // In song mode, preserve the final loop counter value (e.g., stay at 4/4)
                    // The loop counter should only reset when playback_start() is called
                    state_write_begin();
                    g_sequencer_playing = 0;
                    // current_step already set to -1 above
                    // NOTE: current_section and current_section_loop are NOT reset here
                    // They stay at their final values until playback_start() resets them
                    state_update_prefix();
                    state_write_end();
                    
                    prnt("🔒 [PLAYBACK] Stopped - preserving state: section=%d, loop=%d", 
                         g_playback_state.current_section,
                         g_playback_state.current_section_loop);
                    prnt("✅ [PLAYBACK] State updated: is_playing=%d, current_step=%d (should be 0, -1)", 
                         g_playback_state.is_playing,
                         g_playback_state.current_step);
                    
                    g_consecutive_stopped_count = 0;  // Reset counter
                    
                    // Don't continue updating position
                    usleep(16000);
                    continue;
                }
                
                // Still waiting for consecutive confirmations, skip this cycle
                usleep(16000);
                continue;
            } else {
                // SunVox is playing - reset consecutive stopped counter
                g_consecutive_stopped_count = 0;
            }
            
            // Update current step from SunVox
            update_current_step_from_sunvox();
        }
        
        // Poll every 16ms (~60Hz)
        usleep(16000);
    }
    
    prnt("🔄 [PLAYBACK] Polling thread stopped");
    return NULL;
}

// Update current step from SunVox playback position
static void update_current_step_from_sunvox(void) {
    int line = sunvox_wrapper_get_current_line();
    if (line < 0) {
        return; // Not an error, just means playback is stopped
    }

    // --- Position Calculation ---
    // With the no-clone timeline, we can derive everything from the absolute line number.
    int sections_count = table_get_sections_count();
    int timeline_pos = 0;
    int current_section_from_line = -1;
    int section_start_step = 0;
    int local_line = 0;

    for (int i = 0; i < sections_count; i++) {
        int section_steps = table_get_section_step_count(i);
        if (line >= timeline_pos && line < timeline_pos + section_steps) {
            current_section_from_line = i;
            local_line = line - timeline_pos;
            section_start_step = table_get_section_start_step(i);
            break;
        }
        timeline_pos += section_steps;
    }

    if (current_section_from_line == -1) {
        return; // Playhead is past the end of the known timeline
    }
    
    // --- State Update ---
    // Get the true loop number directly from the SunVox engine.
    int engine_loop = sunvox_wrapper_get_pattern_current_loop(current_section_from_line);
    
    // Calculate the final loop value for the UI. It's only non-zero in song mode.
    int final_loop = g_playback_state.song_mode ? engine_loop : 0;
    
    // Calculate the new global step.
    int new_global_step = section_start_step + local_line;

    // Update state only if something has changed.
    if (g_current_step != new_global_step ||
        g_playback_state.current_section != current_section_from_line ||
        g_playback_state.current_section_loop != final_loop)
    {
        state_write_begin();
        g_current_step = new_global_step;
        g_playback_state.current_section = current_section_from_line;
        g_playback_state.current_section_loop = final_loop;
        state_update_prefix();
        state_write_end();
    }
}
