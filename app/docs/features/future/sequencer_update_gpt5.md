## Step Sequencer Refactor — Implementation Plan (for approval)

This plan describes the minimal, clear, and maintainable implementation for a new authoritative native step-sequencer with Flutter UI powered by FFI pointers. It keeps only the essentials now: a sound grid and play/stop, plus a samples bank panel. Everything else is out of scope for the first iteration.

### Goals
- **Authoritative native engine**: C/ObjC++ owns sequencer table and playback using miniaudio node-graph.
- **FFI pointers**: Flutter reads native data via pointers and triggers native CRUD via FFI.
- **Efficient UI updates**: Only changed cells propagate through a native change-tracking list read each frame.
- **Simple UI**: One screen `sequencer_screen_updated.dart` with a single section that contains 4 layers (A/B/C/D). Only one layer active at a time. Play/Stop.
- **Playback modes**: Song vs Loop, using a playback region in native.

---

## Native layer (authoritative)

### Files
- `app/native/table.mm` — Table and CRUD, selections, change tracking, section/layer addressing.
- `app/native/playback.mm` — miniaudio node-graph setup, transport (start/stop), bpm, step clock, A/B switching, smoothing.
- `app/native/sample_bank.mm` — Sample loading/unloading and handles for table cells.

Existing `app/native/sequencer.mm` (old impl) will remain unchanged for reference. New impl is split for clarity.

### Data structures
1) Global configuration
```
// Compile-time maxima (used for single allocation once)
#define MAX_SEQUENCER_STEPS <to be decided>  // e.g. 512
#define MAX_SEQUENCER_COLS  <to be decided>  // e.g. 64

// Runtime active dimensions
static int g_steps_len;   // 0..MAX_SEQUENCER_STEPS
static int g_cols_len;    // 0..MAX_SEQUENCER_COLS
```

2) Cell
```
typedef struct {
    int sample_id;        // -1 = empty; otherwise refers to sample_bank slot
    int section_index;    // for bookkeeping (optional for v1)
    float volume;         // user volume [0..1]

    // change tracking (one-frame flag or last-step flag)
    int changed_last_step; // 0/1 — set in CRUD and selection operations where applicable
} Cell;
```

3) Tables
```
// Static backing 2D storage (contiguous for FFI-friendly pointers)
static Cell g_table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS];

// Pointer to active logical region (same memory, but iterate bounds via g_steps_len/g_cols_len)
static Cell (*g_active_table)[MAX_SEQUENCER_COLS] = g_table;
```

4) Sections and layers (UI concepts)
- Section: vertical slice over steps with a width in columns; the “song” is the full table.
- Layer: horizontal slice within a section (subset of columns).

For v1: One section visible with 4 fixed layers (L0..L3). Only one active layer at a time.

We’ll store a simple mapping:
```
typedef struct {
    int section_start_col; // inclusive
    int section_len_cols;  // number of columns in section
    int layer_count;       // 4 for v1
    // For v1, layers are equal-sized, contiguous slices inside the section
} SectionLayout;

static SectionLayout g_layout;
static int g_active_layer_index; // 0..layer_count-1
```

### CRUD and selection
API exposed for FFI (subset shown — full signatures in FFI section):
- `Cell* table_ptr();` — returns pointer to first cell for Flutter pointer mapping.
- `int steps_len(); int cols_len();` — current active bounds.
- CRUD on cells by `(step, col)` within active bounds:
  - `int cell_read(int step, int col, Cell* out);`
  - `int cell_update(int step, int col, const Cell* in);`
  - `int cell_insert(int step, int insert_at_col);` — shift right inside active section/layer; trims last col if overflow.
  - `int cell_delete(int step, int delete_col);` — shift left.
- Selection helpers (non-copying, index-returning):
  - `int select_every_nth_col_in_section(int section_index, int n, int* out_cols, int max_out_len);`
  - `int select_section_bounds(int section_index, int* out_start_col, int* out_len);`

Each CRUD operation sets `changed_last_step=1` for affected cells and appends coordinates to the per-frame change list.

### Change tracking
- A ring buffer (or fixed array per callback frame) of changed coordinates: `struct {int step; int col;} g_changed_cells[]`.
- Two phases:
  1) During CRUD: append changed coordinates.
  2) On frame/tick read: expose current list via `get_changed_cells` and clear flags.

FFI:
- `int get_changed_cells(const Cell** out_cells, const int** out_coords, int* out_count);`
  - Returns pointers to arrays for zero-copy UI updates; coords are `(step, col)` pairs.

