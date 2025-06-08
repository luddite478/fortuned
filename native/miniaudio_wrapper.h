#ifndef MINIAUDIO_WRAPPER_H
#define MINIAUDIO_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the miniaudio engine
int miniaudio_init(void);

// Play a sound from a file
int miniaudio_play_sound(const char* file_path);

// Load a sound into memory
int miniaudio_load_sound(const char* file_path);

// Play a previously loaded sound
int miniaudio_play_loaded_sound(void);

// Stop all currently playing sounds
void miniaudio_stop_all_sounds(void);

// Check if engine is initialized
int miniaudio_is_initialized(void);

// Get current audio route info (for debugging Bluetooth connectivity)
void miniaudio_log_audio_route(void);

// Manually reconfigure audio session (for testing)
int miniaudio_reconfigure_audio_session(void);

// Cleanup the miniaudio engine
void miniaudio_cleanup(void);

// MAX number of simultaneous playback slots
#define MINIAUDIO_MAX_SLOTS 8

// Returns the number of available playback slots (always MINIAUDIO_MAX_SLOTS)
int miniaudio_get_slot_count(void);

// Loads a sound into the given slot. When loadToMemory == 1 the file will be
// fully decoded into memory for lowest-latency playback. When 0 the file will
// be streamed from disk.
int miniaudio_load_sound_to_slot(int slot, const char* file_path, int loadToMemory);

// Returns 1 if the slot successfully has a sound loaded, 0 otherwise.
int miniaudio_is_slot_loaded(int slot);

// Starts playback of the sound in the given slot. The sound is mixed together
// with any other playing slots.
int miniaudio_play_slot(int slot);

// Stops playback of the sound in the given slot.
void miniaudio_stop_slot(int slot);

// Unloads the sound from the given slot and frees all associated memory.
void miniaudio_unload_slot(int slot);

#ifdef __cplusplus
}
#endif

#endif // MINIAUDIO_WRAPPER_H 