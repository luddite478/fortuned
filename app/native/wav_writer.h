#ifndef SIMPLE_WAV_WRITER_H
#define SIMPLE_WAV_WRITER_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// Simple WAV file writer - no dependencies needed!
// Writes PCM float32 data to WAV file

typedef struct {
    FILE* file;
    uint32_t sample_rate;
    uint16_t num_channels;
    uint32_t data_chunk_size;
    long data_size_pos;  // Position in file where we'll write final size
} wav_writer;

// Open a WAV file for writing
// Returns 0 on success, -1 on error
int wav_open(wav_writer* writer, const char* filename, uint32_t sample_rate, uint16_t num_channels);

// Write float32 interleaved PCM frames to WAV file
// frames: pointer to float buffer (interleaved LRLRLR... for stereo)
// num_frames: number of frames to write (not samples - 1 frame = all channels)
// Returns number of frames written, or -1 on error
int wav_write_frames(wav_writer* writer, const float* frames, uint32_t num_frames);

// Close the WAV file and finalize the header
void wav_close(wav_writer* writer);

#ifdef __cplusplus
}
#endif

#endif // SIMPLE_WAV_WRITER_H



