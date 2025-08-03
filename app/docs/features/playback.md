# 🎵 Audio Playback Implementation

**A/B column node architecture with smooth transitions and efficient resource usage**

## Core Architecture

The audio system uses **2 nodes per column (A/B switching)** for efficient resource management and smooth transitions. Instead of creating nodes for each grid cell, we maintain exactly 2 nodes per column and switch between them as needed.

### Function Naming
Updated to consistent naming scheme:
- `start_sequencer()` / `stop_sequencer()` / `is_sequencer_playing()` - sequencer control
- `clear_grid_completely()` - clears samples and resets volume/pitch settings  
- `stop_all_slots()` - stops sample bank playback
- `syncFlutterSequencerGridToNativeSequencerGrid()` - explicit Flutter→Native sync

### A/B Column Node Structure
```c
// Single column node (A or B)
typedef struct {
    int node_initialized;          // 1 when miniaudio node is created
    int sample_slot;               // Which sample this node plays (-1 = none)
    ma_decoder decoder;            // Independent audio decoder
    ma_pitch_data_source pitch_ds; // Pitch shifting layer
    ma_data_source_node node;      // Individual node in graph
    float volume, pitch;           // Current settings
    
    // Volume smoothing (see docs/smoothing.md)
    float current_volume;          // Current smoothed volume
    float target_volume;           // Target volume we're smoothing towards
    float volume_rise_coeff;       // Smoothing coefficient for fade-in
    float volume_fall_coeff;       // Smoothing coefficient for fade-out
    int is_volume_smoothing;       // Whether smoothing is active
    
    uint64_t id;                   // Unique identifier
} column_node_t;

// Column nodes container (A/B pair per column)
typedef struct {
    column_node_t nodes[2];        // A and B nodes for this column
    int active_node;               // 0 = A active, 1 = B active, -1 = none
    int next_node;                 // Which node (0 or 1) to use for next sample
    int column;                    // Column index
} column_nodes_t;
```

### Audio Flow Architecture
```
Sample File → Decoder → Pitch Data Source → Data Source Node → Node Graph → Output
                                              ↑
                                      Volume Smoothing
                                    (see docs/smoothing.md)
```

## Volume and Pitch Control Hierarchy

### Sample Bank Controls (Global)
```c
// Sample bank volume/pitch affect all instances of that sample
g_slots[bank].volume = 1.0f;  // Default: 100% volume
g_slots[bank].pitch = 1.0f;   // Default: original pitch
```

### Cell-Level Overrides
```c
// Cell-specific volume/pitch override sample bank settings when set
g_sequencer_grid_volumes[step][column] = DEFAULT_CELL_VOLUME; // -1.0 = use sample bank
g_sequencer_grid_pitches[step][column] = DEFAULT_CELL_PITCH;  // -1.0 = use sample bank
```

### Default Value System
```c
// Special default values indicating "no override" (use sample bank setting)
#define DEFAULT_CELL_VOLUME -1.0f   // Use sample bank volume
#define DEFAULT_CELL_PITCH -1.0f    // Use sample bank pitch

// Resolution logic (cell overrides take precedence when not default)
static float resolve_cell_volume(int step, int column, int sample_slot) {
    audio_slot_t* sample = &g_slots[sample_slot];
    float bank_volume = sample->volume;
    float cell_volume = g_sequencer_grid_volumes[step][column];
    return (cell_volume != DEFAULT_CELL_VOLUME) ? cell_volume : bank_volume;
}

static float resolve_cell_pitch(int step, int column, int sample_slot) {
    audio_slot_t* sample = &g_slots[sample_slot];
    float bank_pitch = sample->pitch;
    float cell_pitch = g_sequencer_grid_pitches[step][column];
    return (cell_pitch != DEFAULT_CELL_PITCH) ? cell_pitch : bank_pitch;
}
```

### Reset Functions
```c
// Reset cell controls to use sample bank defaults
int reset_cell_volume(int step, int column);
int reset_cell_pitch(int step, int column);
```

## Playback Flow

### 1. A/B Node Management
**Nodes are created on-demand during playback, not when cells are set:**
```c
// When sequencer triggers a sample:
play_samples_for_step(step) → setup_column_node(...) → A/B switching
```
- **Timing**: Nodes created during first playback of a sample in a column
- **State**: New nodes start in `ma_node_state_stopped`, activated when triggered
- **Lifecycle**: Nodes persist and are reused for different samples
- **A/B Logic**: Always switch to unused node for smooth transitions

