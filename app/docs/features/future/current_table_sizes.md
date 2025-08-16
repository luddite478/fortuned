## Current Table Sizes: steps_len and columns_len

### Purpose
- Track the current logical size of the flattened sequencer grid independently from fixed storage capacity.
- Drive iteration, row moves, clears, and playback boundaries by current sizes, not by capacity.

### Definitions
```c
// Fixed capacities (already exist)
#define MAX_SEQUENCER_STEPS 128
#define MAX_TOTAL_COLUMNS   64

// Current logical sizes (new)
static int g_steps_len   = 16; // total steps used in the flattened grid (sum of all sections)
static int g_columns_len = 4;  // active columns (num grids * columns per grid)

// Playback region uses [start, end) with end <= g_steps_len
typedef struct { int start; int end; } playback_region_t;
static playback_region_t g_playback_region = {0, 16};
```

### Invariants
- 1 <= g_steps_len <= MAX_SEQUENCER_STEPS
- 1 <= g_columns_len <= MAX_TOTAL_COLUMNS
- 0 <= g_playback_region.start < g_playback_region.end <= g_steps_len

### APIs (internal or FFI as needed)
```c
int  get_steps_len(void)   { return g_steps_len; }
int  get_columns_len(void) { return g_columns_len; }

void set_columns_len(int columns) {
  if (columns < 1) columns = 1;
  if (columns > MAX_TOTAL_COLUMNS) columns = MAX_TOTAL_COLUMNS;
  g_columns_len = columns;
}

void set_playback_region(playback_region_t r) {
  if (r.start < 0) r.start = 0;
  if (r.end < r.start + 1) r.end = r.start + 1;
  if (r.end > g_steps_len) r.end = g_steps_len;
  g_playback_region = r;
  if (g_current_step < g_playback_region.start) g_current_step = g_playback_region.start;
  if (g_current_step >= g_playback_region.end)  g_current_step = g_playback_region.end - 1;
}
```

### Usage in algorithms
- Iteration limits use `g_steps_len` and `g_columns_len`.
- Row insert/delete adjust `g_steps_len` (+1 / -1) and clear/move only within current sizes; see `absolute_row_insert_delete.md`.
- Clearing rows: clear only active columns (`0..g_columns_len-1`).

### When to update current sizes
- Columns length changes whenever UI modifies grids or columns-per-grid.
- Steps length changes only via structural edits (insert/delete); song-mode region end typically equals `g_steps_len`.

### Migration plan
- Implement `g_steps_len/g_columns_len` and switch loops/memmoves to use them.
- Keep existing SoA or migrate to AoS independently (orthogonal).
- After adoption, ensure all APIs that previously assumed capacity use current sizes instead.

### Recommendation
Implement `g_steps_len/g_columns_len` as a separate step first (low risk, orthogonal to cell AoS). Then migrate to the Cell struct; both changes compose cleanly.



