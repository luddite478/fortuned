#include "table.h"
#include "undo_redo.h"
#include "sunvox_wrapper.h"  // For SunVox pattern sync
#include "playback.h"         // For switch_to_section
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <math.h>

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "TABLE"
#endif

// Global table state consolidated into a single struct
static TableState g_table_state; // zero-initialized

// Seqlock helper functions for unified state
static inline void state_write_begin() {
    g_table_state.version++; // odd = write in progress
}

static inline void state_write_end() {
    g_table_state.version++; // even = stable
}

// Helper to set a cell to default values
static inline void table_set_cell_defaults(Cell* cell) {
    if (!cell) return;
    cell->sample_slot = -1;
    cell->settings.volume = DEFAULT_CELL_VOLUME;
    cell->settings.pitch = DEFAULT_CELL_PITCH;
    cell->is_processing = 0;
}

// Initialize table with default values
void table_init(void) {
    prnt("🎵 [TABLE] Initializing table: %d x %d", MAX_SEQUENCER_STEPS, MAX_SEQUENCER_COLS);
    
    // Clear all cells
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            table_set_cell_defaults(&g_table_state.table[step][col]);
        }
    }
    
    g_table_state.sections_count = 1;
    g_table_state.sections[0].start_step = 0;
    g_table_state.sections[0].num_steps = DEFAULT_SECTION_STEPS;  // Default section size

    // Initialize layers metadata for all sections with default lengths
    for (int s = 0; s < MAX_SECTIONS; s++) {
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[s][l].len = MAX_COLS_PER_LAYER;
        }
    }

    // Initialize FFI-visible fields for unified state
    g_table_state.version = 0;
    g_table_state.table_ptr = &g_table_state.table[0][0];
    g_table_state.sections_ptr = &g_table_state.sections[0];
    g_table_state.layers_ptr = &g_table_state.layers[0][0];
    
    prnt("✅ [TABLE] Table initialized successfully");

    // Note: SunVox patterns will be created in playback_init() after SunVox is initialized
    // Do not seed undo/redo baseline here; a single baseline is recorded after all modules init
}

// Get pointer to cell (direct memory access for Flutter FFI)
Cell* table_get_cell(int step, int col) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS || col < 0 || col >= MAX_SEQUENCER_COLS) {
        prnt_err("❌ [TABLE] Cell access out of bounds: [%d, %d]", step, col);
        return NULL;
    }
    return &g_table_state.table[step][col];
}

// Set cell data and mark as changed
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    // Validate parameters
    if (sample_slot < -1 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [TABLE] Invalid sample_slot: %d", sample_slot);
        return;
    }
    
    // Update cell
    cell->sample_slot = sample_slot;
    cell->settings.volume = volume;
    cell->settings.pitch = pitch;
    cell->is_processing = 0;
    
    prnt("🎵 [TABLE] Set cell [%d, %d]: slot=%d, vol=%.2f, pitch=%.2f", 
         step, col, sample_slot, volume, pitch);

    // Sync cell to SunVox pattern
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set only volume/pitch settings for a cell
void table_set_cell_settings(int step, int col, float volume, float pitch, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;


    cell->settings.volume = volume;
    cell->settings.pitch = pitch;
    prnt("🎚️ [TABLE] Set settings [%d, %d]: vol=%.2f, pitch=%.2f", step, col, volume, pitch);

    // Sync cell to SunVox pattern
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set only sample slot for a cell
void table_set_cell_sample_slot(int step, int col, int sample_slot, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    if (sample_slot < -1 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [TABLE] Invalid sample_slot: %d", sample_slot);
        return;
    }
    cell->sample_slot = sample_slot;
    prnt("🎵 [TABLE] Set sample slot [%d, %d]: slot=%d", step, col, sample_slot);
    
    // Sync cell to SunVox pattern
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_sync_cell(step, col);
    }
    
    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Clear cell and mark as changed
void table_clear_cell(int step, int col, int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    table_set_cell_defaults(cell);
    
    prnt("🧹 [TABLE] Cleared cell [%d, %d]", step, col);

    // Sync cell to SunVox pattern
    if (sunvox_wrapper_is_initialized()) {
        sunvox_wrapper_sync_cell(step, col);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Insert step at given position
void table_insert_step(int section_index, int at_step, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_end = g_table_state.sections[section_index].start_step + g_table_state.sections[section_index].num_steps;
    
    if (at_step < 0 || at_step > section_end || section_end >= MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Cannot insert step at %d (section end: %d, max: %d)", 
                 at_step, section_end, MAX_SEQUENCER_STEPS);
        return;
    }
    // Mutate under seqlock
    state_write_begin();

    // Shift all rows down from insertion point
    for (int step = section_end; step > at_step; step--) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = g_table_state.table[step - 1][col];
        }
    }
    
    // Clear the new row
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        table_set_cell_defaults(&g_table_state.table[at_step][col]);
    }
    
    // Increase section length
    g_table_state.sections[section_index].num_steps++;

    state_write_end();
    
    prnt("➕ [TABLE] Inserted step at %d in section %d (section steps: %d)", at_step, section_index, g_table_state.sections[section_index].num_steps);

    // Recreate SunVox pattern with new size
    sunvox_wrapper_create_section_pattern(section_index, g_table_state.sections[section_index].num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Delete step at given position
void table_delete_step(int section_index, int at_step, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_start = g_table_state.sections[section_index].start_step;
    int section_end = section_start + g_table_state.sections[section_index].num_steps;
    
    if (at_step < section_start || at_step >= section_end || g_table_state.sections[section_index].num_steps <= 1) {
        prnt_err("❌ [TABLE] Cannot delete step at %d (section: %d-%d, steps: %d)", 
                 at_step, section_start, section_end-1, g_table_state.sections[section_index].num_steps);
        return;
    }
    // Mutate under seqlock
    state_write_begin();

    // Shift all rows up from deletion point
    for (int step = at_step; step < section_end - 1; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = g_table_state.table[step + 1][col];
        }
    }
    
    // Clear the last row in section
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        table_set_cell_defaults(&g_table_state.table[section_end - 1][col]);
    }
    
    // Decrease section length
    g_table_state.sections[section_index].num_steps--;

    state_write_end();
    
    prnt("➖ [TABLE] Deleted step at %d in section %d (section steps: %d)", at_step, section_index, g_table_state.sections[section_index].num_steps);

    // Recreate SunVox pattern with new size
    sunvox_wrapper_create_section_pattern(section_index, g_table_state.sections[section_index].num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

int table_get_max_steps(void) {
    return MAX_SEQUENCER_STEPS;
}

int table_get_max_cols(void) {
    return MAX_SEQUENCER_COLS;
}

int table_get_sections_count(void) {
    return g_table_state.sections_count;
}

// Helper to calculate which section a step belongs to
int table_get_section_at_step(int step) {
    for (int i = 0; i < g_table_state.sections_count; i++) {
        int start = g_table_state.sections[i].start_step;
        int end = start + g_table_state.sections[i].num_steps;
        if (step >= start && step < end) {
            return i;
        }
    }
    return -1; // Not in any section
}

int table_get_section_start_step(int section_index) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        return 0;
    }
    return g_table_state.sections[section_index].start_step;
}

