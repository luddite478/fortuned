#ifndef PLAYBACK_H
#define PLAYBACK_H

#include <stdint.h>
#include "table.h"

#ifdef __cplusplus
extern "C" {
#endif

// Constants for playback
#define SAMPLE_RATE 48000
#define CHANNELS 2
#define VOLUME_RISE_TIME_MS 6.0f      // 6ms fade-in time
#define VOLUME_FALL_TIME_MS 12.0f     // 12ms fade-out time  
#define VOLUME_THRESHOLD 0.0001f      // Convergence threshold

// A/B Node structure for smooth switching
typedef struct {
    int column;
    int index;                      // 0=A, 1=B
    int node_initialized;           // 1 when miniaudio node is created
    int sample_slot;                // Which sample this node plays (-1 = none)
    
    // miniaudio components
    void* decoder;                  // ma_decoder* (cast to void* for C compatibility)
    void* node;                     // ma_data_source_node* (cast to void* for C compatibility)
    
    // Volume smoothing
    float user_volume;              // User volume setting (from cell)
    float current_volume;           // Real actual volume (for smoothing)
    float target_volume;            // Target volume we're smoothing towards
    float volume_rise_coeff;        // Smoothing coefficient for fade-in
    float volume_fall_coeff;        // Smoothing coefficient for fade-out
    
    uint64_t id;                    // Unique identifier
} ColumnNode;

// Column management (2 nodes per column)
typedef struct {
    ColumnNode nodes[2];            // A and B nodes
    int active_node;                // 0=A, 1=B, -1=none
    int next_node;                  // Which node to use next
} ColumnNodes;

// Playback region
typedef struct {
    int start;
    int end;                        // exclusive
} PlaybackRegion;

// PublicPlaybackState exposed to Flutter via FFI (read-only snapshot)
typedef struct {
    uint32_t version;               // even=stable, odd=writer in progress
    int is_playing;                 // 0/1
    int current_step;               // current sequencer step
    int bpm;                        // current BPM
    int region_start;               // inclusive start of playback region
    int region_end;                 // exclusive end of playback region
    int song_mode;                  // 0=loop, 1=song
} PublicPlaybackState;

// Playback initialization and cleanup
__attribute__((visibility("default"))) __attribute__((used))
int playback_init(void);

__attribute__((visibility("default"))) __attribute__((used))
void playback_cleanup(void);

// Playback control
__attribute__((visibility("default"))) __attribute__((used))
int playback_start(int bpm, int start_step);

__attribute__((visibility("default"))) __attribute__((used))
void playback_stop(void);

__attribute__((visibility("default"))) __attribute__((used))
int playback_is_playing(void);

// Playback settings
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_bpm(int bpm);

__attribute__((visibility("default"))) __attribute__((used))
int playback_get_bpm(void);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_region(int start, int end);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_mode(int song_mode);

__attribute__((visibility("default"))) __attribute__((used))
int playback_get_current_step(void);

// Return a stable pointer to the native PublicPlaybackState struct
__attribute__((visibility("default"))) __attribute__((used))
const PublicPlaybackState* playback_get_state_ptr(void);

// Sample bank functions (forward declarations)
__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_load(int slot, const char* file_path);

__attribute__((visibility("default"))) __attribute__((used))
void sample_bank_unload(int slot);

__attribute__((visibility("default"))) __attribute__((used))
int sample_bank_is_loaded(int slot);

__attribute__((visibility("default"))) __attribute__((used))
const char* sample_bank_get_file_path(int slot);

#ifdef __cplusplus
}
#endif

#endif // PLAYBACK_H
