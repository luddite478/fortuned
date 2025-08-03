# 🎵 Pitch Shifting Implementation

**Real-time pitch shifting using miniaudio's resampler, integrated with A/B column node architecture**

## Overview

The pitch system provides real-time pitch shifting for all audio playback through a dedicated pitch data source layer. Each audio pipeline includes pitch processing between the decoder and the node graph connection.

**Key Features:**
- ✅ **Per-cell pitch control** - Each grid cell can have independent pitch
- ✅ **Sample bank pitch** - Global pitch per sample slot  
- ✅ **Real-time processing** - No latency, applied during playback
- ✅ **10-octave range** - C0 to C10 (pitch ratios 0.03125 to 32.0)
- ✅ **Node-graph integration** - Seamless with A/B column node architecture
- ✅ **UI/Native conversion** - Automatic conversion between UI sliders and pitch ratios
- ✅ **Reset to defaults** - Ability to reset cell overrides to sample bank settings

## Audio Pipeline Integration

### Complete Audio Flow
```
Sample File → Decoder → Pitch Data Source → Data Source Node → Node Graph → Output
                           ↑
                    Resampler-based
                    Pitch Shifting
```

### A/B Column Node Architecture
```c
typedef struct {
    ma_decoder decoder;            // Audio decoder
    ma_pitch_data_source pitch_ds; // ← Pitch processing layer
    ma_data_source_node node;      // Node graph connection
    float pitch;                   // Current pitch value (as ratio)
    int pitch_ds_initialized;      // Initialization flag
} column_node_t;  // A or B node in a column pair
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

## Pitch Control Hierarchy

### Sample Bank Pitch (Global)
```c
// API: set_sample_bank_pitch(bank, pitch_ratio)
// Storage: g_slots[bank].pitch
// Scope: Affects all instances of this sample
// Range: 0.03125 to 32.0 (C0 to C10, 1.0 = original pitch)
```

### Cell Pitch (Per-Cell Override)
```c
// API: set_cell_pitch(step, column, pitch_ratio) 
// Storage: g_sequencer_grid_pitches[step][column]
// Scope: Overrides sample bank pitch for specific cell
// Default: DEFAULT_CELL_PITCH (-1.0) = use sample bank setting
```

### Default Value System
```c
// Default values indicating "no override" 
#define DEFAULT_CELL_PITCH -1.0f    // Special value meaning "use sample bank pitch"

// Initialization:
g_sequencer_grid_pitches[step][col] = DEFAULT_CELL_PITCH; // Use sample bank default
```

### Pitch Resolution Logic
```c
// Updated resolution (no longer uses 1.0 as default):
static float resolve_cell_pitch(int step, int column, int sample_slot) {
    audio_slot_t* sample = &g_slots[sample_slot];
    float bank_pitch = sample->pitch;
    float cell_pitch = g_sequencer_grid_pitches[step][column];
    return (cell_pitch != DEFAULT_CELL_PITCH) ? cell_pitch : bank_pitch;
}

// In play_samples_for_step():
float resolved_pitch = resolve_cell_pitch(step, column, sample_to_play);
create_cell_node(step, column, sample_slot, resolved_volume, resolved_pitch);
```

### Reset Functions
```c
// Reset cell to use sample bank default
int reset_cell_pitch(int step, int column) {
    g_sequencer_grid_pitches[step][column] = DEFAULT_CELL_PITCH;
    update_existing_nodes_for_cell(step, column, sample_in_cell);
    return 0;
}
```

## UI/Native Conversion System

### Pitch Value Formats
- **UI Sliders**: 0.0 to 1.0 (where 0.5 = original pitch, 0.0 = -12 semitones, 1.0 = +12 semitones)
- **Native Audio**: 0.03125 to 32.0 (where 1.0 = original pitch, covers C0 to C10)

### Conversion Functions
```c
// Convert UI slider value (0.0-1.0) to pitch ratio (0.03125-32.0)
static float ui_pitch_to_ratio(float ui_pitch) {
    // UI 0.0→-12 semitones, 0.5→0 semitones, 1.0→+12 semitones
    float semitones = ui_pitch * 24.0f - 12.0f;
    return powf(2.0f, semitones / 12.0f);
}

// Convert pitch ratio back to UI value
static float ratio_to_ui_pitch(float ratio) {
    float semitones = 12.0f * log2f(ratio);
    return (semitones + 12.0f) / 24.0f;
}
```

### Flutter Integration
```dart
// PitchConversion utility in sound_settings.dart
class PitchConversion {
  static double uiValueToPitchRatio(double uiValue) {
    final semitones = uiValue * 24.0 - 12.0;
    return math.pow(2.0, semitones / 12.0).toDouble();
  }
  
