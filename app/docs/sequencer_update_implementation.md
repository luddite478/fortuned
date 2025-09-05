# Sequencer Implementation Documentation

## Overview

This document describes the implementation of the step sequencer system with a native C++ backend and Flutter UI frontend. The system is designed around an authoritative native state with efficient FFI communication and minimal UI updates.

## Architecture Principles

### Core Design Philosophy

1. **Authoritative Native State**: All sequencer data lives in native C++ memory
2. **Zero-Copy Communication**: Flutter reads native data via pointers, no data copying
3. **Change-Based Updates**: Only UI elements that changed are updated each frame
4. **A/B Node Switching**: Smooth audio transitions without clicks or pops
5. **Efficient Memory Management**: Static arrays with maximum sizes, dynamic active regions

### Layer Separation

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                         │
│  - State Management (table.dart, playback.dart, etc.)      │
│  - UI Widgets (simplified_sound_grid.dart, etc.)           │
│  - FFI Bindings (table_playback_bindings.dart)             │
└─────────────────────────────────────────────────────────────┘
                              │ FFI
┌─────────────────────────────────────────────────────────────┐
│                   Native C++ Layer                          │
│  - Table Management (table.mm)                             │
│  - Audio Playback (playback.mm)                            │
│  - Sample Management (sample_bank functions in playback.mm) │
└─────────────────────────────────────────────────────────────┘
```

## Native Layer (C++)

### Data Structures

#### Cell Structure
```cpp
typedef struct {
    int sample_slot;         // -1 = empty, 0-25 = sample index (A-Z)
    int section_index;       // Which section this cell belongs to
    float volume;            // 0.0 to 1.0
    float pitch;             // 0.25 to 4.0 (2 octaves down/up)
    bool changed_last_frame; // For efficient UI updates
} Cell;
```

**Rules:**
- `sample_slot = -1` indicates an empty cell
- `sample_slot 0-25` maps to samples A-Z (26 total slots)
- `volume` is clamped between 0.0 and 1.0
- `pitch` affects playback speed (0.5 = half speed, 2.0 = double speed)
- `changed_last_frame` is set whenever cell data changes

#### Section Structure
```cpp
typedef struct {
    int start_step;    // Starting step index in the global table
    int num_steps;     // Number of steps in this section
} Section;
```

**Rules:**
- Sections are contiguous portions of the global table
- Each section can have different lengths
- Maximum 64 sections supported
- Sections cannot overlap

#### Table Layout
```cpp
static Cell g_table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS];
static int g_active_steps = 16;     // Current active rows
static int g_active_cols = 8;       // Current active columns
static int g_sections_count = 1;    // Number of sections
static Section g_sections[64];      // Section definitions
```

**Constants:**
- `MAX_SEQUENCER_STEPS = 2048` - Maximum table height
- `MAX_SEQUENCER_COLS = 16` - Maximum table width
- Active dimensions can be smaller than maximum

### Table Operations (table.mm)

#### CRUD Operations

**Read Cell:**
```cpp
Cell* table_get_cell(int step, int col);
```
- Returns pointer to cell data (zero-copy access)
- Returns NULL for invalid coordinates
- Used by Flutter to read cell state

**Update Cell:**
```cpp
void table_set_cell(int step, int col, int sample_slot, float volume, float pitch);
```
- Updates cell data and marks as changed
- Automatically calls `table_mark_cell_changed(step, col)`
- Validates coordinates and parameters

**Clear Cell:**
```cpp
void table_clear_cell(int step, int col);
```
- Sets `sample_slot = -1` (empty)
- Resets volume and pitch to defaults
- Marks cell as changed

**Insert/Delete Steps:**
```cpp
void table_insert_step(int at_step);
void table_delete_step(int at_step);
```
- Modifies table structure by shifting rows
- Updates all affected cells' change flags
- Adjusts section boundaries accordingly

#### Change Tracking System

**Purpose:** Enable efficient UI updates by tracking which cells changed.

**Mechanism:**
```cpp
typedef struct {
    int step;
    int col;
} CellCoordinate;

