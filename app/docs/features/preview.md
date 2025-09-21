## Preview System

This document describes the audio preview system used to play standalone samples and to preview configured cells/samples from the UI without affecting sequencer playback state.

### Goals

- Trigger quick, low-latency previews mixed into the global audio graph
- Reuse the same pitch pipeline (resampler/SoundTouch preprocessing) as playback
- Keep the audio callback lock-free and avoid allocations during mixing

### Architecture Overview

- Native module: `app/native/preview.h` and `app/native/preview.mm`
  - Maintains two lightweight preview contexts:
    - Sample preview (by file path)
    - Cell/sample-slot preview (by slot/step/col with resolved settings)
  - Each context owns its own `ma_decoder` → `ma_pitch_data_source` → `ma_data_source_node`
  - Nodes are attached directly to the global `ma_node_graph` endpoint
  - No volume smoothing for preview; the node volume is set immediately

- Node graph accessor:
  - `playback_get_node_graph()` exported from `playback.mm`
  - Preview module queries the currently active node graph and attaches preview nodes

- Pitch integration:
  - Uses `pitch_ds_create(...)` from `pitch.h`, so the preview benefits from the same preprocessing/cache logic and runtime method (miniaudio resampler / SoundTouch realtime / preprocessed)

- Lifecycle:
  - `preview_init()` is called inside `playback_init()`
  - `preview_cleanup()` is called inside `playback_cleanup()`
  - Preview nodes are created/destroyed outside the audio callback

### Native API (C)

- Initialization and teardown:
  - `int preview_init(void);`
  - `void preview_cleanup(void);`

- Preview actions:
  - `int preview_sample_path(const char* file_path, float pitch, float volume);`
    - Plays an on-disk audio file at the specified pitch/volume
  - `int preview_slot(int slot, float pitch, float volume);`
    - Plays a loaded sample-bank slot at the specified pitch/volume
  - `int preview_cell(int step, int column, float pitch, float volume);`
    - Plays a cell’s sample using absolute step/column indices; pitch/volume passed-in are applied directly
  - `void preview_stop_sample(void);`
  - `void preview_stop_cell(void);`

Return value is `0` on success; negative on error (e.g., decoder init failure).

### Flutter FFI Bindings

Bindings are exposed in `app/lib/ffi/playback_bindings.dart`:

- `int Function(Pointer<Utf8>, double, double) previewSamplePath`
- `int Function(int, double, double) previewSlot`
- `int Function(int, int, double, double) previewCell`
- `void Function() previewStopSample`
- `void Function() previewStopCell`

### UI Integration

1) Sample Browser (preview by file path)

- File entries in `app/lib/widgets/sequencer/v2/sample_selection_widget.dart` preview on tap.
- Since Flutter assets are not true files on disk, the widget loads the asset bytes via `rootBundle.load(...)`, writes to a temporary file (e.g., `/tmp/preview_<name>`), and then calls `previewSamplePath(tempPath, 1.0, 1.0)`.

2) Sound Settings (preview current configuration)

- `app/lib/widgets/sequencer/v2/sound_settings.dart` adds a speaker icon to the header (left of VOL/KEY) for both cell and sample modes.
- Sample settings: calls `previewSlot(activeSlot, pitch, volume)` using the current sample-bank settings.
- Cell settings: computes absolute `step`/`col` from the selected UI cell; resolves effective pitch/volume (cell override or inherited from sample) and calls `previewCell(step, col, effPitch, effVol)`.

### Pitch/Volume Semantics

- Sample preview (`preview_slot`) uses the provided pitch/volume directly (UI supplies current values from notifiers)
- Cell preview (`preview_cell`) resolves overrides first:
  - If cell volume is default, it inherits sample-bank volume
  - If cell pitch is default, it inherits sample-bank pitch

### Filesystem vs Assets

- `ma_decoder_init_file(...)` requires an actual filesystem path.
- For bundled assets, write bytes to a temp file and pass that path to `preview_sample_path(...)`.
- Symptom if skipped: decoder init fails (e.g., `-7`), because the path is not a real file.

### Error Handling & Troubleshooting

- Decoder init failed (`-7`/`MA_DOES_NOT_EXIST`):
  - Ensure the path points to an existing on-disk file
  - For assets, write to a temp file first (as done in the sample browser)

- No audio heard:
  - Confirm device is initialized (`playback_init` was successful)
  - Confirm the sample-bank slot is loaded (when using `preview_slot`/`preview_cell`)
  - Verify volume is non-zero and the node graph is running

### Performance Notes

- Preview uses the same node graph and mixes alongside sequencer nodes
- No smoothing is applied for preview; volume is applied immediately on the output bus
- Pitch method selection and preprocessing/cache are reused via `pitch_ds_create(...)`

### Example Calls

Native (C):

```
// Play a file from disk at unity pitch/volume
preview_sample_path("/tmp/snare.wav", 1.0f, 1.0f);

// Play loaded sample slot C (index 2) one octave up at 50% volume
preview_slot(2, 2.0f, 0.5f);

// Play cell at absolute step 10, column 3 with explicit pitch/volume
preview_cell(10, 3, 0.5f, 0.8f);
```

Dart (FFI):

```
final bindings = PlaybackBindings();
final tmpPath = file.path.toNativeUtf8();
try {
  bindings.previewSamplePath(tmpPath, 1.0, 1.0);
} finally {
  malloc.free(tmpPath);
}

// Preview active slot with current sample settings
bindings.previewSlot(activeSlot, samplePitch, sampleVolume);

// Preview current cell with resolved settings
bindings.previewCell(step, colAbs, effPitch, effVol);
```

### Future Extensions

- Optional smoothing for preview fades
- Pause/seek within preview (e.g., scrubbing)
- Unified preview manager for multiple concurrent previews (currently one per context)