### Playback engine (miniaudio node-graph)
1) Graph and device
```
// Global node graph
static ma_node_graph g_nodeGraph;
static ma_device g_device;
```

2) Per-column A/B nodes
```
typedef struct {
    int column;
    int index;                  // 0=A, 1=B
    int node_initialized;       // 0/1
    int sample_slot;            // -1 = none
    ma_decoder decoder;         // independent decoder
    ma_data_source_node node;   // node within graph

    float user_volume;
    float current_volume;
    float target_volume;
    float volume_rise_coeff;    // alpha for fade-in
    float volume_fall_coeff;    // alpha for fade-out

    uint64_t id;
} miniaudio_node_t;

static miniaudio_node_t g_nodes[MAX_SEQUENCER_COLS][2];
```

3) Transport and clock
```
static int g_is_playing;
static int g_sequencer_bpm;
static ma_uint64 g_frames_per_step;   // (SAMPLE_RATE * 60) / (bpm * 4)
static ma_uint64 g_step_frame_counter;
static int g_current_step;            // 0..g_steps_len-1
```

4) Playback region and modes
```
typedef enum { MODE_SONG = 0, MODE_LOOP = 1 } SequencerMode;
static SequencerMode g_mode;

typedef struct {
    int start_step;  // inclusive
    int length;      // steps
} PlaybackRegion;

static PlaybackRegion g_region; // whole table in song mode; one section in loop mode
```

5) Node-graph lifecycle
- Initialize `ma_node_graph` once.
- For each column, lazily initialize 2 nodes (A/B) as `ma_node_state_stopped` and attach to graph endpoint per docs.
- When a step triggers a column (non-empty cell):
  - Switch to the idle node (toggle A/B), load sample if needed (from `sample_bank.mm`), set decoder to start.
  - Start node, set `target_volume=cell.volume`, set rise/fall alphas.
  - If previous node is active in that column, its `target_volume` becomes 0 (fade-out).
- When a step has empty cell in a column, we do not trigger a new sample; if the column had previous sample, it keeps playing until canceled by a later non-empty cell in the same column or naturally ends (node reaches silence and stops).
- Deactivate node (stop and detach decoder) when `current_volume` reaches ~0 and decoder is done.

6) Volume smoothing
```
#define VOLUME_RISE_TIME_MS 6.0f
#define VOLUME_FALL_TIME_MS 12.0f
#define VOLUME_THRESHOLD 0.0001f

static float calculate_smoothing_alpha(float time_ms);
static float apply_exponential_smoothing(float current, float target, float alpha);
```
Apply per audio callback iteration.

7) Audio callback
```
static void audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    // 1) Run sequencer clock
    for (ma_uint32 frame = 0; frame < frameCount; frame++) {
        g_step_frame_counter++;
        if (g_step_frame_counter >= g_frames_per_step) {
            g_step_frame_counter = 0;
            if (g_is_playing) {
                // Advance step within g_region
                // Trigger play_samples_for_step(g_current_step)
            }
        }
    }

    // 2) Render graph
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
}
```

8) FFI control
- `void set_bpm(int bpm);`
- `void start_sequencer(); void stop_sequencer();`
- `void set_mode(int mode); // 0 song, 1 loop`
- `void set_region(int start_step, int length);`
- `int current_step();`

### Sample bank
- Load by path or asset key; return `sample_id`.
- Decode via `ma_decoder_init_file` (or memory) and provide to column node on demand.
- FFI:
  - `int sample_load(const char* path);`
  - `void sample_unload(int sample_id);`

---

## FFI surface (high-level)

Functions to export:
- Table data and bounds
  - `Cell* table_ptr();`
  - `int steps_len(); int cols_len();`
- CRUD
  - `int cell_read(int step, int col, Cell* out);`
  - `int cell_update(int step, int col, const Cell* in);`
  - `int cell_insert(int step, int insert_at_col);`
  - `int cell_delete(int step, int delete_col);`
  - `int select_every_nth_col_in_section(int section_index, int n, int* out_cols, int max_out_len);`
- Change tracking
  - `int get_changed_cells(const Cell** out_cells, const int** out_coords, int* out_count);`
- Layout and mode
  - `void set_section_layout(int start_col, int len_cols, int layer_count);`
  - `void set_active_layer(int layer_index);`
  - `int get_active_layer();`
