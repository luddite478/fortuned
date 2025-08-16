## Grid Cell (AoS) Implementation Plan

### Goals
- Replace parallel arrays with a single cell struct (AoS) for clarity, performance, and easier future fields.
- Keep existing FFI surface (operate with ints/floats), no struct crossing FFI.
- Zero functional regressions; enable faster row shifts (single memmove per row).

### Cell data model
```c
typedef struct {
  int   sample_slot;    // -1 = empty
  float volume;         // DEFAULT_CELL_VOLUME when using bank default
  float pitch;          // DEFAULT_CELL_PITCH when using bank default (ratio)
  // future: pan, envelope, probability, etc.
} Cell;

static Cell g_cells[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS];
static const Cell DEFAULT_CELL = { -1, DEFAULT_CELL_VOLUME, DEFAULT_CELL_PITCH };
```

### Current size
```c
// Current logical sizes (must satisfy 1 <= g_steps_len <= MAX_SEQUENCER_STEPS,
// and 1 <= g_columns_len <= MAX_TOTAL_COLUMNS)
static int g_steps_len = 16;   // total steps currently used in the flattened grid (sum of sections)
static int g_columns_len = 4;  // active columns currently used (num grids * cols per grid)

// Invariants: playback_region.end == g_steps_len (song), or fits within it (loop)
//             0 <= playback_region.start < playback_region.end <= g_steps_len
```

### Helpers
```c
static inline Cell* cell_at(int step, int col) {
  if (step < 0 || step >= g_steps_len) return NULL;
  if (col < 0 || col >= g_columns_len) return NULL;
  return &g_cells[step][col];
}

static inline void clear_steps(int startStep, int count) {
  for (int i = 0; i < count; i++) {
    int step = startStep + i; if (step >= MAX_SEQUENCER_STEPS) break; // allow tail clears during insert/delete
    for (int c = 0; c < g_columns_len; c++) g_cells[step][c] = DEFAULT_CELL; // clear active columns
  }
}

static inline void move_steps(int fromStep, int toStep, int numSteps) {
  if (numSteps <= 0) return;
  size_t stepBytes = sizeof(Cell) * (size_t)g_columns_len; // move only active columns
  memmove(&g_cells[toStep][0], &g_cells[fromStep][0], (size_t)numSteps * stepBytes);
}
```

### Replace usages
- Playback: read `Cell` instead of 3 arrays.
  - `int sample = g_cells[step][col].sample_slot;`
  - Resolve volume/pitch using cell overrides; fallback to bank.
- Set/clear cell:
```c
void set_cell(int step, int column, int sample_slot) {
  // ...validate...
  Cell* cell = cell_at(step, column);
  int old = cell->sample_slot;
  if (sample_slot == -1) { *cell = DEFAULT_CELL; return; }
  if (old >= 0 && old != sample_slot) {
    cell->volume = DEFAULT_CELL_VOLUME;
    cell->pitch  = DEFAULT_CELL_PITCH;
  }
  cell->sample_slot = sample_slot;
}

void clear_cell(int step, int column) {
  Cell* cell = cell_at(step, column);
  *cell = DEFAULT_CELL;
}
```

- Volume/pitch overrides:
```c
int set_cell_volume(int step, int column, float volume) { cell_at(step,column)->volume = volume; return 0; }
int reset_cell_volume(int step, int column) { cell_at(step,column)->volume = DEFAULT_CELL_VOLUME; return 0; }
float get_cell_volume(int step, int column) { return cell_at(step,column)->volume; }

int set_cell_pitch(int step, int column, float pitch) { cell_at(step,column)->pitch = pitch; return 0; }
int reset_cell_pitch(int step, int column) { cell_at(step,column)->pitch = DEFAULT_CELL_PITCH; return 0; }
float get_cell_pitch(int step, int column) { return cell_at(step,column)->pitch; }
```

### Note on step operations
Step insert/delete is specified separately. See `absolute_row_insert_delete.md` for the step API and boundary handling. This document focuses on the AoS cell model, current sizes, and per-cell accessors only.

### Migration plan
- Phase 1: Add `Cell`, helpers; dual-write in `set_cell/clear/volume/pitch` to both AoS and existing SoA arrays.
- Phase 2: Switch read paths (playback, resolvers) to AoS.
- Phase 3: Remove SoA arrays and dual-write; keep only `g_cells`.
- Phase 4: Introduce absolute row insert/delete API (see companion doc) and playback region.

### FFI impact
- Existing functions remain (operate with ints/floats), no struct over FFI.
- No binding changes until insert/delete/region are added.

### Testing
- Verify set/clear, volume/pitch overrides, and playback read from `g_cells`.
- Regression: existing projects load/play identically; performance improves on step shifts.


