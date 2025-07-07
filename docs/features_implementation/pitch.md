# 🎵 Pitch Shifting Implementation

**Real-time pitch shifting for samples using miniaudio's resampler system**

## Overview

The pitch shifting system allows changing the pitch of samples in real-time without affecting the tempo of the sequencer. Each sample can have a global pitch setting (sample bank pitch) and individual cells can override this with their own pitch values.

**Key Features:**
- ✅ **Sample-based pitch shifting** - Classic tracker/sampler approach
- ✅ **Real-time processing** - No latency, applied during playback
- ✅ **10-octave range** - C0 to C10 (pitch ratios 0.03125 to 32.0)
- ✅ **Per-sample and per-cell control** - Hierarchical pitch system
- ✅ **Node-graph integration** - Works seamlessly with the mixing system

## Technical Implementation

### Core Architecture

```c
// Pitch data source wrapper using miniaudio resampler
typedef struct {
    ma_data_source_base ds;
    ma_data_source* original_ds;
    float pitch_ratio;
    ma_uint32 channels;
    ma_uint32 sample_rate;
    
    // Use miniaudio resampler for pitch shifting
    ma_resampler resampler;
    int resampler_initialized;
    ma_uint32 target_sample_rate;  // Calculated from pitch ratio
} ma_pitch_data_source;
```

### Resampler-Based Pitch Shifting

The implementation uses **miniaudio's `ma_resampler`** for pitch shifting by treating it as a sample rate conversion problem:

**Theory:**
- **Higher pitch** = play sample faster = downsample to lower target rate
- **Lower pitch** = play sample slower = upsample to higher target rate

**Implementation:**
```c
// INVERTED calculation (empirically determined):
// Higher pitch ratio = lower target sample rate (faster playback)
// Lower pitch ratio = higher target sample rate (slower playback)
pPitch->target_sample_rate = (ma_uint32)(sampleRate / pitchRatio);
```

**Example:**
- **2.0x pitch** (1 octave up): 48000 Hz → 24000 Hz target
- **0.5x pitch** (1 octave down): 48000 Hz → 96000 Hz target

### Pitch Data Source Implementation

Each sample slot has its own `ma_pitch_data_source` that wraps the original decoder:

```c
// Initialize resampler for pitch shifting
ma_resampler_config resamplerConfig = ma_resampler_config_init(
    SAMPLE_FORMAT,                // ma_format_f32
    channels,                     // 2 (stereo)
    sampleRate,                   // 48000 Hz (input)
    target_sample_rate,           // Calculated from pitch ratio
    ma_resample_algorithm_linear  // Fast linear interpolation
);

ma_result result = ma_resampler_init(&resamplerConfig, NULL, &pPitch->resampler);
```

### Real-time Processing

The pitch data source reads and processes audio in real-time:

```c
static ma_result ma_pitch_data_source_read(ma_data_source* pDataSource, 
                                          void* pFramesOut, 
                                          ma_uint64 frameCount, 
                                          ma_uint64* pFramesRead) {
    // 1. Estimate input frames needed based on pitch ratio
    ma_uint64 inputFramesNeeded = (ma_uint64)(frameCount / pPitch->pitch_ratio);
    
    // 2. Read from original data source
    ma_result result = ma_data_source_read_pcm_frames(pPitch->original_ds, 
                                                     tempInputBuffer, 
                                                     inputFramesNeeded, 
                                                     &inputFramesRead);
    
    // 3. Process through resampler
    result = ma_resampler_process_pcm_frames(&pPitch->resampler, 
                                           tempInputBuffer, 
                                           &inputFramesToProcess, 
                                           pFramesOut, 
                                           &outputFramesProcessed);
    
    *pFramesRead = outputFramesProcessed;
    return result;
}
```

## Integration with Node Graph

The pitch data source integrates seamlessly with miniaudio's node graph system:

```c
// Each slot has: decoder → pitch_data_source → data_source_node → node_graph
audio_slot_t* slot = &g_slots[slot_index];

// 1. Initialize pitch data source around decoder
ma_pitch_data_source_init(&slot->pitch_ds, &slot->decoder, pitch_ratio, channels, sample_rate);

// 2. Create data source node wrapping pitch data source
ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(&slot->pitch_ds);
ma_data_source_node_init(&g_nodeGraph, &nodeConfig, NULL, &slot->node);

// 3. Connect to graph endpoint
ma_node_attach_output_bus(&slot->node, 0, ma_node_graph_get_endpoint(&g_nodeGraph), 0);
```

## Pitch Control Hierarchy