### 2. A/B Switching Logic
**Sequencer manages A/B switching for smooth transitions:**
```c
// During playback:
play_samples_for_step(step) → get_column_node_for_cell(...) → A/B switch + fade
```
- **Smart switching**: Different sample = switch A/B, same sample = restart current
- **Column tracking**: `currently_playing_nodes_per_col[]` tracks active A or B node
- **Smooth transitions**: Crossfade between A/B nodes (see `docs/smoothing.md`)
- **Resource efficiency**: Fixed memory usage (16 columns × 2 = 32 nodes total)

### 3. Real-time Control Updates
```c
// Update existing nodes when settings change
static void update_existing_nodes_for_cell(int step, int column, int sample_slot) {
    cell_node_t* existing_node = find_node_for_cell(step, column, sample_slot);
    if (existing_node) {
        // Update pitch immediately
        float resolved_pitch = resolve_cell_pitch(step, column, sample_slot);
        update_cell_pitch(existing_node, resolved_pitch);
        
        // Update stored volume (smoothing uses resolved volume)
        existing_node->volume = resolve_cell_volume(step, column, sample_slot);
    }
}
```

### 4. A/B Column System
```c
static column_nodes_t g_column_nodes[MAX_TOTAL_COLUMNS];  // A/B pairs for each column
static column_node_t* currently_playing_nodes_per_col[MAX_TOTAL_COLUMNS];  // Track active node
```
**Purpose**: Provide exactly 2 reusable nodes per column for efficient resource management.

**A/B Switching Behavior**:
- **New sample in column**: Fade out current node, setup & fade in alternate node (A→B or B→A)
- **Same sample triggered**: Restart current node from beginning with smooth transition  
- **Empty cell**: Keep previous node playing (intended sequencer behavior)
- **Resource limit**: Always exactly 32 nodes total (16 columns × 2)

### 5. Stop/Start Behavior
```c
// stop_sequencer() function:
void stop_sequencer(void) {
    g_sequencer_playing = 0;
    g_current_step = 0;
    
    // NEW: Use miniaudio node state control (preserves all settings)
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active) {
            ma_node_set_state(&g_cell_nodes[i].node, ma_node_state_stopped);
        }
    }
    // Nodes preserved - no destruction/recreation needed
}

// start_sequencer() function:  
int start_sequencer(int bpm, int steps) {
    // Resume existing nodes (much faster than recreation)
    for (int i = 0; i < MAX_ACTIVE_CELL_NODES; i++) {
        if (g_cell_nodes[i].active) {
            ma_node_set_state(&g_cell_nodes[i].node, ma_node_state_started);
        }
    }
    
    g_sequencer_playing = 1;
    g_step_just_changed = 1;  // Trigger step 0 immediately
}
```

**Result**: Efficient stop/start cycles that preserve volume/pitch settings and avoid node recreation.

### 6. Pitch Change Handling During Restart

**Issue Fixed**: With SoundTouch preprocessing, when the same sample plays from different steps with different pitches, the node must be completely rebuilt rather than just updating the pitch data source.

```c
// In play_samples_for_step() restart logic:
if (g_current_pitch_method == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && 
    target_node->pitch != resolved_pitch) {
    
    // Rebuild the entire node with new pitch for preprocessing
    setup_column_node(column, target_node_idx, sample_to_play, resolved_volume, resolved_pitch);
} else {
    // For real-time methods, just update the pitch data source
    update_column_node_pitch(target_node, resolved_pitch);
}
```

**Result**: Individual cell pitch overrides work correctly with preprocessing method.

### 7. Grid Sync Strategy
```dart
// Explicit sync when actually needed
syncFlutterSequencerGridToNativeSequencerGrid();

// Call only when:
// - App startup after loading saved state  
// - Loading different saved state
// - Switching sound grids
// - Major grid changes (resize, etc.)

// NOT needed for:
// - Simple stop/start (nodes preserved via ma_node_set_state)
// - Individual cell changes (handled by _syncSingleCellToNative)
```

**Result**: ~90% fewer sync operations, much faster restart times.

## Click Elimination

**Volume smoothing prevents audio clicks during transitions.**
See `docs/smoothing.md` for detailed implementation.