static CellCoordinate g_changed_cells[MAX_SEQUENCER_STEPS * MAX_SEQUENCER_COLS];
static int g_changed_cells_count = 0;
```

**Workflow:**
1. Any table modification calls `table_mark_cell_changed(step, col)`
2. Changed coordinates accumulate in `g_changed_cells` array
3. Flutter calls `table_get_changed_cells()` each frame
4. Flutter updates only the changed cells via ValueNotifiers
5. `table_clear_changed_cells()` resets the tracking

### Audio Playback (playback.mm)

#### Node-Graph Architecture

Uses miniaudio's node-graph system for mixing and playback:

```cpp
typedef struct {
    int column;
    int index;                // 0=A, 1=B
    int node_initialized;
    int sample_slot;
    
    ma_decoder* decoder;      // Individual decoder instance
    ma_data_source_node* node; // Node in the audio graph
    
    // Volume smoothing
    float user_volume;        // User-set volume
    float current_volume;     // Actual current volume
    float target_volume;      // Target for smoothing
    float volume_rise_coeff;  // Fade-in coefficient
    float volume_fall_coeff;  // Fade-out coefficient
    
    uint64_t id;             // Unique identifier
} ColumnNode;
```

#### A/B Node Switching

**Purpose:** Eliminate audio clicks when samples change in the same column.

**Logic:**
- Each column has 2 nodes: A and B
- When a new sample plays in a column:
  1. Previous node fades out (exponential volume reduction)
  2. New node fades in (exponential volume increase)
  3. Old node stops when volume reaches threshold
  4. Roles switch for next sample change

**Implementation:**
```cpp
typedef struct {
    ColumnNode nodes[2];     // A and B nodes
    int active_node;         // Currently playing node (0=A, 1=B, -1=none)
    int next_node;           // Which node to use for next sample
} ColumnNodes;
```

#### Volume Smoothing

**Exponential Smoothing Formula:**
```cpp
new_volume = current_volume + α × (target_volume - current_volume)
```

Where α (alpha) is calculated as:
```cpp
α = 1 - exp(-dt / time_constant)
```

**Time Constants:**
- `VOLUME_RISE_TIME_MS = 6.0f` - Fade-in time
- `VOLUME_FALL_TIME_MS = 12.0f` - Fade-out time
- `VOLUME_THRESHOLD = 0.0001f` - When to consider volume "zero"

#### Playback Rules

**Per-Step Playback:**
- When a step is triggered, ALL samples in ALL columns play simultaneously
- Each column is independent of others

**Column Exclusivity:**
- Only one sample can play per column at any time
- New sample in a column stops the previous sample in that column
- Uses A/B switching for smooth transitions

**Timing:**
- BPM determines step duration: `frames_per_step = (SAMPLE_RATE × 60) / (BPM × 4)`
- Each step represents a 16th note
- Frame counter increments each audio callback

**Example Scenario:**
```
Table:  [A, B,  ,  ]  Step 0: Samples A and B start playing
        [ , B, C,  ]  Step 1: Sample A stops, B continues, C starts
        [ ,  , C, D]  Step 2: B stops, C continues, D starts
```

### Sample Management

#### Sample Bank Storage
```cpp
static ma_decoder g_sample_decoders[MAX_SAMPLE_SLOTS];  // 26 decoders (A-Z)
static char* g_sample_paths[MAX_SAMPLE_SLOTS];          // File paths
static bool g_sample_loaded[MAX_SAMPLE_SLOTS];          // Load status
```

#### Loading Process
1. `sample_bank_load(slot, file_path)` called from Flutter
2. Creates ma_decoder for the audio file
3. Stores file path and marks slot as loaded
4. Each playback node creates its own decoder instance (independent playback positions)

**Why Multiple Decoders?**
- Sample bank decoder: For validation and metadata
- Node decoders: Independent playback positions for overlapping playback

## Flutter Layer

### State Management Architecture

#### Provider Hierarchy
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: tableState),
    ChangeNotifierProvider.value(value: playbackState),
    ChangeNotifierProvider.value(value: sampleBankState),
    ChangeNotifierProvider.value(value: sampleBrowserState),
  ],
  child: SequencerScreenUpdated(),
)
```

#### TableState (lib/state/sequencer/table.dart)

**Purpose:** Manages table data and efficient UI updates.

**Key Features:**
- Holds pointers to native cell data (no copying)
- 2D array of ValueNotifiers for efficient updates
- Lazy initialization of notifiers (only create when needed)
- Processes changed cells from native each frame

**Change Notification Flow:**
```
1. Native modifies cell → marks as changed
2. Timer polls native → gets changed cells list
3. TableState updates specific ValueNotifiers
4. UI widgets listening to those notifiers rebuild
```

**Layer Management:**
- UI concept: Layers are horizontal slices of columns
- `activeLayer` determines which columns are visible
- `colsPerLayer` calculated as `activeCols / layersCount`
- Layer switching doesn't affect native state

#### PlaybackState (lib/state/sequencer/playback.dart)

**Controls:**
- BPM setting
- Play/Stop commands
- Song/Loop mode switching
- Playback region configuration

**Mode Logic:**
- **Loop Mode:** Plays current section repeatedly
- **Song Mode:** Plays all sections sequentially
- Playback region automatically adjusts based on mode

#### SampleBankState (lib/state/sequencer/sample_bank.dart)

**Asset Loading Process:**
1. Flutter asset → copied to temporary file on device
2. Temporary file path → passed to native `sample_bank_load`
3. Native loads and validates the audio file
4. Success/failure reported back to Flutter

