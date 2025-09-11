# 🎵 Pitch Shifting Implementation

**Pitch processing via SoundTouch preprocessing by default, with optional miniaudio resampler, integrated with A/B column node architecture**

## Overview

The pitch system provides pitch processing for all audio playback through a dedicated pitch data source layer. Each audio pipeline includes pitch processing between the decoder and the node graph connection.

**Key Features:**
- ✅ **Per-cell pitch control** - Each grid cell can have independent pitch
- ✅ **Sample bank pitch** - Global pitch per sample slot  
- ✅ **Default: SoundTouch preprocessing** - High-quality offline pitch with async caching
- ✅ **Optional: Miniaudio resampler** - Real-time resampling when explicitly selected
- ✅ **10-octave range** - C0 to C10 (pitch ratios 0.03125 to 32.0)
- ✅ **Node-graph integration** - Seamless with A/B column node architecture
- ✅ **UI/Native conversion** - Automatic conversion between UI sliders and pitch ratios
- ✅ **Reset to defaults** - Ability to reset cell overrides to sample bank settings

## Audio Pipeline Integration

### Complete Audio Flow
```
Sample File → Decoder → Pitch Data Source → Data Source Node → Node Graph → Output
                           ↑
                     Pitch Processing
                     (Preprocess by default)
```

### A/B Column Node Architecture
```c
typedef struct {
    ma_decoder decoder;            // Audio decoder
    /* pitch_ds is a wrapper data source that either:
       - uses a preprocessed, memory-backed decoder (preferred), or
       - reads from the original decoder (unpitched) until cache is ready,
       - or, if explicitly enabled, resamples in real-time. */
    ma_data_source* pitch_ds;      // Pitch processing layer
    ma_data_source_node node;      // Node graph connection
    float pitch;                   // Current pitch value (as ratio)
    int pitch_ds_initialized;      // Initialization flag
} ma_column_node_t;  // A or B node in a column pair
```

## Pitch Data Source Implementation

### Core Structure
The pitch layer is implemented as a custom `ma_data_source` that wraps the original decoder. In preprocessing mode, it swaps in a memory-backed audio buffer (`ma_audio_buffer`) for preprocessed PCM when available.

### Optional Method: Miniaudio Resampler (explicit)
If the pitch method is explicitly set to resampler, the pitch layer applies real-time resampling using an inverted sample-rate calculation:

```c
target_sample_rate = (ma_uint32)(sampleRate / pitchRatio);
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

### 2. Pitch Change Policy
```c
// Preprocessing (default):
//  - If pitch changed, or not yet bound to preprocessed data → rebuild node to bind correct cache
//  - If same pitch and already preprocessed → reuse by seeking to start

// Miniaudio resampler (optional):
//  - Update pitch in-place via data source and seek to start for immediate changes
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

### SoundTouch Preprocessing Method (default)
With preprocessing, each unique pitch for a sample is rendered offline in a background thread and cached in memory. When a node needs to change pitch (e.g., a new trigger with a different pitch), the node is rebuilt to pick up the correct preprocessed audio.

**Key Policy:** In `play_samples_for_step()`, when the same sample is already playing but with a different pitch:
- **Preprocessing (default)**: Rebuild the entire node with `setup_column_node()` to bind the correct preprocessed audio
- **Resampler (optional)**: Update the pitch data source directly for immediate changes

This ensures proper pitch data source initialization for each pitch value.

### Pitch Data Source Read Behavior
- **Preprocessing (default)**:
  - If cache exists: read from the preprocessed `ma_audio_buffer` (PCM in RAM).
  - If cache missing: read unpitched from the original decoder while a background job renders and caches the requested pitch; subsequent triggers use the cache.
- **Resampler (optional)**: read from original decoder and resample in real-time (only when explicitly selected).

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

## Performance Optimizations

### Async Preprocessing (Background Threading)
```cpp
// SoundTouch preprocessing runs in background threads (max 4)
if (!preprocessed && fabs(pitch - 1.0f) > 0.001f) {
    start_async_preprocessing(sample_slot, pitch);  // ← Background thread
    // Playback continues unpitched until cache is ready
}
```

**Benefits:**
- **UI Responsiveness**: No blocking during SoundTouch preprocessing
- **Seamless Triggers**: Plays original pitch immediately; caches target pitch for next trigger
- **Future Performance**: Subsequent uses get cached high-quality version

### Native Call Debouncing (Dart Layer)
```dart
// 50ms debouncing prevents performance issues from rapid UI changes
_debouncedNativePitchCall('sample_$sampleIndex', pitch, () {
  _sequencerLibrary.setSampleBankPitch(sampleIndex, pitch);
  _previewSampleWithNewPitch(sampleIndex, pitch);
});

// UI updates immediately, native calls are throttled
_samplePitchNotifiers[sampleIndex]?.value = pitch; // ← Instant UI feedback
```

**Benefits:**
- **Smooth Sliders**: UI responds instantly without lag
- **Reduced Native Load**: Max 1 call per 50ms instead of dozens
- **Smart Batching**: Only latest value sent to native code

## Performance Characteristics

- **Default algorithm**: SoundTouch offline preprocessing (high quality)
- **Optional algorithm**: Linear interpolation resampling via `ma_resampler` (explicit opt-in)
- **Memory**: Cache uses additional memory per unique (sample, pitch)
- **Latency**: Immediate playback starts at original pitch if cache is not ready; no blocking on UI thread
- **Concurrent**: Each cell/node is independent; up to 4 preprocessing jobs run concurrently
- **Real-time updates**: Preprocessing method rebuilds on next trigger; resampler method updates instantly
- **Debouncing**: Native calls can be throttled on the Dart side to reduce churn

This implementation provides seamless pitch shifting integrated with the per-cell node architecture, enabling independent pitch control for every playing audio instance with optimal performance and UI responsiveness. 