The system supports two levels of pitch control:

### 1. Sample Bank Pitch (Global)
- **Scope**: Affects all instances of a sample across the grid
- **Range**: C0 to C10 (0.03125 to 32.0 ratio)
- **Storage**: `g_slots[bank].pitch`
- **API**: `set_sample_bank_pitch(bank, pitch)`

### 2. Cell Pitch (Per-Cell Override)
- **Scope**: Affects only specific grid cells
- **Priority**: Overrides sample bank pitch when set
- **Storage**: `g_sequencer_grid_pitches[step][column]`
- **API**: `set_cell_pitch(step, column, pitch)`

### Pitch Resolution Logic
```c
// In sequencer playback:
float bank_pitch = sample->pitch;
float cell_pitch = g_sequencer_grid_pitches[step][column];
float final_pitch = (cell_pitch != 1.0f) ? cell_pitch : bank_pitch;

// Apply to pitch data source
ma_pitch_data_source_set_pitch(&sample->pitch_ds, final_pitch);
```

## UI Integration

### Musical Notes Mapping
The UI uses `lib/utils/musical_notes.dart` for musical note conversion:

```dart
// Convert slider position (0-120) to pitch multiplier
double sliderPositionToPitchMultiplier(int position) {
  final semitonesFromCenter = position - 60; // C5 = center
  return math.pow(2.0, semitonesFromCenter / 12.0).toDouble();
}

// Examples:
// C5 (position 60) → 1.0 (no change)
// C6 (position 72) → 2.0 (1 octave up)
// C4 (position 48) → 0.5 (1 octave down)
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
  _cellPitches[cellIndex] = pitch.clamp(0.03125, 32.0);
  final row = cellIndex ~/ _gridColumns;
  final col = cellIndex % _gridColumns;
  final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
  _sequencerLibrary.setCellPitch(row, absoluteColumn, pitch);
  notifyListeners();
}
```

## Performance Characteristics

### Computational Cost
- **Algorithm**: Linear interpolation resampling
- **Quality**: Good for real-time use, excellent performance
- **Memory**: Minimal overhead (~100 bytes per slot)
- **Latency**: No additional latency beyond normal audio buffering

### Memory Management
- **Resampler Cleanup**: Properly uninitializes when slots are freed
- **Dynamic Updates**: Can change pitch in real-time without audio glitches
- **Resource Limits**: Shares the same 1024-slot limit as the main audio system

## References

### Miniaudio Documentation
- **Resampling**: [Section 10.3 - Resampling](https://miniaud.io/docs/manual/index.html#resampling)
- **Node Graph**: [Section 9 - Node Graph](https://miniaud.io/docs/manual/index.html#node-graph)
- **Data Sources**: [Section 8 - Data Sources](https://miniaud.io/docs/manual/index.html#data-sources)

### Key Miniaudio APIs Used
```c
// Resampler initialization
ma_resampler_config ma_resampler_config_init(format, channels, inputRate, outputRate, algorithm);
ma_result ma_resampler_init(const ma_resampler_config* pConfig, pResampler);

// Real-time processing
ma_result ma_resampler_process_pcm_frames(pResampler, pFramesIn, pFrameCountIn, pFramesOut, pFrameCountOut);

// Cleanup
void ma_resampler_uninit(ma_resampler* pResampler);
```

## Troubleshooting

### Common Issues

**1. No audio after pitch change**
- Check if resampler initialization succeeded
- Verify pitch ratio is within valid range (0.03125 to 32.0)
- Ensure target sample rate is within reasonable bounds (8000-192000 Hz)

**2. Audio glitches during pitch changes**
- Resampler is reinitialized on every pitch change for simplicity
- Brief audio interruption is expected and normal

**3. Pitch direction reversed**
- The implementation uses inverted calculation empirically determined
- Higher pitch ratios result in lower target sample rates (faster playback)

### Debug Logging
```c
prnt("✅ [PITCH] Initialized resampler: %.2fx pitch (rate: %d -> %d Hz)", 
     pitchRatio, sampleRate, target_sample_rate);
prnt("🎵 [PITCH] Updated resampler: %.2fx pitch (rate: %d -> %d Hz)", 
     pitchRatio, sample_rate, target_sample_rate);
```

## Future Enhancements

### Potential Improvements
- **Higher Quality**: Switch to `ma_resample_algorithm_custom` for better quality
- **Formant Preservation**: Add formant correction for vocal samples
- **Granular Synthesis**: Implement time-stretching independent of pitch
- **Real-time Updates**: Smooth pitch transitions without resampler recreation 