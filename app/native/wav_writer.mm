#include "wav_writer.h"
#include <string.h>

// WAV file format structures
typedef struct {
    char chunk_id[4];      // "RIFF"
    uint32_t chunk_size;   // File size - 8
    char format[4];        // "WAVE"
} wav_riff_header;

typedef struct {
    char chunk_id[4];      // "fmt "
    uint32_t chunk_size;   // 16 for PCM
    uint16_t audio_format; // 1 = PCM int, 3 = PCM float
    uint16_t num_channels;
    uint32_t sample_rate;
    uint32_t byte_rate;    // sample_rate * num_channels * bytes_per_sample
    uint16_t block_align;  // num_channels * bytes_per_sample
    uint16_t bits_per_sample;
} wav_fmt_header;

typedef struct {
    char chunk_id[4];      // "data"
    uint32_t chunk_size;   // Number of bytes in data
} wav_data_header;

// Helper to write little-endian values
static void write_le_uint32(FILE* f, uint32_t val) {
    fputc(val & 0xFF, f);
    fputc((val >> 8) & 0xFF, f);
    fputc((val >> 16) & 0xFF, f);
    fputc((val >> 24) & 0xFF, f);
}

static void write_le_uint16(FILE* f, uint16_t val) {
    fputc(val & 0xFF, f);
    fputc((val >> 8) & 0xFF, f);
}

int wav_open(wav_writer* writer, const char* filename, uint32_t sample_rate, uint16_t num_channels) {
    if (!writer || !filename) return -1;
    
    memset(writer, 0, sizeof(wav_writer));
    
    writer->file = fopen(filename, "wb");
    if (!writer->file) return -1;
    
    writer->sample_rate = sample_rate;
    writer->num_channels = num_channels;
    writer->data_chunk_size = 0;
    
    // Write RIFF header
    fwrite("RIFF", 1, 4, writer->file);
    write_le_uint32(writer->file, 0);  // Placeholder, will update on close
    fwrite("WAVE", 1, 4, writer->file);
    
    // Write fmt chunk
    fwrite("fmt ", 1, 4, writer->file);
    write_le_uint32(writer->file, 16);  // Chunk size
    write_le_uint16(writer->file, 3);   // Audio format: 3 = IEEE float
    write_le_uint16(writer->file, num_channels);
    write_le_uint32(writer->file, sample_rate);
    write_le_uint32(writer->file, sample_rate * num_channels * 4);  // Byte rate
    write_le_uint16(writer->file, num_channels * 4);  // Block align
    write_le_uint16(writer->file, 32);  // Bits per sample (float32)
    
    // Write data chunk header
    fwrite("data", 1, 4, writer->file);
    writer->data_size_pos = ftell(writer->file);
    write_le_uint32(writer->file, 0);  // Placeholder, will update on close
    
    return 0;
}

int wav_write_frames(wav_writer* writer, const float* frames, uint32_t num_frames) {
    if (!writer || !writer->file || !frames) return -1;
    
    uint32_t num_samples = num_frames * writer->num_channels;
    
    // Write float samples (already in correct byte order for most systems)
    // Note: This assumes little-endian system. For big-endian, would need to swap bytes.
    size_t written = fwrite(frames, sizeof(float), num_samples, writer->file);
    
    if (written != num_samples) return -1;
    
    writer->data_chunk_size += num_samples * sizeof(float);
    
    return (int)num_frames;
}

void wav_close(wav_writer* writer) {
    if (!writer || !writer->file) return;
    
    // Update the data chunk size
    fseek(writer->file, writer->data_size_pos, SEEK_SET);
    write_le_uint32(writer->file, writer->data_chunk_size);
    
    // Update the RIFF chunk size (file size - 8)
    fseek(writer->file, 4, SEEK_SET);
    uint32_t riff_size = 36 + writer->data_chunk_size;  // 36 = size of headers before data
    write_le_uint32(writer->file, riff_size);
    
    fclose(writer->file);
    writer->file = NULL;
}

