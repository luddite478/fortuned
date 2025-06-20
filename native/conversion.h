#ifndef CONVERSION_H
#define CONVERSION_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize conversion library
__attribute__((visibility("default"))) __attribute__((used))
int conversion_init(void);

// Convert WAV file to MP3 with specified bitrate
__attribute__((visibility("default"))) __attribute__((used))
int conversion_convert_wav_to_mp3(const char* wav_path, const char* mp3_path, int bitrate_kbps);

// Get file size in bytes
__attribute__((visibility("default"))) __attribute__((used))
int conversion_get_file_size(const char* file_path);

// Check if conversion library is available
__attribute__((visibility("default"))) __attribute__((used))
int conversion_is_available(void);

// Get conversion library version string
__attribute__((visibility("default"))) __attribute__((used))
const char* conversion_get_version(void);

// Cleanup conversion resources
__attribute__((visibility("default"))) __attribute__((used))
void conversion_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // CONVERSION_H 