**Why Temporary Files?**
- Native code can't directly access Flutter assets
- Temporary files bridge Flutter assets to native file system

#### SampleBrowserState (lib/state/sequencer/sample_browser.dart)

**Manifest Parsing:**
- Loads `samples_manifest.json` from Flutter assets
- Builds virtual folder hierarchy from flat path structure
- Handles navigation through sample directories

### Timer System (lib/state/sequencer/timer.dart)

**Frame-Rate Updates:**
```dart
void _onTick(Duration elapsed) {
  tableState.processChangedCells();  // Update changed cells
  if (playbackState.isPlaying) {
    playbackState.updateCurrentStep(); // Update playhead position
  }
}
```

**Efficiency:** Only polls native state, doesn't push data to native.

## UI Components

### SimplifiedSoundGrid (lib/widgets/sequencer_updated/simplified_sound_grid.dart)

**Cell Rendering:**
```dart
ValueListenableBuilder<CellData>(
  valueListenable: tableState.getCellNotifier(step, col),
  builder: (context, cellData, child) {
    // Only this cell rebuilds when its data changes
  }
)
```

**Interaction Logic:**
- Empty cell tap → Opens sample browser
- Filled cell tap → Could modify volume/pitch (future)
- Sample browser selection → Adds sample to cell

**Sample Browser Integration:**
- Conditionally shows either grid or browser
- Browser overlays the grid when active
- Selection returns to grid with sample loaded

### PlaybackControls (lib/widgets/sequencer_updated/playback_controls.dart)

**Simple Controls:**
- Play/Stop button
- BPM slider
- Current step indicator

## FFI Bindings (lib/table_playback_bindings.dart)

### Function Signatures

**Table Functions:**
```dart
typedef TableGetCellNative = Pointer<Cell> Function(Int32 step, Int32 col);
typedef TableSetCellNative = Void Function(Int32 step, Int32 col, Int32 sampleSlot, Float volume, Float pitch);
```

**Memory Management:**
- Uses `calloc` for temporary allocations
- Always calls `calloc.free()` after use
- Native pointers remain valid throughout app lifetime

## Key Relationships and Dependencies

### Native Dependencies
```
playback.mm → table.mm (reads cell data for playback)
playback.mm → sample_bank functions (loads and plays samples)
table.mm → (standalone, no dependencies)
```

### Flutter Dependencies
```
Timer → TableState, PlaybackState (polls for changes)
TableState → FFI bindings (CRUD operations)
PlaybackState → FFI bindings (playback control)
SampleBankState → FFI bindings (sample loading)
UI Widgets → State via Provider (reactive updates)
```

### Data Flow
```
User Interaction → Flutter State → FFI Call → Native State Change → 
Change Tracking → Timer Poll → Flutter State Update → UI Rebuild
```

## Performance Considerations

### Memory Usage
- **Static Arrays:** Pre-allocated maximum sizes avoid dynamic allocation
- **Active Regions:** Only use portion of maximum arrays
- **Pointer Sharing:** Flutter reads native memory directly

### UI Efficiency
- **ValueNotifiers:** Only changed cells rebuild
- **Lazy Initialization:** Notifiers created only when cells become visible
- **2D Array Access:** O(1) notifier lookup vs string-based keys

### Audio Performance
- **Node Graph:** Efficient mixing by miniaudio
- **A/B Switching:** Prevents audio discontinuities
- **Independent Decoders:** Multiple simultaneous playback of same sample

## Error Handling

### Native Layer
- Coordinate validation on all table operations
- Sample slot bounds checking
- Decoder initialization failure handling
- Memory allocation failure handling

### Flutter Layer
- FFI null pointer checks
- Asset loading failure handling
- Invalid state recovery
- Graceful degradation when native calls fail

## Future Extensions

### Planned Features
- **Pitch Control:** Per-cell pitch adjustment (already in Cell structure)
- **Effects:** Per-column or per-cell audio effects
- **Section Management:** Dynamic section creation/deletion
- **Sample Preview:** Playback samples in browser before selection

### Architecture Support
- **Modular Design:** Easy to add new state managers
- **FFI Extensible:** Simple to add new native functions
- **UI Flexible:** Component-based for easy feature addition

## Debugging and Monitoring

### Native Logging
```cpp
prnt("✅ [SAMPLE_BANK] Sample loaded in slot %d: %s", slot, file_path);
prnt_err("❌ [PLAYBACK] Sample slot %d not loaded", sample_slot);
```

### Flutter Debugging
- Provider state changes visible in Flutter Inspector
- ValueNotifier changes trackable
- FFI call success/failure logged

### Performance Monitoring
- Changed cells count per frame
- Active nodes count
- Memory usage tracking
- Audio callback timing

This documentation provides a comprehensive understanding of the sequencer implementation, focusing on the rules, logic, and relationships between all components of the system.
