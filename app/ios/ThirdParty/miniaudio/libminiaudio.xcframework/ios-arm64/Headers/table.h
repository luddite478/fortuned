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
#define MAX_SECTIONS 128

// Core cell data structure
typedef struct {
    int sample_slot;            // -1 = empty, 0-25 = sample index (A-Z)
    float volume;               // 0.0 to 1.0
    float pitch;                // 0.25 to 4.0 (2 octaves down/up)
} Cell;

// Section structure - each section can have different number of steps
typedef struct {
    int start_step;             // Starting step in the table
    int num_steps;              // Number of steps in this section
} Section;

// PublicTableState exposed to Flutter via FFI (read-only snapshot)
typedef struct {
    uint32_t version;               // even=stable, odd=writer in progress
    int sections_count;             // number of sections
    Cell* table_ptr;                // direct pointer to table base
    Section* sections_ptr;          // direct pointer to sections array
} PublicTableState;

// Table management functions
__attribute__((visibility("default"))) __attribute__((used))
void table_init(void);

__attribute__((visibility("default"))) __attribute__((used))
Cell* table_get_cell(int step, int col);

__attribute__((visibility("default"))) __attribute__((used))
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch);

__attribute__((visibility("default"))) __attribute__((used))
void table_clear_cell(int step, int col);

__attribute__((visibility("default"))) __attribute__((used))
void table_insert_step(int section_index, int at_step);

__attribute__((visibility("default"))) __attribute__((used))
void table_delete_step(int section_index, int at_step);



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
void table_set_section_step_count(int section_index, int steps);



// Return a stable pointer to the native PublicTableState struct
__attribute__((visibility("default"))) __attribute__((used))
const PublicTableState* table_get_state_ptr(void);

#ifdef __cplusplus
}
#endif

#endif // TABLE_H