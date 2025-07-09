# 🎵 Pitch Shifting Implementation

**Real-time pitch shifting using miniaudio's resampler, integrated with per-cell node architecture**

## Overview

The pitch system provides real-time pitch shifting for all audio playback through a dedicated pitch data source layer. Each audio pipeline includes pitch processing between the decoder and the node graph connection.

**Key Features:**
- ✅ **Per-cell pitch control** - Each grid cell can have independent pitch
- ✅ **Sample bank pitch** - Global pitch per sample slot  
- ✅ **Real-time processing** - No latency, applied during playback
- ✅ **10-octave range** - C0 to C10 (pitch ratios 0.03125 to 32.0)
- ✅ **Node-graph integration** - Seamless with per-cell node architecture

## Audio Pipeline Integration

### Complete Audio Flow
```
Sample File → Decoder → Pitch Data Source → Data Source Node → Node Graph → Output
                           ↑
                    Resampler-based
                    Pitch Shifting
```

### Per-Cell Node Architecture
```c
typedef struct {
    ma_decoder decoder;            // Audio decoder
    ma_pitch_data_source pitch_ds; // ← Pitch processing layer
    ma_data_source_node node;      // Node graph connection
    float pitch;                   // Current pitch value
    int pitch_ds_initialized;      // Initialization flag
} cell_node_t;
```

## Pitch Data Source Implementation

### Core Structure
```c
typedef struct {
    ma_data_source_base ds;
    ma_data_source* original_ds;    // Wrapped decoder
    float pitch_ratio;              // Current pitch multiplier
    ma_resampler resampler;         // miniaudio resampler
    int resampler_initialized;
} ma_pitch_data_source;
```

### Resampler-Based Pitch Shifting
**Uses miniaudio's `ma_resampler` for pitch shifting:**
- **Higher pitch** = lower target sample rate = faster playback
- **Lower pitch** = higher target sample rate = slower playback

```c
// Inverted calculation (empirically determined):
target_sample_rate = (ma_uint32)(sampleRate / pitchRatio);

// Examples:
// 2.0x pitch (1 octave up): 48000 Hz → 24000 Hz target
// 0.5x pitch (1 octave down): 48000 Hz → 96000 Hz target
```

## Integration with Playback Systems

### 1. Per-Cell Nodes (Sequencer)
```c
// Cell node creation with pitch:
cell_node_t* create_cell_node(int step, int column, int sample_slot, float volume, float pitch) {
    // 1. Initialize decoder
    ma_decoder_init_memory/file(&cell->decoder, ...);
    
    // 2. Wrap decoder with pitch data source
    ma_pitch_data_source_init(&cell->pitch_ds, &cell->decoder, pitch, channels, sample_rate);
    
    // 3. Create node from pitch data source
    ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &cell->node);
    
    // 4. Connect to node graph
    ma_node_attach_output_bus(&cell->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
}
```

### 2. Sample Bank Playback
- **Same pipeline**: `decoder → pitch_ds → node → graph`
- **Independent**: Separate from sequencer cell nodes
- **Persistent**: Pitch setting applies to manual playback

### 3. Preview Systems  
- **Sample preview**: Supports pitch for accurate preview
- **Cell preview**: Uses cell-specific pitch settings
- **Same architecture**: All use `ma_pitch_data_source`

## Pitch Control Hierarchy

### Sample Bank Pitch (Global)
```c
// API: set_sample_bank_pitch(bank, pitch)
// Storage: g_slots[bank].pitch
// Scope: Affects all instances of this sample
```

### Cell Pitch (Per-Cell Override)
```c
// API: set_cell_pitch(step, column, pitch) 
// Storage: g_sequencer_grid_pitches[step][column]
// Scope: Overrides sample bank pitch for specific cell
```

### Pitch Resolution Logic
```c
// In play_samples_for_step():
float bank_pitch = sample->pitch;
float cell_pitch = g_sequencer_grid_pitches[step][column];
float final_pitch = (cell_pitch != 1.0f) ? cell_pitch : bank_pitch;

// Create cell node with resolved pitch:
create_cell_node(step, column, sample_slot, final_volume, final_pitch);
```

## Real-time Processing

### Pitch Data Source Read Callback
```c
static ma_result ma_pitch_data_source_read(ma_data_source* pDataSource, void* pFramesOut, 
                                          ma_uint64 frameCount, ma_uint64* pFramesRead) {
    // 1. Estimate input frames needed based on pitch ratio
    ma_uint64 inputFramesNeeded = (ma_uint64)(frameCount / pPitch->pitch_ratio);
    
    // 2. Read from original decoder
    ma_data_source_read_pcm_frames(pPitch->original_ds, tempBuffer, inputFramesNeeded, &inputFramesRead);
    
    // 3. Process through resampler (pitch shift)
    ma_resampler_process_pcm_frames(&pPitch->resampler, tempBuffer, &inputFramesToProcess, 
                                   pFramesOut, &outputFramesProcessed);
    
    *pFramesRead = outputFramesProcessed;
    return MA_SUCCESS;
}
```

## UI Integration

### Musical Notes Mapping
```dart
// lib/utils/musical_notes.dart
double sliderPositionToPitchMultiplier(int position) {
  final semitonesFromCenter = position - 60; // C5 = center (position 60)
  return math.pow(2.0, semitonesFromCenter / 12.0).toDouble();
}

// Examples:
// C5 (60) → 1.0   (no change)
// C6 (72) → 2.0   (1 octave up)  
// C4 (48) → 0.5   (1 octave down)
```

### Flutter State Management
```dart
// Sample-level pitch control
void setSamplePitch(int sampleIndex, double pitch) {
  _samplePitches[sampleIndex] = pitch.clamp(0.03125, 32.0);
  _sequencerLibrary.setSampleBankPitch(sampleIndex, pitch);
  notifyListeners();
}

// Cell-level pitch control
void setCellPitch(int cellIndex, double pitch) {
  final row = cellIndex ~/ _gridColumns;
  final col = cellIndex % _gridColumns; 
  _sequencerLibrary.setCellPitch(row, col, pitch);
  notifyListeners();
}
```

## Performance Characteristics

- **Algorithm**: Linear interpolation resampling via `ma_resampler`
- **Quality**: Good for real-time use, excellent performance  
- **Memory**: Minimal overhead per audio pipeline
- **Latency**: No additional latency beyond normal audio buffering
- **Concurrent**: Each cell node processes pitch independently

This implementation provides seamless pitch shifting integrated with the per-cell node architecture, enabling independent pitch control for every playing audio instance. 