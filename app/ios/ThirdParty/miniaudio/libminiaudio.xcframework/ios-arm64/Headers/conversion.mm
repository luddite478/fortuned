#include "conversion.h"

// Platform-specific includes and definitions
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "NIYYA_CONVERSION"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "NIYYA_CONVERSION"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "NIYYA_CONVERSION"
#endif

// Include all standard headers that LAME needs
#include <stdio.h>
#include <stdlib.h>    // malloc, free, calloc, exit
#include <string.h>    // memset, strlen, strcpy, etc.
#include <strings.h>   // bcopy on macOS/BSD
#include <memory.h>    // memory functions
#include <unistd.h>    // POSIX functions
#include <stdint.h>    // integer types
#include <math.h>      // math functions

// Define missing functions for iOS/macOS compatibility
#ifndef bcopy
#define bcopy(src, dst, len) memmove(dst, src, len)
#endif

#include "lame.h"

// Conversion state
static int g_conversion_initialized = 0;

// WAV file header structure
typedef struct {
    char riff[4];           // "RIFF"
    uint32_t chunk_size;    // File size - 8
    char wave[4];           // "WAVE"
    char fmt[4];            // "fmt "
    uint32_t fmt_chunk_size; // Usually 16
    uint16_t audio_format;   // 1 = PCM, 3 = IEEE float
    uint16_t num_channels;   // 1 = mono, 2 = stereo
    uint32_t sample_rate;    // Sample rate
    uint32_t byte_rate;      // Bytes per second
    uint16_t block_align;    // Bytes per sample frame
    uint16_t bits_per_sample; // Bits per sample
    char data[4];           // "data"
    uint32_t data_size;     // Data chunk size
} wav_header_t;

int conversion_init(void) {
    if (g_conversion_initialized) {
        prnt("✅ [CONVERSION] Already initialized");
        return 0;
    }
    
    // Test LAME availability by creating and destroying an encoder
    lame_t test_lame = lame_init();
    if (!test_lame) {
        prnt_err("🔴 [CONVERSION] Failed to initialize test encoder");
        return -1;
    }
    
    lame_close(test_lame);
    g_conversion_initialized = 1;
    
    prnt("✅ [CONVERSION] Initialized successfully");
    return 0;
}