- Transport
  - `void start_sequencer(); void stop_sequencer();`
  - `void set_bpm(int bpm);`
  - `void set_mode(int mode); // 0 song, 1 loop`
  - `void set_region(int start_step, int length);`
  - `int current_step();`
- Samples
  - `int sample_load(const char* path);`
  - `void sample_unload(int sample_id);`

We will update `app/ffigen.yaml` if needed and regenerate bindings. New bindings will live in a dedicated `lib/sequencer_bindings_generated.dart` (reuse existing filename if compatible, otherwise add a new one `sequencer_v2_bindings_generated.dart`).

---

## Flutter layer

### Files
- `app/lib/state/sequencer/table.dart` — Pointer-backed view of the native table; thin CRUD helpers that call FFI and expose typed Pointer<Cell> for the grid.
- `app/lib/state/sequencer/timer.dart` — Ticker that calls `get_changed_cells` each frame and notifies observers (ValueNotifiers per cell, row, column or section depending on granularity needed).
- `app/lib/state/sequencer/playback.dart` — Holds UI-visible playback meta (bpm, mode, current section/layer index). Delegates changes to FFI.
- `app/lib/screens/sequencer_screen_updated.dart` — Minimal UI with only: sound grid + samples bank + play/stop and layer selector. One section with 4 layers; only one active.

### UI specifics (v1)
- Grid displays current section and the active layer only.
- Layer selector (4 tabs/cards) switches `g_active_layer_index` via FFI.
- Play/Stop button calls `start_sequencer`/`stop_sequencer`.
- BPM control can be a simple input or pre-set buttons; calls `set_bpm`.
- Insert/Delete step: acts in the middle of the section (as requested); calls `cell_insert`/`cell_delete` per selected row/col.
- Efficient updates: per frame, read `get_changed_cells`, update only affected ValueNotifiers.

### Pointer mapping
- Define a Dart FFI struct mirroring native `Cell` (packing and field order must match).
- Map base pointer from `table_ptr()` to a 2D access helper. No copies for reads.
- CRUD uses FFI function calls; direct writes through pointer are avoided to keep native bookkeeping consistent.

---

## Build integration

- Update `app/native/CMakeLists.txt` to include `table.mm`, `playback.mm`, `sample_bank.mm` in the static library.
- Update iOS Xcode project to compile the new files. Android uses CMake/NDK from the same list.
- Ensure miniaudio single-header is included once, and link flags are correct.

---

## Testing and validation (v1)

1) Unit-like native checks (log prints):
- Set BPM and verify `g_frames_per_step` computed correctly.
- Create a simple pattern: cells in (0,0), (0,1), (1,0). Confirm cancel rule for column 0, continuous play for column 1.
- Toggle loop vs song to verify playback region boundaries.

2) Flutter manual testing:
- Start/stop while grid visible.
- Change active layer and verify only that layer updates.
- Insert/delete in middle and confirm table shift + minimal UI updates.

---

## Open questions for you

1) Defaults: What should we use for `MAX_SEQUENCER_STEPS` and `MAX_SEQUENCER_COLS` for v1?
2) Sample bank: Are samples loaded by absolute file path, Flutter asset key, or both? Any format constraints (e.g., prefer 48kHz mono) or should miniaudio resample on the fly?
3) Decoder lifecycle: Is it acceptable to keep decoders open per active node during playback and close them on silence/end, or do you want a shared decoder + independent read cursors per node?
4) UI section width: For v1, is the single section width equal to `g_cols_len`? If not, provide start/len.
5) Insert/Delete semantics: You asked “insert/delete steps in the middle of the table.” For multiple rows, should insert/delete act on all rows at a given column index inside the visible section, or only the active layer’s sub-range?
6) Change tracking buffer size: Provide expected upper bound of changed cells per frame to size the buffer safely.
7) Bindings: Do you want to reuse `lib/sequencer_bindings_generated.dart` or create `lib/sequencer_v2_bindings_generated.dart` to keep old and new side-by-side temporarily?
8) iOS/Android: Any platform-specific audio requirements (e.g., background mode, low-latency settings) we should lock in now?

---

If you approve this plan, I’ll proceed to:
1) Implement native modules (`table.mm`, `playback.mm`, `sample_bank.mm`) + CMake/Xcode entries.
2) Expose the FFI surface and regenerate bindings.
3) Add the minimal Flutter state modules and `sequencer_screen_updated.dart` wired to the native engine.
4) Verify playback with miniaudio node-graph, A/B smoothing, and efficient UI updates via `get_changed_cells`.