  static double pitchRatioToUiValue(double ratio) {
    final semitones = 12.0 * (math.log(ratio) / math.ln2);
    return (semitones + 12.0) / 24.0;
  }
}

// Usage in UI callbacks:
pitchGetter: (sequencer, index) => PitchConversion.pitchRatioToUiValue(sequencer.getCellPitch(index)),
pitchSetter: (sequencer, index, uiValue) => sequencer.setCellPitch(index, PitchConversion.uiValueToPitchRatio(uiValue)),
```

## Integration with Playback Systems

### 1. A/B Column Nodes (Sequencer)
```c
// Column node setup with pitch:
int setup_column_node(int column, int node_index, int sample_slot, float volume, float pitch) {
    // 1. Initialize decoder
    ma_decoder_init_memory/file(&node->decoder, ...);
    
    // 2. Wrap decoder with pitch data source
    ma_pitch_data_source_init(&node->pitch_ds, &node->decoder, pitch, channels, sample_rate);
    
    // 3. Create node from pitch data source
    ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &node->node);
    
    // 4. Connect to node graph
    ma_node_attach_output_bus(&node->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
}
```

### 2. Real-time Pitch Updates
```c
// Update pitch for existing column nodes when settings change
static void update_existing_column_nodes_for_cell(int step, int column, int sample_slot) {
    if (column < 0 || column >= g_columns) return;
    column_nodes_t* col_nodes = &g_column_nodes[column];
    
    // Update active node if it's playing this sample
    if (col_nodes->active_node >= 0) {
        column_node_t* active_node = &col_nodes->nodes[col_nodes->active_node];
        if (active_node->sample_slot == sample_slot) {
            float resolved_pitch = resolve_cell_pitch(step, column, sample_slot);
            update_column_node_pitch(active_node, resolved_pitch);
        }
    }
}

// Real-time pitch change for column node
static void update_column_node_pitch(column_node_t* node, float new_pitch) {
    if (!node || !node->pitch_ds_initialized) return;
    node->pitch = new_pitch;
    ma_pitch_data_source_set_pitch(&node->pitch_ds, new_pitch);
}
```

### 3. Sample Bank Playback
- **Same pipeline**: `decoder → pitch_ds → node → graph`
- **Independent**: Separate from sequencer cell nodes
- **Persistent**: Pitch setting applies to manual playback

### 4. Preview Systems  
- **Sample preview**: Supports pitch for accurate preview
- **Cell preview**: Uses cell-specific pitch settings
- **Same architecture**: All use `ma_pitch_data_source`

## Real-time Processing

### SoundTouch Preprocessing Method
With the SoundTouch preprocessing method, each unique pitch requires its own preprocessed audio data. When a node needs to change pitch during playback (e.g., when restarting for a different step with different pitch), the entire node must be rebuilt rather than just updating the pitch data source.

**Key Fix:** In `play_samples_for_step()`, when the same sample is already playing but with a different pitch:
- **For preprocessing method**: Rebuild the entire node with `setup_column_node()`
- **For real-time methods**: Update the pitch data source directly

This ensures proper pitch data source initialization for each pitch value.

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

// Cell-level pitch control (receives UI values, converts to ratios)
void setCellPitch(int cellIndex, double pitchRatio) {
  final row = cellIndex ~/ _gridColumns;
  final col = cellIndex % _gridColumns; 
  final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
  _sequencerLibrary.setCellPitch(row, absoluteColumn, pitchRatio);
  notifyListeners();
}

// Reset cell to use sample bank default
void resetCellPitch(int cellIndex) {
  _cellPitches.remove(cellIndex);
  final row = cellIndex ~/ _gridColumns;
  final col = cellIndex % _gridColumns;
  final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
  _sequencerLibrary.resetCellPitch(row, absoluteColumn);
  notifyListeners();
}
```

## Performance Characteristics

- **Algorithm**: Linear interpolation resampling via `ma_resampler`
- **Quality**: Good for real-time use, excellent performance  
- **Memory**: Minimal overhead per audio pipeline
- **Latency**: No additional latency beyond normal audio buffering
- **Concurrent**: Each cell node processes pitch independently
- **Real-time updates**: Existing nodes update immediately when settings change

This implementation provides seamless pitch shifting integrated with the per-cell node architecture, enabling independent pitch control for every playing audio instance with proper UI/native value conversion and reset capabilities. 