int conversion_convert_wav_to_mp3(const char* wav_path, const char* mp3_path, int bitrate_kbps) {
    if (!g_conversion_initialized) {
        prnt_err("🔴 [CONVERSION] Not initialized. Call conversion_init() first");
        return -1;
    }
    
    if (!wav_path || !mp3_path) {
        prnt_err("🔴 [CONVERSION] Invalid file paths");
        return -1;
    }
    
    prnt("🎵 [CONVERSION] Starting conversion: %s -> %s at %d kbps", wav_path, mp3_path, bitrate_kbps);
    
    // Open input WAV file
    FILE* wav_file = fopen(wav_path, "rb");
    if (!wav_file) {
        prnt_err("🔴 [CONVERSION] Failed to open WAV file: %s", wav_path);
        return -1;
    }
    
    // Read and parse WAV header
    wav_header_t header;
    size_t read_size = fread(&header, 1, sizeof(wav_header_t), wav_file);
    if (read_size != sizeof(wav_header_t)) {
        prnt_err("🔴 [CONVERSION] Failed to read WAV header");
        fclose(wav_file);
        return -1;
    }
    
    // Validate WAV file
    if (memcmp(header.riff, "RIFF", 4) != 0 || memcmp(header.wave, "WAVE", 4) != 0) {
        prnt_err("🔴 [CONVERSION] Invalid WAV file format");
        fclose(wav_file);
        return -1;
    }
    
    // Log WAV file properties
    prnt("📊 [WAV] Format: %d, Channels: %d, Sample Rate: %d Hz, Bits: %d", 
         header.audio_format, header.num_channels, header.sample_rate, header.bits_per_sample);
    
    // Open output MP3 file
    FILE* mp3_file = fopen(mp3_path, "wb");
    if (!mp3_file) {
        prnt_err("🔴 [CONVERSION] Failed to create MP3 file: %s", mp3_path);
        fclose(wav_file);
        return -1;
    }
    
    // Initialize LAME encoder
    lame_t lame = lame_init();
    if (!lame) {
        prnt_err("🔴 [CONVERSION] Failed to initialize encoder");
        fclose(wav_file);
        fclose(mp3_file);
        return -1;
    }
    
    // Configure LAME encoder with WAV file properties
    lame_set_in_samplerate(lame, header.sample_rate);
    lame_set_num_channels(lame, header.num_channels);
    lame_set_brate(lame, bitrate_kbps);
    
    // Set mode based on channel count
    if (header.num_channels == 1) {
        lame_set_mode(lame, MONO);
    } else {
        lame_set_mode(lame, STEREO);
    }
    
    lame_set_quality(lame, 2); // 0=best (very slow), 9=worst, 2=high quality
    lame_set_bWriteVbrTag(lame, 0); // Disable VBR tag for CBR
    
    if (lame_init_params(lame) < 0) {
        prnt_err("🔴 [CONVERSION] Failed to initialize encoder parameters");
        lame_close(lame);
        fclose(wav_file);
        fclose(mp3_file);
        return -1;
    }
    
    // Calculate buffer sizes based on WAV format
    const int FRAMES_PER_BUFFER = 4096;
    const int bytes_per_frame = (header.bits_per_sample / 8) * header.num_channels;
    const int wav_buffer_size = FRAMES_PER_BUFFER * bytes_per_frame;
    const int MP3_BUFFER_SIZE = 8192;
    
    // Allocate buffers
    void* wav_buffer = malloc(wav_buffer_size);
    short int* pcm_buffer = (short int*)malloc(FRAMES_PER_BUFFER * header.num_channels * sizeof(short int));
    unsigned char* mp3_buffer = (unsigned char*)malloc(MP3_BUFFER_SIZE);
    
    if (!wav_buffer || !pcm_buffer || !mp3_buffer) {
        prnt_err("🔴 [CONVERSION] Failed to allocate buffers");
        free(wav_buffer);
        free(pcm_buffer);
        free(mp3_buffer);
        lame_close(lame);
        fclose(wav_file);
        fclose(mp3_file);
        return -1;
    }
    
    size_t total_samples_processed = 0;
    int read_frames = 0;
    int write_bytes = 0;
    
    // Convert WAV to MP3
    do {
        // Read WAV data
        size_t bytes_read = fread(wav_buffer, 1, wav_buffer_size, wav_file);
        read_frames = (int)(bytes_read / bytes_per_frame);
        
        if (read_frames == 0) {
            // Flush remaining data
            write_bytes = lame_encode_flush(lame, mp3_buffer, MP3_BUFFER_SIZE);
        } else {
            // Convert audio format to 16-bit signed int for LAME
            if (header.audio_format == 3 && header.bits_per_sample == 32) {
                // IEEE float (32-bit) - what miniaudio outputs
                float* float_samples = (float*)wav_buffer;
                for (int i = 0; i < read_frames * header.num_channels; i++) {
                    // Convert float (-1.0 to 1.0) to 16-bit signed int (-32768 to 32767)
                    float sample = float_samples[i];
                    if (sample > 1.0f) sample = 1.0f;
                    if (sample < -1.0f) sample = -1.0f;
                    pcm_buffer[i] = (short int)(sample * 32767.0f);
                }
            } else if (header.audio_format == 1 && header.bits_per_sample == 16) {
                // Already 16-bit signed int - direct copy
                memcpy(pcm_buffer, wav_buffer, read_frames * header.num_channels * sizeof(short int));
            } else {
                prnt_err("🔴 [CONVERSION] Unsupported WAV format: format=%d, bits=%d", 
                         header.audio_format, header.bits_per_sample);
                break;
            }
            
            // Encode to MP3
            if (header.num_channels == 1) {
                write_bytes = lame_encode_buffer(lame, pcm_buffer, NULL, read_frames, mp3_buffer, MP3_BUFFER_SIZE);
            } else {
                write_bytes = lame_encode_buffer_interleaved(lame, pcm_buffer, read_frames, mp3_buffer, MP3_BUFFER_SIZE);
            }
            
            total_samples_processed += read_frames;
        }
        
        if (write_bytes < 0) {
            prnt_err("🔴 [CONVERSION] Encoding error: %d", write_bytes);
            break;
        }
        
        if (write_bytes > 0) {
            size_t written = fwrite(mp3_buffer, 1, (size_t)write_bytes, mp3_file);
            if (written != (size_t)write_bytes) {
                prnt_err("🔴 [CONVERSION] Failed to write MP3 data");
                break;
            }
        }
        
    } while (read_frames != 0);
    
    // Cleanup
    free(wav_buffer);
    free(pcm_buffer);
    free(mp3_buffer);
    lame_close(lame);
    fclose(wav_file);
    fclose(mp3_file);
    
    // Calculate duration
    double duration_seconds = (double)total_samples_processed / header.sample_rate;
    
    prnt("✅ [CONVERSION] Conversion completed successfully");
    prnt("📊 [CONVERSION] Processed %zu samples (%.2f seconds) at %d Hz", 
         total_samples_processed, duration_seconds, header.sample_rate);
    
    return 0;
}

int conversion_get_file_size(const char* file_path) {
    if (!file_path) return -1;
    
    FILE* file = fopen(file_path, "rb");
    if (!file) return -1;
    
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fclose(file);
    
    return (int)size;
}

int conversion_is_available(void) {
    return g_conversion_initialized ? 1 : 0;
}

const char* conversion_get_version(void) {
    return get_lame_version();
}

void conversion_cleanup(void) {
    if (g_conversion_initialized) {
        g_conversion_initialized = 0;
        prnt("✅ [CONVERSION] Cleanup completed");
    }
} 