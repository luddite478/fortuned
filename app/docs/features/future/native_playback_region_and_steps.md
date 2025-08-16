### Native Sequencer Refactor: AoS Cells, Current Sizes, Playback Region, Step Ops

#### Overview
- Migrated native grid to an Array-of-Structs (AoS) model (`g_cells`).
- Introduced current logical sizes (`g_steps_len`, `g_columns_len`) separate from fixed capacities.
- Added a playback region `[start, end)` that defines the active window of steps for playback.
- Implemented single-step structural edits: `insert_step()` and `delete_step()` with safe application at step boundaries.
- Deprecated native “sections” behavior in favor of playback region control from Flutter.

#### Data Model
```c
typedef struct {
  int   sample_slot;   // -1 = empty
  float volume;        // DEFAULT_CELL_VOLUME → use sample bank volume
  float pitch;         // DEFAULT_CELL_PITCH  → use sample bank pitch (ratio)
} Cell;

static Cell g_cells[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS];
static int  g_steps_len = 16;    // 1..MAX_SEQUENCER_STEPS (current logical steps)
static int  g_columns_len = 4;   // 1..MAX_TOTAL_COLUMNS (current active columns)
```

Capacities remain hard bounds:
- `MAX_SEQUENCER_STEPS` and `MAX_TOTAL_COLUMNS` define storage capacity, not current size.

#### Playback Region
```c
typedef struct { int start; int end; } playback_region_t; // [start, end), end exclusive

// Set + clamp
void set_playback_region(playback_region_t region);
```
- Region is validated: `0 <= start < end <= g_steps_len`.
- Loop mode: when `g_current_step >= end`, wrap to `start`.
- Song mode: when `g_current_step >= end`, stop playback.
- On `start_sequencer(...)`, the region is clamped to current `g_steps_len` if needed.

#### APIs (FFI)
Current sizes and columns:
```c
int  get_steps_len(void);
int  get_columns_len(void);
void set_columns_len(int columns); // clamps to [1, MAX_TOTAL_COLUMNS]
```

Playback region:
```c
void set_playback_region(playback_region_t region); // clamps to [0, g_steps_len]
```

Single-step structural edits:
```c
void insert_step(int step);  // shifts tail down, clears inserted step, grows g_steps_len (≤ capacity)
void delete_step(int step);  // shifts tail up, clears last step, shrinks g_steps_len (≥ 1)
```

Notes:
- If editing the currently playing step while playing, the operation is queued and applied at the next step boundary to avoid clicks.

Deprecated section functions (no-ops / logs only):
```c
void set_current_section(int section);
void set_total_sections(int sections);
int  get_current_section(void);
int  get_total_sections(void);
```

#### Runtime Behavior
- Playback reads from `g_cells` (AoS):
  - Sample: `g_cells[step][col].sample_slot`
  - Volume override: `g_cells[step][col].volume`
  - Pitch override: `g_cells[step][col].pitch`
- Resolvers fall back to sample bank when cell override is default.
- `run_sequencer()` uses playback region to decide wrap/stop and applies any pending single-step op at the step boundary.

#### Flutter Integration
- When adding/removing steps:
  1) Call `insert_step(step)` or `delete_step(step)`.
  2) Update playback region via `set_playback_region(...)`:
     - Song mode: region should cover the full native table `[0, get_steps_len())`.
     - Loop mode: region should cover the currently visible section window
       (e.g., `[sectionStart, sectionStart + sectionLength)`), where sectionLength may differ per section.

- When changing the number of active columns (e.g., grids × columns-per-grid):
  - Call `set_columns_len(totalActiveColumns)`.

- On start:
  - Ensure region is set for the intended mode before `start_sequencer(...)`.
  - Native clamps region to `g_steps_len` if needed.

#### Migration Notes
- Removed legacy SoA arrays (`g_sequencer_grid`, `g_sequencer_grid_volumes`, `g_sequencer_grid_pitches`).
- All reads/writes use `g_cells`.
- Terminology standardized to “steps” (not “rows”).
- Helpers renamed: `clear_steps(...)`, `move_steps(...)`.

This refactor centralizes grid state, decouples playback boundaries from sections, and provides clear step-wise structural editing with predictable playback behavior.


