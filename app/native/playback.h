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
#define DEFAULT_SECTION_LOOPS 4
#define MIN_SECTION_LOOPS 1
#define MAX_SECTION_LOOPS 1024
#define MA_NODES_PER_COLUMN 2
#define MIN_BPM 1
#define MAX_BPM 300

// A/B Node structure for smooth switching
typedef struct {
    int column;
    int index;                      // 0=A, 1=B
    int node_initialized;           // 1 when miniaudio node is created
    int sample_slot;                // Which sample this node plays (-1 = none)
    
    // miniaudio components
    void* decoder;                  // ma_decoder* (cast to void* for C compatibility)
    void* node;                     // ma_data_source_node* (cast to void* for C compatibility)
    void* pitch_ds;                 // ma_pitch_data_source* (cast to void*)
    int pitch_ds_initialized;       // 1 when pitch data source is initialized
    float pitch;                    // Current pitch ratio
    
    // Volume smoothing
    float user_volume;              // User volume setting (from cell)
    float current_volume;           // Real actual volume (for smoothing)
    float target_volume;            // Target volume we're smoothing towards
    float volume_rise_coeff;        // Smoothing coefficient for fade-in
    float volume_fall_coeff;        // Smoothing coefficient for fade-out
    
    uint64_t id;                    // Unique identifier
} MAColumnNode;

// Column management (2 nodes per column)
typedef struct {
    MAColumnNode nodes[2];          // A and B nodes
    int active_node;                // 0=A, 1=B, -1=none
    int next_node;                  // Which node to use next
} MAColumnNodes;

// Playback region
// typedef struct {
//     int start;
//     int end;                        // exclusive
// } PlaybackRegion;

// Single live playback state (authoritative)
typedef struct {
    // FFI-visible prefix (read directly by Dart)
    uint32_t version;               // even=stable, odd=writer in progress
    int is_playing;                 // 0/1
    int current_step;               // current sequencer step
    int bpm;                        // current BPM
    int region_start;               // inclusive start of playback region
    int region_end;                 // exclusive end of playback region
    int song_mode;                  // 0=loop, 1=song
    int* sections_loops_num;        // &sections_loops_num_storage[0]
    int current_section;            // current section being played
    int current_section_loop;       // current loop within section (0-based)

    // Canonical storage
    int sections_loops_num_storage[MAX_SECTIONS];
} PlaybackState;

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

// Playback settings
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_bpm(int bpm);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_region(int start, int end);

__attribute__((visibility("default"))) __attribute__((used))
void playback_set_mode(int song_mode);

// Section loops management
__attribute__((visibility("default"))) __attribute__((used))
void playback_set_section_loops_num(int section, int loops);

// Section switching helper (stops and restarts playback at section start if needed)
__attribute__((visibility("default"))) __attribute__((used))
void switch_to_section(int section_index);

// Return a stable pointer to the native PlaybackState struct (prefix-mapped)
__attribute__((visibility("default"))) __attribute__((used))
const PlaybackState* playback_get_state_ptr(void);

// Accessor for full live playback state (snapshot-friendly)
__attribute__((visibility("default"))) __attribute__((used))
const PlaybackState* playback_state_get_ptr(void);

// Unified state API
__attribute__((visibility("default"))) __attribute__((used))
void playback_apply_state(const PlaybackState* state);

// Components-based apply removed in favor of unified state snapshot

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
