#ifndef LAME_WRAPPER_H
#define LAME_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize LAME library
__attribute__((visibility("default"))) __attribute__((used))
int lame_wrapper_init(void);

// Convert WAV file to MP3 with specified bitrate
__attribute__((visibility("default"))) __attribute__((used))
int lame_wrapper_convert_wav_to_mp3(const char* wav_path, const char* mp3_path, int bitrate_kbps);

// Get file size in bytes
__attribute__((visibility("default"))) __attribute__((used))
int lame_wrapper_get_file_size(const char* file_path);

// Check if LAME is available
__attribute__((visibility("default"))) __attribute__((used))
int lame_wrapper_is_available(void);

// Get LAME version string
__attribute__((visibility("default"))) __attribute__((used))
const char* lame_wrapper_get_version(void);

// Cleanup LAME resources
__attribute__((visibility("default"))) __attribute__((used))
void lame_wrapper_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // LAME_WRAPPER_H 