int table_get_section_step_count(int section_index) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        return DEFAULT_SECTION_STEPS; // Default section size
    }
    return g_table_state.sections[section_index].num_steps;
}

// Section management functions
void table_set_section_step_count(int section_index, int steps, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        state_write_begin();
        g_table_state.sections[section_index].num_steps = steps;
        state_write_end();
        
        prnt("📏 [TABLE] Set section %d step count to %d", section_index, steps);
        
        // Recreate SunVox pattern with new size
        sunvox_wrapper_create_section_pattern(section_index, steps);
        
        if (undo_record) {
            UndoRedoManager_record();
        }
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}

// Append a new section; if copy_from_section >= 0, copy its cells and step count; otherwise use provided steps
void table_append_section(int steps, int copy_from_section, int undo_record) {
    if (g_table_state.sections_count >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Cannot append section: max sections reached");
        return;
    }

    int new_index = g_table_state.sections_count;
    int new_steps = steps;
    if (copy_from_section >= 0 && copy_from_section < g_table_state.sections_count) {
        new_steps = g_table_state.sections[copy_from_section].num_steps;
    }
    if (new_steps <= 0 || new_steps > MAX_SEQUENCER_STEPS) {
        new_steps = DEFAULT_SECTION_STEPS; // fallback
    }

    // Calculate start step for new section at the end of current table
    int start = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        start += g_table_state.sections[i].num_steps;
    }

    // Initialize section metadata
    g_table_state.sections[new_index].start_step = start;
    g_table_state.sections[new_index].num_steps = new_steps;

    // Initialize layers for new section to default lengths
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_table_state.layers[new_index][l].len = MAX_COLS_PER_LAYER;
    }

    // Copy cells if requested
    if (copy_from_section >= 0 && copy_from_section < g_table_state.sections_count) {
        int src_start = g_table_state.sections[copy_from_section].start_step;
        for (int step = 0; step < new_steps; step++) {
            for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                g_table_state.table[start + step][col] = g_table_state.table[src_start + step][col];
            }
        }
    } else {
        // Clear new section cells
        for (int step = 0; step < new_steps; step++) {
            for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
                table_set_cell_defaults(&g_table_state.table[start + step][col]);
            }
        }
    }

    state_write_begin();

    g_table_state.sections_count++;

    state_write_end();

    prnt("🆕 [TABLE] Appended section %d (steps=%d, start=%d)", new_index, new_steps, start);
    
    // Check if playback is active before we modify anything
    const PlaybackState* pb_state = playback_get_state_ptr();
    int was_playing = pb_state ? pb_state->is_playing : 0;
    int bpm = pb_state ? pb_state->bpm : 120;
    
    // Stop playback first to prevent audio artifacts during section creation
    if (was_playing) {
        playback_stop();
    }
    
    // Create SunVox pattern for this section (won't restart playback since we stopped it)
    sunvox_wrapper_create_section_pattern(new_index, new_steps);
    
    // Switch to the new section (this will set up timeline and position)
    switch_to_section(new_index);
    
    // Manually restart playback if it was active before
    if (was_playing) {
        int section_start_step = table_get_section_start_step(new_index);
        playback_start(bpm, section_start_step);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Delete a section by index; shifts subsequent sections up and compacts start_step
void table_delete_section(int section_index, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    if (g_table_state.sections_count <= 1) {
        prnt_err("❌ [TABLE] Cannot delete the last remaining section");
        return;
    }

    int remove_start = g_table_state.sections[section_index].start_step;
    int remove_steps = g_table_state.sections[section_index].num_steps;
    int total_steps = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) total_steps += g_table_state.sections[i].num_steps;

    state_write_begin();

    // Shift table cells up to cover removed section range
    for (int step = remove_start; step < total_steps - remove_steps; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table_state.table[step][col] = g_table_state.table[step + remove_steps][col];
        }
    }
    // Clear trailing cells
    for (int step = total_steps - remove_steps; step < total_steps; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            table_set_cell_defaults(&g_table_state.table[step][col]);
        }
    }

    // Shift sections metadata down and recompute start_step chain
    for (int i = section_index; i < g_table_state.sections_count - 1; i++) {
        g_table_state.sections[i] = g_table_state.sections[i + 1];
        // Shift layers row along with section metadata
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[i][l] = g_table_state.layers[i + 1][l];
        }
    }
    g_table_state.sections_count--;
    int cursor = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        g_table_state.sections[i].start_step = cursor;
        cursor += g_table_state.sections[i].num_steps;
    }
    // Reset trailing layers row to defaults
    for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
        g_table_state.layers[g_table_state.sections_count][l].len = MAX_COLS_PER_LAYER;
    }

    state_write_end();

    prnt("🗑️ [TABLE] Deleted section %d (steps=%d)", section_index, remove_steps);
    
    // Remove SunVox pattern (it was at the end before shift)
    sunvox_wrapper_remove_section_pattern(g_table_state.sections_count); // old last index
    
    // Recreate all section patterns since they shifted
    for (int i = 0; i < g_table_state.sections_count; i++) {
        sunvox_wrapper_create_section_pattern(i, g_table_state.sections[i].num_steps);
    }

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set section metadata directly (start_step, num_steps)
void table_set_section(int index, int start_step, int num_steps, int undo_record) {
    if (index < 0 || index >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Invalid section index: %d", index);
        return;
    }
    if (num_steps <= 0 || num_steps > MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Invalid section steps: %d", num_steps);
        return;
    }
    if (start_step < 0 || start_step >= MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Invalid section start: %d", start_step);
        return;
    }

    state_write_begin();
    g_table_state.sections[index].start_step = start_step;
    g_table_state.sections[index].num_steps = num_steps;
    state_write_end();

    prnt("[TABLE] Set section %d (start=%d, steps=%d)", index, start_step, num_steps);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Set per-section layer length
void table_set_layer_len(int section_index, int layer_index, int len, int undo_record) {
    if (section_index < 0 || section_index >= MAX_SECTIONS) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    if (layer_index < 0 || layer_index >= MAX_LAYERS_PER_SECTION) {
        prnt_err("❌ [TABLE] Invalid layer index: %d", layer_index);
        return;
    }
    if (len < 0 || len > MAX_SEQUENCER_COLS) {
        prnt_err("❌ [TABLE] Invalid layer len: %d", len);
        return;
    }

    state_write_begin();
    g_table_state.layers[section_index][layer_index].len = len;
    state_write_end();

    prnt("[TABLE] Set layer len section=%d layer=%d len=%d", section_index, layer_index, len);

    if (undo_record) {
        UndoRedoManager_record();
    }
}

// Return pointer to unified state for Flutter FFI access
const TableState* table_get_state_ptr(void) { return &g_table_state; }

// Expose live state for read
const TableState* table_state_get_ptr(void) { return &g_table_state; }

// Apply a native snapshot used by Undo/Redo
void table_apply_state(const TableState* snap) {
    state_write_begin();

    // Copy full state
    g_table_state.sections_count = snap->sections_count;
    if (g_table_state.sections_count < 0) g_table_state.sections_count = 0;
    if (g_table_state.sections_count > MAX_SECTIONS) g_table_state.sections_count = MAX_SECTIONS;
    // table
    for (int r = 0; r < MAX_SEQUENCER_STEPS; r++) {
        for (int c = 0; c < MAX_SEQUENCER_COLS; c++) {
            g_table_state.table[r][c] = snap->table[r][c];
        }
    }
    // sections
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_table_state.sections[i] = snap->sections[i];
    }
    // layers
    for (int s = 0; s < MAX_SECTIONS; s++) {
        for (int l = 0; l < MAX_LAYERS_PER_SECTION; l++) {
            g_table_state.layers[s][l] = snap->layers[s][l];
        }
    }

    state_write_end();
    prnt("📥 [TABLE] Applied TableState (sections=%d)", g_table_state.sections_count);
}
