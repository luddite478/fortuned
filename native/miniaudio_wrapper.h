#ifndef MINIAUDIO_WRAPPER_H
#define MINIAUDIO_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the miniaudio engine
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_init(void);

// Play a sound from a file
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_sound(const char* file_path);

// Load a sound into memory
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_load_sound(const char* file_path);

// Play a previously loaded sound
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_loaded_sound(void);

// Stop all currently playing sounds
__attribute__((visibility("default"))) __attribute__((used))
void audio_stop_all_sounds(void);

// Check if engine is initialized
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_initialized(void);

// Get current audio route info (for debugging Bluetooth connectivity)
__attribute__((visibility("default"))) __attribute__((used))
void audio_log_route(void);

// Manually reconfigure audio session (for testing)
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_reconfigure_audio_session(void);

// Cleanup the miniaudio engine
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void);

// Sequencer functions (sample-accurate timing)
__attribute__((visibility("default"))) __attribute__((used))
int sequencer_start(int bpm, int steps);
__attribute__((visibility("default"))) __attribute__((used))
void sequencer_stop(void);
__attribute__((visibility("default"))) __attribute__((used))
int sequencer_is_playing(void);
__attribute__((visibility("default"))) __attribute__((used))
int sequencer_get_current_step(void);
__attribute__((visibility("default"))) __attribute__((used))
void sequencer_set_bpm(int bpm);
__attribute__((visibility("default"))) __attribute__((used))
void grid_set_cell(int step, int column, int sample_slot);
__attribute__((visibility("default"))) __attribute__((used))
void grid_clear_cell(int step, int column);
__attribute__((visibility("default"))) __attribute__((used))
void grid_clear_all_cells(void);

// Multi-grid sequencer support
__attribute__((visibility("default"))) __attribute__((used))
void grid_set_columns(int columns);

// MAX number of simultaneous playback slots
#define MINIAUDIO_MAX_SLOTS 1024

// Returns the number of available playback slots (always MINIAUDIO_MAX_SLOTS)
__attribute__((visibility("default"))) __attribute__((used))
int audio_get_slot_count(void);

// Loads a sound into the given slot. When loadToMemory == 1 the file will be
// fully decoded into memory for lowest-latency playback. When 0 the file will
// be streamed from disk.
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_load_sound_to_slot(int slot, const char* file_path, int loadToMemory);

// Returns 1 if the slot successfully has a sound loaded, 0 otherwise.
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_slot_loaded(int slot);

// Starts playback of the sound in the given slot. The sound is mixed together
// with any other playing slots.
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_play_slot(int slot);

// Stops playback of the sound in the given slot.
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_stop_slot(int slot);

// Unloads the sound from the given slot and frees all associated memory.
__attribute__((visibility("default"))) __attribute__((used))
void audio_unload_slot(int slot);

// Memory usage tracking functions
__attribute__((visibility("default"))) __attribute__((used))
uint64_t audio_get_total_memory_usage(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t audio_get_slot_memory_usage(int slot);
__attribute__((visibility("default"))) __attribute__((used))
int audio_get_memory_slot_count(void);

// Memory limit information functions
__attribute__((visibility("default"))) __attribute__((used))
int audio_get_max_memory_slots(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t audio_get_max_memory_file_size(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t audio_get_max_total_memory_usage(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t audio_get_available_memory_capacity(void);

// Output recording/rendering functions (captures mixed grid output to WAV file)
__attribute__((visibility("default"))) __attribute__((used))
int recording_start_output(const char* output_file_path);
__attribute__((visibility("default"))) __attribute__((used))
int recording_stop_output(void);
__attribute__((visibility("default"))) __attribute__((used))
int recording_is_active(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t recording_get_duration_ms(void);

#ifdef __cplusplus
}
#endif

#endif // MINIAUDIO_WRAPPER_H 