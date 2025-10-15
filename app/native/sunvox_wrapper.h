#ifndef SUNVOX_WRAPPER_H
#define SUNVOX_WRAPPER_H

// Simple wrapper around SunVox library for our playback engine
// Maps our table-based sequencer to SunVox patterns and modules

#ifdef __cplusplus
extern "C" {
#endif

// Initialize SunVox engine (called from playback_init)
// Returns 0 on success, negative on error
int sunvox_wrapper_init(void);

// Cleanup SunVox engine (called from playback_cleanup)
void sunvox_wrapper_cleanup(void);

// Load a sample into a SunVox sampler module
// sample_slot: 0..MAX_SAMPLE_SLOTS-1
// file_path: path to audio file
// Returns 0 on success, negative on error
int sunvox_wrapper_load_sample(int sample_slot, const char* file_path);

// Unload a sample from a SunVox sampler module
void sunvox_wrapper_unload_sample(int sample_slot);

// Create a pattern for a section
// Returns 0 on success, negative on error
int sunvox_wrapper_create_section_pattern(int section_index, int section_length);

// Remove a pattern for a section
void sunvox_wrapper_remove_section_pattern(int section_index);

// Sync entire section to its SunVox pattern
void sunvox_wrapper_sync_section(int section_index);

// Sync single cell to SunVox pattern
// Called when a single cell changes
void sunvox_wrapper_sync_cell(int step, int col);

// Set playback mode (updates timeline accordingly)
// current_loop: which loop to use in loop mode (0 = first loop, 1 = second, etc.)
void sunvox_wrapper_set_playback_mode(int song_mode, int current_section, int current_loop);

// Update the timeline/playback order of sections (uses internally stored mode)
void sunvox_wrapper_update_timeline(void);

// Start playback
// Returns 0 on success, negative on error
int sunvox_wrapper_play(void);

// Stop playback
void sunvox_wrapper_stop(void);

// Set BPM
void sunvox_wrapper_set_bpm(int bpm);

// Set playback region (loop range)
// start: inclusive start step
// end: exclusive end step
void sunvox_wrapper_set_region(int start, int end);

// Get current playback line/step
// Returns current line number or -1 if not playing
int sunvox_wrapper_get_current_line(void);

// Get pattern X position for a section (for calculating local position in loop mode)
// Returns X position in timeline or 0 if pattern doesn't exist
int sunvox_wrapper_get_section_pattern_x(int section_index);

// Trigger notes at a specific step (used when starting playback mid-song)
// This manually triggers all notes at the given step
void sunvox_wrapper_trigger_step(int step);

// Render audio frames (called from audio callback)
// buf: output buffer (stereo float32 interleaved)
// frames: number of frames to render
// Returns 1 if audio rendered, 0 if silence
int sunvox_wrapper_render(float* buf, int frames);

// Check if SunVox is initialized
int sunvox_wrapper_is_initialized(void);

// Debug: Dump all pattern information
void sunvox_wrapper_debug_dump_patterns(const char* context);

int sunvox_wrapper_get_pattern_current_loop(int section_index);

#ifdef __cplusplus
}
#endif

#endif // SUNVOX_WRAPPER_H


