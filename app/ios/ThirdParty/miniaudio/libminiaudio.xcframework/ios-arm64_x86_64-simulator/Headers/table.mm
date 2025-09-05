#include "table.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

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

// Global table state - static arrays with MAX sizes
static Cell g_table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS];
static int g_sections_count = 1;        // Number of sections
static Section g_sections[MAX_SECTIONS]; // Section definitions

// Public state exposed to Flutter (with seqlock)
static PublicTableState g_public_state = {0};

// Seqlock helper functions (matching playback.mm pattern)
static inline void public_state_write_begin() {
    g_public_state.version++; // odd = write in progress
}

static inline void public_state_write_end() {
    g_public_state.version++; // even = stable
}

static inline void public_state_update() {
    g_public_state.sections_count = g_sections_count;
    g_public_state.table_ptr = &g_table[0][0];      // Base pointer to table
    g_public_state.sections_ptr = &g_sections[0];   // Base pointer to sections
}

// Initialize table with default values
void table_init(void) {
    prnt("🎵 [TABLE] Initializing table: %d x %d", MAX_SEQUENCER_STEPS, MAX_SEQUENCER_COLS);
    
    // Clear all cells
    for (int step = 0; step < MAX_SEQUENCER_STEPS; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table[step][col].sample_slot = -1;        // Empty
            g_table[step][col].volume = 1.0f;           // Full volume
            g_table[step][col].pitch = 1.0f;            // Normal pitch
        }
    }
    
    // Initialize default section
    g_sections[0].start_step = 0;
    g_sections[0].num_steps = 16;  // Default section size
    
    // Initialize exposed table state snapshot
    g_public_state.version = 0;
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
    
    prnt("✅ [TABLE] Table initialized successfully");
}

// Get pointer to cell (direct memory access for Flutter FFI)
Cell* table_get_cell(int step, int col) {
    if (step < 0 || step >= MAX_SEQUENCER_STEPS || col < 0 || col >= MAX_SEQUENCER_COLS) {
        prnt_err("❌ [TABLE] Cell access out of bounds: [%d, %d]", step, col);
        return NULL;
    }
    return &g_table[step][col];
}

// Set cell data and mark as changed
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    // Validate parameters
    if (sample_slot < -1 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [TABLE] Invalid sample_slot: %d", sample_slot);
        return;
    }
    if (volume < 0.0f || volume > 1.0f) {
        prnt_err("❌ [TABLE] Invalid volume: %f", volume);
        return;
    }
    if (pitch < 0.25f || pitch > 4.0f) {
        prnt_err("❌ [TABLE] Invalid pitch: %f", pitch);
        return;
    }
    
    // Update cell
    cell->sample_slot = sample_slot;
    cell->volume = volume;
    cell->pitch = pitch;
    
    prnt("🎵 [TABLE] Set cell [%d, %d]: slot=%d, vol=%.2f, pitch=%.2f", 
         step, col, sample_slot, volume, pitch);
}

// Clear cell and mark as changed
void table_clear_cell(int step, int col) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    cell->sample_slot = -1;
    cell->volume = 1.0f;
    cell->pitch = 1.0f;
    
    prnt("🧹 [TABLE] Cleared cell [%d, %d]", step, col);
}

// Insert step at given position
void table_insert_step(int section_index, int at_step) {
    if (section_index < 0 || section_index >= g_sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_end = g_sections[section_index].start_step + g_sections[section_index].num_steps;
    
    if (at_step < 0 || at_step > section_end || section_end >= MAX_SEQUENCER_STEPS) {
        prnt_err("❌ [TABLE] Cannot insert step at %d (section end: %d, max: %d)", 
                 at_step, section_end, MAX_SEQUENCER_STEPS);
        return;
    }
    
    // Shift all rows down from insertion point
    for (int step = section_end; step > at_step; step--) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table[step][col] = g_table[step - 1][col];
        }
    }
    
    // Clear the new row
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        g_table[at_step][col].sample_slot = -1;
        g_table[at_step][col].volume = 1.0f;
        g_table[at_step][col].pitch = 1.0f;
    }
    
    // Increase section length
    g_sections[section_index].num_steps++;
    
    // Update public state with seqlock
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
    
    prnt("➕ [TABLE] Inserted step at %d in section %d (section steps: %d)", at_step, section_index, g_sections[section_index].num_steps);
}

// Delete step at given position
void table_delete_step(int section_index, int at_step) {
    if (section_index < 0 || section_index >= g_sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    int section_start = g_sections[section_index].start_step;
    int section_end = section_start + g_sections[section_index].num_steps;
    
    if (at_step < section_start || at_step >= section_end || g_sections[section_index].num_steps <= 1) {
        prnt_err("❌ [TABLE] Cannot delete step at %d (section: %d-%d, steps: %d)", 
                 at_step, section_start, section_end-1, g_sections[section_index].num_steps);
        return;
    }
    
    // Shift all rows up from deletion point
    for (int step = at_step; step < section_end - 1; step++) {
        for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
            g_table[step][col] = g_table[step + 1][col];
        }
    }
    
    // Clear the last row in section
    for (int col = 0; col < MAX_SEQUENCER_COLS; col++) {
        g_table[section_end - 1][col].sample_slot = -1;
        g_table[section_end - 1][col].volume = 1.0f;
        g_table[section_end - 1][col].pitch = 1.0f;
    }
    
    // Decrease section length
    g_sections[section_index].num_steps--;
    
    // Update public state with seqlock
    public_state_write_begin();
    public_state_update();
    public_state_write_end();
    
    prnt("➖ [TABLE] Deleted step at %d in section %d (section steps: %d)", at_step, section_index, g_sections[section_index].num_steps);
}

// Getter functions for FFI - now section-based
int table_get_max_steps(void) {
    return MAX_SEQUENCER_STEPS;
}

int table_get_max_cols(void) {
    return MAX_SEQUENCER_COLS;
}

int table_get_sections_count(void) {
    return g_sections_count;
}

// Helper to calculate which section a step belongs to
int table_get_section_at_step(int step) {
    for (int i = 0; i < g_sections_count; i++) {
        int start = g_sections[i].start_step;
        int end = start + g_sections[i].num_steps;
        if (step >= start && step < end) {
            return i;
        }
    }
    return -1; // Not in any section
}

int table_get_section_start_step(int section_index) {
    if (section_index < 0 || section_index >= g_sections_count) {
        return 0;
    }
    return g_sections[section_index].start_step;
}

int table_get_section_step_count(int section_index) {
    if (section_index < 0 || section_index >= g_sections_count) {
        return 16; // Default section size
    }
    return g_sections[section_index].num_steps;
}

// Section management functions
void table_set_section_step_count(int section_index, int steps) {
    if (section_index < 0 || section_index >= g_sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        g_sections[section_index].num_steps = steps;
        
        // Update public state with seqlock
        public_state_write_begin();
        public_state_update();
        public_state_write_end();
        
        prnt("📏 [TABLE] Set section %d step count to %d", section_index, steps);
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}

// Return pointer to public state for Flutter FFI access
const PublicTableState* table_get_state_ptr(void) {
    return &g_public_state;
}