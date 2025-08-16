## Row Insert/Delete with Playback Region

### Goals
- Modify the flattened grid in-place using steps, one row per call (matches UI behavior).
- Avoid clicks: never mutate the currently playing step mid-tick.
- Keep playback boundaries in a single region [start, end), reuse `g_song_mode` for wrap vs stop.

### Public native API (FFI)
```c
// Insert/delete exactly one row at given step
void insert_step(int step);
void delete_step(int step);

// Set playback window in steps. "end" is exclusive: region = [start, end)
typedef struct { int start; int end; } playback_region_t;
void set_playback_region(playback_region_t region);

// Current logical sizes (separate from fixed capacity)
int get_steps_len(void);   // returns current total steps used
int get_columns_len(void); // returns current active columns
void set_columns_len(int columns); // updates active columns (<= capacity)
```

### Behavior and size updates
```c
// Insert at step: shifts tail within current size, clears inserted row, grows g_steps_len by 1
// Delete at step: shifts tail up within current size, clears freed last row, shrinks g_steps_len by 1 (min 1)
```

### Internals
```c
// Pending single-step op if editing equals current step while playing
enum { OP_NONE = 0, OP_INSERT = 1, OP_DELETE = 2 };
typedef struct { int op; int step; } pending_op_t; // single struct
static pending_op_t g_pending = { OP_NONE, 0 };

static inline void clear_rows(int startRow, int count);
static inline void move_rows(int fromRow, int toRow, int numRows);

// Capacity is a fixed upper bound for storage (e.g., MAX_SEQUENCER_STEPS)
// Current total steps tracked by g_steps_len; playback_region.end must be <= g_steps_len.
static void apply_insert_1(int step) {
  if (step < 0) step = 0;
  if (step > g_steps_len) step = g_steps_len; // insert at tail if beyond current
  int rowsToMove = (g_steps_len < MAX_SEQUENCER_STEPS ? (g_steps_len - step) : (MAX_SEQUENCER_STEPS - step - 1));
  if (rowsToMove > 0) move_rows(step, step + 1, rowsToMove); // move only current length
  clear_rows(step, 1);
  if (step <= g_current_step) g_current_step += 1; // keep pointing to same content
  if (g_steps_len < MAX_SEQUENCER_STEPS) g_steps_len += 1; // grow current length up to capacity
}

static void apply_delete_1(int step) {
  if (step < 0) step = 0;
  if (step >= g_steps_len) step = g_steps_len - 1; // clamp to last valid row
  int rowsToMove = g_steps_len - step - 1; // move only current length tail
  if (rowsToMove > 0) move_rows(step + 1, step, rowsToMove);
  clear_rows(g_steps_len - 1, 1);
  if (step < g_current_step)      g_current_step -= 1;
  else if (step == g_current_step) {/* stay at same index, new content slid in */}
  if (g_steps_len > 1) g_steps_len -= 1; // shrink current length, keep >=1
}

void insert_step(int step) {
  if (g_sequencer_playing && step == g_current_step) { g_pending.op = OP_INSERT; g_pending.step = step; return; }
  apply_insert_1(step);
}

void delete_step(int step) {
  if (g_sequencer_playing && step == g_current_step) { g_pending.op = OP_DELETE; g_pending.step = step; return; }
  apply_delete_1(step);
}

// Call at step boundary before triggering new step
static inline void apply_pending_op_if_exists() {
  if (g_pending.op == OP_NONE) return;
  if (g_pending.op == OP_INSERT) apply_insert_1(g_pending.step);
  else if (g_pending.op == OP_DELETE) apply_delete_1(g_pending.step);
  g_pending.op = OP_NONE;
  // clamp to region if maintained natively
  // Ensure playback region is within current length
  // if (g_playback_region.end > g_steps_len) g_playback_region.end = g_steps_len;
  // if (g_current_step < g_playback_region.start) g_current_step = g_playback_region.start;
  // if (g_current_step >= g_playback_region.end)  g_current_step = g_playback_region.end - 1;
}
```

- Maintain a single region `[start, end)` in `playback_region_t`, where `end` is exclusive (one past last step).
- Loop mode: when `g_current_step >= end`, set `g_current_step = start`.
- Song mode: when `g_current_step >= end`, stop.
- Flutter updates region after structural changes (e.g., section resize).

### Flutter call flow (resize one section row)
1) Compute the target step at the end of the section.
2) Add row: `insert_step(step)`; Remove row: `delete_step(step)`.
3) Update playback region: `set_playback_region((playback_region_t){ .start = start, .end = end })`.

### Notes on current size vs capacity
- `MAX_SEQUENCER_STEPS` and `MAX_TOTAL_COLUMNS` are storage capacities (upper bounds).
- The actual current sizes are `g_steps_len` and `g_columns_len`.
- The playback region `.end` must be <= `g_steps_len`.
- Insert increases `g_steps_len` by 1 (up to capacity); delete decreases it (down to at least 1).

### Testing checklist
- Insert/delete at 0, middle, end while stopped and while playing.
- Ensure no clicks when editing the currently playing step (pending op applies on next boundary).
- Verify loop wrapping and song stop at updated region.