**Key points**:
- **Exponential smoothing**: Natural fade curves (6ms rise, 12ms fall)
- **Per-callback updates**: `update_volume_smoothing()` called every ~11ms
- **Separate rise/fall**: Different timing for fade-in vs fade-out
- **Click-free**: Eliminates discontinuities in audio waveform

## Node Graph Integration

**Following miniaudio node graph pattern:**
```c
// Initialize node graph
ma_node_graph_init(&nodeGraphConfig, NULL, &g_nodeGraph);

// Each cell node connects to endpoint
ma_node_attach_output_bus(&cell->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);

// Audio callback reads from graph
ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
```

**Benefits**:
- **Automatic mixing**: Node graph handles all audio mixing
- **Polyphonic playback**: Multiple cells can play same sample simultaneously
- **Independent processing**: Each cell has its own audio pipeline

## Performance Characteristics

### Resource Management
- **32 total nodes**: Always exactly 16 columns × 2 A/B nodes = 32 nodes
- **Fixed allocation**: Node structures pre-allocated, miniaudio nodes created on-demand
- **Memory efficiency**: ~75% fewer nodes than old per-cell system
- **No cleanup needed**: Nodes are persistent and reused for different samples

### Real-time Performance
- **Volume-only control**: Sequencer just changes volume, no node creation/destruction
- **Smooth transitions**: Exponential volume smoothing prevents clicks
- **Frame-accurate timing**: Sample triggers aligned to audio frames
- **Low latency**: Minimal processing overhead per node
- **Real-time updates**: Settings changes applied immediately to existing nodes

## Other Playback Systems

### Sample Bank Playback
- **Purpose**: Manual sample triggering outside sequencer
- **Implementation**: Dedicated audio pipeline per slot
- **Independence**: Separate from sequencer grid playback

### Preview Systems
- **Sample Preview**: For file browser (`g_sample_preview`)
- **Cell Preview**: For grid cells (`g_cell_preview`) - **Now with immediate feedback!**
- **Implementation**: Dedicated preview nodes independent of other playback
- **Auto-stop**: Preview automatically stops after 1.5 seconds
- **Integration**: Triggered when changing cell pitch/volume for immediate feedback

**New Features**: 
1. **Cell Settings Preview**: When you adjust a cell's pitch or volume, the system immediately previews the cell with the new settings
2. **Sample Bank Settings Preview**: When you adjust a sample's default pitch or volume (sample bank level), the system immediately previews that sample with the new settings - **even if no cells use that sample on the grid**
3. **Tap Preview**: When the sequencer is NOT playing, tapping any cell with a sample will preview it with current pitch/volume settings
4. **Auto-stop**: All previews automatically stop after 1.5 seconds to avoid audio clutter
5. **Smart Preview Management**: New previews automatically cancel previous ones to avoid overlapping sounds

This gives instant audio feedback regardless of sequencer state, grid content, or current step position.

## Technical Implementation

### Main Audio Callback
```c
static void audio_callback(...) {
    // 1. Run sequencer (timing + sample triggering)
    run_sequencer(frameCount);  // Internal function - same name
    
    // 2. Update volume smoothing to prevent clicks
    update_volume_smoothing();
    
    // 3. Monitor cell nodes (cleanup finished)
    monitor_cell_nodes();
    
    // 4. Mix all playing samples into output buffer
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
}
```

### A/B Switching Logic
```c
// In play_samples_for_step():
column_nodes_t* col_nodes = &g_column_nodes[column];
if (different_sample || no_active_sample) {
    // A/B switch: fade out current, setup & fade in alternate
    target_node_idx = col_nodes->next_node;  // Get A or B
    setup_column_node(column, target_node_idx, sample, volume, pitch);
    
    if (col_nodes->active_node >= 0) {
        set_target_volume(&col_nodes->nodes[col_nodes->active_node], 0.0f);  // Fade out
    }
    set_target_volume(&col_nodes->nodes[target_node_idx], volume);  // Fade in
    
    col_nodes->active_node = target_node_idx;
    col_nodes->next_node = (target_node_idx + 1) % 2;  // Alternate for next time
} else {
    // Same sample - restart current node
    ma_decoder_seek_to_pcm_frame(&current_node->decoder, 0);
    set_target_volume(current_node, volume);
}
```

This architecture provides smooth, click-free playback with efficient resource management, professional audio quality, and real-time control updates for both volume and pitch.
