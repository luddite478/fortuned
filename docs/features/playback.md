# 🎵 Audio Playback Implementation

**Per-cell node architecture with column tracking and smooth volume transitions**

## Core Architecture

The audio system uses **individual nodes per grid cell** with **column-based tracking** for smooth transitions. Each grid cell gets its own permanent audio node that's controlled by the sequencer through volume changes.

### Per-Cell Node Structure
```c
typedef struct {
    int active;                    // Node status
    int step, column, sample_slot; // Grid position and sample reference
    ma_decoder decoder;            // Independent audio decoder
    ma_pitch_data_source pitch_ds; // Pitch shifting layer
    ma_data_source_node node;      // Individual node in graph
    float volume, pitch;           // Cell-specific controls
    
    // Volume smoothing (see docs/smoothing.md)
    float current_volume;          // Current smoothed volume
    float target_volume;           // Target volume we're smoothing towards
    float volume_rise_coeff;       // Smoothing coefficient for fade-in
    float volume_fall_coeff;       // Smoothing coefficient for fade-out
    int is_volume_smoothing;       // Whether smoothing is active
    
    uint64_t id;                   // Unique identifier
} cell_node_t;
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

### 1. Node Creation (Grid Management)
**Nodes are created when cells are set, not during playback:**
```c
// When user sets a cell:
set_cell(step, column, sample_slot) → create_cell_node(...) → starts at volume 0.0
```
- **Timing**: Happens during grid editing, not sequencer playback
- **State**: Nodes start silent (`volume = 0.0`)
- **Lifecycle**: Nodes persist until cell is cleared or changed
- **Volume/Pitch**: Uses resolved values from hierarchy system

### 2. Sequencer Playback (Volume Control)
**Sequencer controls volume of existing nodes:**
```c
// During playback:
play_samples_for_step(step) → find_node_for_cell(...) → set_target_volume(...)
```
- **No node creation**: Sequencer only controls volume of pre-existing nodes
- **Column tracking**: `currently_playing_nodes_per_col[]` tracks what's audible per column
- **Smooth transitions**: Volume changes use exponential smoothing (see `docs/smoothing.md`)
- **Real-time resolution**: Volume/pitch resolved on every trigger

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

### 4. Column Tracking System
```c
static cell_node_t* currently_playing_nodes_per_col[MAX_TOTAL_COLUMNS];
```
**Purpose**: Track which node is currently audible in each column for smooth transitions.

**Behavior**:
- **New sample in column**: Fade out old node, fade in new node
- **Same sample triggered**: Restart from beginning with smooth volume transition
- **Empty cell**: Keep previous node playing (intended sequencer behavior)

### 5. Stop/Start Behavior
```c
// stop() function:
void stop(void) {
    // Smoothly fade out all currently playing nodes
    for (each column) {
        if (currently_playing_nodes_per_col[column]) {
            set_target_volume(node, 0.0f);  // Smooth fade to silence
        }
    }
    
    // Clear tracking since nothing is currently playing
    memset(currently_playing_nodes_per_col, 0, ...);
}

// start() function:
void start(int bpm, int steps) {
    // Configure sequencer (don't clear column tracking)
    g_current_step = 0;
    g_step_just_changed = 1;  // Trigger step 0 immediately
    g_sequencer_playing = 1;
}
```

**Result**: Clean stop/start cycles with proper state management.

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
- **512 simultaneous nodes**: `MAX_ACTIVE_CELL_NODES = 512`
- **Node pooling**: Pre-allocated `g_cell_nodes[]` array
- **Memory efficiency**: Multiple nodes can reference same sample data
- **Automatic cleanup**: Finished nodes automatically return to pool

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
- **Cell Preview**: For grid cells (`g_cell_preview`)
- **Implementation**: Dedicated preview nodes independent of other playback

## Technical Implementation

### Main Audio Callback
```c
static void audio_callback(...) {
    // 1. Run sequencer (timing + sample triggering)
    run_sequencer(frameCount);
    
    // 2. Update volume smoothing to prevent clicks
    update_volume_smoothing();
    
    // 3. Monitor cell nodes (cleanup finished)
    monitor_cell_nodes();
    
    // 4. Mix all playing samples into output buffer
    ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
}
```

### Sample Switching Logic
```c
// In play_samples_for_step():
cell_node_t* target_node = find_node_for_cell(step, column, sample_to_play);
if (target_node) {
    bool is_same_node = (currently_playing_nodes_per_col[column] == target_node);
    
    if (!is_same_node) {
        // Fade out previous node, fade in new node
        if (currently_playing_nodes_per_col[column]) {
            set_target_volume(currently_playing_nodes_per_col[column], 0.0f);
        }
        set_target_volume(target_node, target_node->volume);
        currently_playing_nodes_per_col[column] = target_node;
    } else {
        // Same node - restart from beginning
        ma_decoder_seek_to_pcm_frame(&target_node->decoder, 0);
        set_target_volume(target_node, target_node->volume);
    }
}
```

This architecture provides smooth, click-free playback with efficient resource management, professional audio quality, and real-time control updates for both volume and pitch.
