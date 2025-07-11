#ifndef SEQUENCER_H
#define SEQUENCER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the audio engine
__attribute__((visibility("default"))) __attribute__((used))
int init(void);

// Play a sound from a file
__attribute__((visibility("default"))) __attribute__((used))
int play_sound(const char* file_path);

// Load a sound into memory
__attribute__((visibility("default"))) __attribute__((used))
int load_sound(const char* file_path);

// Play a previously loaded sound
__attribute__((visibility("default"))) __attribute__((used))
int play_loaded_sound(void);

// Stop all currently playing sounds
__attribute__((visibility("default"))) __attribute__((used))
void stop_all_sounds(void);

// Check if engine is initialized
__attribute__((visibility("default"))) __attribute__((used))
int is_initialized(void);

// Get current audio route info (for debugging Bluetooth connectivity)
__attribute__((visibility("default"))) __attribute__((used))
void log_route(void);

// Manually reconfigure audio session (for testing)
__attribute__((visibility("default"))) __attribute__((used))
int reconfigure_audio_session(void);

// Cleanup the audio engine
__attribute__((visibility("default"))) __attribute__((used))
void cleanup(void);

// Sequencer functions (sample-accurate timing)
__attribute__((visibility("default"))) __attribute__((used))
int start(int bpm, int steps);
__attribute__((visibility("default"))) __attribute__((used))
void stop(void);
__attribute__((visibility("default"))) __attribute__((used))
int is_playing(void);
__attribute__((visibility("default"))) __attribute__((used))
int get_current_step(void);
__attribute__((visibility("default"))) __attribute__((used))
void set_bpm(int bpm);
__attribute__((visibility("default"))) __attribute__((used))
void set_cell(int step, int column, int sample_slot);
__attribute__((visibility("default"))) __attribute__((used))
void clear_cell(int step, int column);
__attribute__((visibility("default"))) __attribute__((used))
void clear_all_cells(void);

// Multi-grid sequencer support
__attribute__((visibility("default"))) __attribute__((used))
void set_columns(int columns);

// MAX number of simultaneous playback slots
#define MAX_SLOTS 1024

// Returns the number of available playback slots (always MAX_SLOTS)
__attribute__((visibility("default"))) __attribute__((used))
int get_slot_count(void);

// Loads a sound into the given slot. When loadToMemory == 1 the file will be
// fully decoded into memory for lowest-latency playback. When 0 the file will
// be streamed from disk.
__attribute__((visibility("default"))) __attribute__((used))
int load_sound_to_slot(int slot, const char* file_path, int loadToMemory);

// Returns 1 if the slot successfully has a sound loaded, 0 otherwise.
__attribute__((visibility("default"))) __attribute__((used))
int is_slot_loaded(int slot);

// Starts playback of the sound in the given slot. The sound is mixed together
// with any other playing slots.
__attribute__((visibility("default"))) __attribute__((used))
int play_slot(int slot);

// Stops playback of the sound in the given slot.
__attribute__((visibility("default"))) __attribute__((used))
void stop_slot(int slot);

// Unloads the sound from the given slot and frees all associated memory.
__attribute__((visibility("default"))) __attribute__((used))
void unload_slot(int slot);

// Memory usage tracking functions
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_total_memory_usage(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_slot_memory_usage(int slot);
__attribute__((visibility("default"))) __attribute__((used))
int get_memory_slot_count(void);

// Memory limit information functions
__attribute__((visibility("default"))) __attribute__((used))
int get_max_memory_slots(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_max_memory_file_size(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_max_total_memory_usage(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_available_memory_capacity(void);

// Volume control functions
__attribute__((visibility("default"))) __attribute__((used))
int set_sample_bank_volume(int bank, float volume);
__attribute__((visibility("default"))) __attribute__((used))
float get_sample_bank_volume(int bank);
__attribute__((visibility("default"))) __attribute__((used))
int set_cell_volume(int step, int column, float volume);
__attribute__((visibility("default"))) __attribute__((used))
float get_cell_volume(int step, int column);

// Pitch control functions
__attribute__((visibility("default"))) __attribute__((used))
int set_sample_bank_pitch(int bank, float pitch);
__attribute__((visibility("default"))) __attribute__((used))
float get_sample_bank_pitch(int bank);
__attribute__((visibility("default"))) __attribute__((used))
int set_cell_pitch(int step, int column, float pitch);
__attribute__((visibility("default"))) __attribute__((used))
float get_cell_pitch(int step, int column);

// Output recording/rendering functions (captures mixed grid output to WAV file)
__attribute__((visibility("default"))) __attribute__((used))
int start_recording(const char* output_file_path);
__attribute__((visibility("default"))) __attribute__((used))
int stop_recording(void);
__attribute__((visibility("default"))) __attribute__((used))
int is_recording(void);
__attribute__((visibility("default"))) __attribute__((used))
uint64_t get_recording_duration(void);

// Diagnostic functions for performance monitoring
__attribute__((visibility("default"))) __attribute__((used))
int get_active_cell_node_count(void);
__attribute__((visibility("default"))) __attribute__((used))
int get_max_cell_node_count(void);

#ifdef __cplusplus
}
#endif

#endif // SEQUENCER_H 