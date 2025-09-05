#ifndef TABLE_H
#define TABLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define MAX_SEQUENCER_STEPS 2048
#define MAX_SEQUENCER_COLS 16
#define MAX_SAMPLE_SLOTS 26
#define MAX_SECTIONS 64
#define DEFAULT_SECTION_STEPS 16
// Layers (per section)
#define MAX_LAYERS_PER_SECTION 4
#define MAX_COLS_PER_LAYER 4

// Cell audio settings
typedef struct {
    float volume;               // 0.0 to 1.0
    float pitch;                // 0.25 to 4.0 (2 octaves down/up)
} CellSettings;

// Core cell data structure
typedef struct {
    int sample_slot;            // -1 = empty, 0-25 = sample index (A-Z)
    CellSettings settings;      // audio settings
} Cell;

// Section structure - each section can have different number of steps
typedef struct {
    int start_step;             // Starting step in the table
    int num_steps;              // Number of steps in this section
} Section;

// Layer structure - per-section fixed number of layers with length (columns count)
typedef struct {
    int len;                    // Number of columns in this layer (default MAX_COLS_PER_LAYER)
} Layer;

// Single live table state (authoritative). The first fields are read by Flutter via FFI.
// Keep these header fields at the top to allow Dart to map them as a prefix view.
typedef struct {
    // Seqlock version (even=stable, odd=writer in progress)
    uint32_t version;

    // Scalars visible to Flutter
    int sections_count;             // number of sections

    // Pointer views to internal arrays (assigned in table_init)
    Cell* table_ptr;                // &table[0][0]
    Section* sections_ptr;          // &sections[0]
    Layer* layers_ptr;              // &layers[0][0]

    // Canonical storage (arrays are static, pointers above reference these)
    Cell table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS];
    Section sections[MAX_SECTIONS];
    Layer layers[MAX_SECTIONS][MAX_LAYERS_PER_SECTION];
} TableState;

// Table management functions
__attribute__((visibility("default"))) __attribute__((used))
void table_init(void);

__attribute__((visibility("default"))) __attribute__((used))
Cell* table_get_cell(int step, int col);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch, int undo_record);

// New: set only cell settings (volume/pitch)
__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell_settings(int step, int col, float volume, float pitch, int undo_record);

// New: set only cell sample slot
__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell_sample_slot(int step, int col, int sample_slot, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_clear_cell(int step, int col, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_insert_step(int section_index, int at_step, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_delete_step(int section_index, int at_step, int undo_record);

// Single setters to be used for batch updates from Flutter side
__attribute__((visibility("default"))) __attribute__((used))
void table_set_section(int index, int start_step, int num_steps, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_layer_len(int section_index, int layer_index, int len, int undo_record);


// Getters for table dimensions
__attribute__((visibility("default"))) __attribute__((used))
int table_get_max_steps(void);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_max_cols(void);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_sections_count(void);

// Section management
__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_start_step(int section_index);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_step_count(int section_index);

__attribute__((visibility("default"))) __attribute__((used))
int table_get_section_at_step(int step);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_section_step_count(int section_index, int steps, int undo_record);


// Section append/delete
__attribute__((visibility("default"))) __attribute__((used))
void table_append_section(int steps, int copy_from_section, int undo_record);

__attribute__((visibility("default"))) __attribute__((used))
void table_delete_section(int section_index, int undo_record);

// Return a stable pointer to the native TableState (prefix-mapped by Dart)
__attribute__((visibility("default"))) __attribute__((used))
const TableState* table_get_state_ptr(void);

// Accessor for full live state (read-only; do not mutate from Dart)
__attribute__((visibility("default"))) __attribute__((used))
const TableState* table_state_get_ptr(void);

// Apply a full table state (used by Undo/Redo and imports)
__attribute__((visibility("default"))) __attribute__((used))
void table_apply_state(const TableState* state);

#ifdef __cplusplus
}
#endif

#endif // TABLE_H