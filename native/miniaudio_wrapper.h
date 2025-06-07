#ifndef MINIAUDIO_WRAPPER_H
#define MINIAUDIO_WRAPPER_H

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
void miniaudio_stop_all_sounds(void);

// Check if engine is initialized
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_is_initialized(void);

// Cleanup the miniaudio engine
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // MINIAUDIO_WRAPPER_H 