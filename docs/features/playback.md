# 🎵 Audio Playback Implementation

**Per-cell node architecture using miniaudio's node graph for perfect polyphonic mixing**

## Core Architecture

The audio system uses **individual nodes per playing cell** following miniaudio's node graph best practices. Each triggered grid cell creates its own independent audio pipeline that automatically mixes with all other playing cells.

### Per-Cell Node Structure
```c
typedef struct {
    int active;                    // Node status
    int step, column, sample_slot; // Grid position and sample reference
    ma_decoder decoder;            // Independent audio decoder
    ma_pitch_data_source pitch_ds; // Pitch shifting layer
    ma_data_source_node node;      // Individual node in graph
    float volume, pitch;           // Cell-specific controls
    uint64_t id;                   // Unique identifier
    int node_initialized, pitch_ds_initialized;
} cell_node_t;
```

### Audio Flow Architecture
```
Sample File → Decoder → Pitch Data Source → Data Source Node → Node Graph → Output
     ↑             ↑            ↑                 ↑              ↑
   File/Memory   Format     Pitch Shift       Node Graph     Automatic
   Loading      Conversion   Processing        Mixing         Mixing
```

## Node Graph Implementation

**Following miniaudio's node graph pattern:**
- **512 simultaneous voices** - `MAX_ACTIVE_CELL_NODES = 512`
- **Cell node pool** - Pre-allocated `g_cell_nodes[512]` array
- **Individual nodes** - Each cell gets `ma_data_source_node` connected to endpoint
- **Automatic mixing** - Node graph handles all audio mixing internally
- **Lifecycle management** - Nodes auto-cleanup when playback finishes

### Key Functions
```c
// Create new cell node for triggered grid cell
cell_node_t* create_cell_node(int step, int column, int sample_slot, float volume, float pitch)

// Find available node from pool
cell_node_t* find_available_cell_node(void)

// Clean up finished nodes automatically
void cleanup_finished_cell_nodes(void)
```

## Playback Systems

### 1. Sequencer Grid Playback (Per-Cell Nodes)
- **Trigger**: Grid cell activated during sequencer playback
- **Creates**: New `cell_node_t` with independent audio pipeline
- **Benefits**: Perfect mixing when multiple cells play same sample
- **Cleanup**: Automatic when sample finishes playing

### 2. Sample Bank Playback (Manual Triggers)
- **Trigger**: User clicks play button on sample bank
- **Uses**: Dedicated sample bank audio pipeline per slot
- **Independence**: Completely separate from sequencer grid
- **Pipeline**: `decoder → pitch_ds → data_source_node → node_graph`

### 3. Preview Systems
**Two dedicated preview systems with their own audio nodes:**

#### Sample Preview (File Browser)
```c
static preview_system_t g_sample_preview;  // For previewing samples before adding to banks
```
- **Purpose**: Preview audio files in sample browser
- **Trigger**: User taps sample in file browser
- **Pipeline**: File → decoder → pitch_ds → node → endpoint

#### Cell Preview (Grid Cells)  
```c
static preview_system_t g_cell_preview;    // For previewing individual grid cells
```
- **Purpose**: Preview specific grid cell content
- **Trigger**: User previews cell settings
- **Pipeline**: Memory/File → decoder → pitch_ds → node → endpoint

**Both preview systems:**
- Use dedicated audio nodes independent of all other playback
- Support pitch control for preview matching
- Auto-stop when new preview starts
- Clean resource management

## Performance Benefits

### Perfect Polyphonic Mixing
- **Multiple cells, same sample**: No interference or audio artifacts
- **Overlapping triggers**: Each gets independent audio node
- **Pitch variations**: Each cell can have different pitch simultaneously

### Resource Efficiency  
- **Node pooling**: Pre-allocated node pool prevents allocation overhead
- **Memory sharing**: Multiple nodes can reference same sample data
- **Automatic cleanup**: Finished nodes automatically return to pool

### Real-time Performance
- **No blocking**: Cell creation/cleanup never blocks audio thread
- **Frame-accurate timing**: Sample triggers aligned to audio frames
- **Low latency**: Minimal processing overhead per node

## Integration with Node Graph

**Following [miniaudio node graph documentation](https://miniaud.io/docs/examples/node_graph.html):**
```c
// Initialize node graph
ma_node_graph_config nodeGraphConfig = ma_node_graph_config_init(CHANNEL_COUNT);
ma_node_graph_init(&nodeGraphConfig, NULL, &g_nodeGraph);

// Each cell node connects to endpoint
ma_node_attach_output_bus(&cell->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);

// Audio callback reads from graph
ma_node_graph_read_pcm_frames(&g_nodeGraph, pOutput, frameCount, NULL);
```

## Technical Implementation

### Cell Node Creation (Sequencer Triggers)
```c
// In play_samples_for_step():
for (int column = 0; column < g_columns; column++) {
    int sample_to_play = g_sequencer_grid[step][column];
    if (sample_to_play >= 0) {
        // Volume/pitch resolution (cell overrides sample bank)
        float final_volume = (cell_volume != 1.0f) ? cell_volume : bank_volume;
        float final_pitch = (cell_pitch != 1.0f) ? cell_pitch : bank_pitch;
        
        // Create new independent cell node
        cell_node_t* cell_node = create_cell_node(step, column, sample_to_play, final_volume, final_pitch);
    }
}
```

### Column-Based Silencing
```c
// Silence existing nodes in column before triggering new sample
silence_cell_nodes_in_column(column);

// Sets volume to 0 instantly without destroying nodes:
ma_node_set_output_bus_volume(&cell->node, 0, 0.0f);
```
- **Immediate silencing**: Previous samples in column stop instantly when new sample triggers
- **No audio artifacts**: Volume-based silencing avoids clicks/pops from abrupt node cleanup
- **Clean pipeline**: Silenced nodes continue processing at 0 volume until natural completion
- **Automatic disposal**: Normal cleanup mechanism handles silenced nodes when finished

### Automatic Resource Cleanup
```c
// In audio callback:
cleanup_finished_cell_nodes();  // Called every ~11ms

// Checks decoder position for completion:
ma_decoder_get_cursor_in_pcm_frames(&cell->decoder, &cursor);
ma_decoder_get_length_in_pcm_frames(&cell->decoder, &length);
if (cursor >= length) {
    cleanup_cell_node(cell);  // Return to pool
}
```

This architecture provides perfect polyphonic playback with automatic mixing, following miniaudio's recommended patterns for complex audio applications.
