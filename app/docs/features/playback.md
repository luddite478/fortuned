## Playback Engine: Implementation and Core Ideas

This document summarizes the current playback engine implementation, the realtime data flow between native and Flutter, and the core ideas behind the design. It complements the shared pattern in `app/docs/native_state_sync_pattern.md`.

### Goals

- **Low-latency, glitch-free playback** using a lock-free audio callback
- **Smooth transitions** when rapidly triggering samples in a sequencer
- **Deterministic timing** with sample-accurate step advances
- **Efficient UI syncing** via a zero-copy read-only single state exposed to Flutter

## Architecture Overview

### Audio Backend (miniaudio)

- Uses miniaudio’s CoreAudio backend on iOS and appropriate backends on other platforms
- A single global `ma_node_graph` feeds the audio device
- The device’s `audio_callback` drives sequencing and audio graph reads

Key globals in `app/native/playback.mm`:
- `g_device`: miniaudio device
- `g_nodeGraph`: miniaudio node graph root
- `g_initialized`: init guard

### Column Nodes (A/B Switching)

- Each sequencer column has two nodes: A and B, represented by `MAColumnNodes`
- The engine alternates between A and B when retriggering a sample on the same column to avoid cut-offs and clicks
- Each node owns its own decoder and `ma_data_source_node`, attached to the graph endpoint

When setting up a node for a step:
- If the node is already initialized with the same sample, pitch policy applies:
  - With preprocessing (default): if pitch changed or not yet bound to preprocessed cache, rebuild the node; if same pitch and cache is bound, seek to start and reuse
  - With realtime resampler (optional): update pitch in-place and seek to start
- Otherwise, the previous node is torn down and a new decoder/node pair is created and attached to the endpoint

### Volume Smoothing (Exponential)

- Separate rise/fall coefficients provide fast attacks and controlled releases
- Smoothing is applied every callback via `update_volume_smoothing()` and pushed to the miniaudio node’s output bus
- Nodes are auto-stopped when both target and current volume stay under a small threshold

Time constants (see `app/native/playback.h`):
- `VOLUME_RISE_TIME_MS = 6ms`
- `VOLUME_FALL_TIME_MS = 12ms`
- `VOLUME_THRESHOLD = 0.0001f`

### Sequencer Timing

- Timing is based on frames-per-step computed from BPM: `framesPerStep = (sampleRate * 60) / (bpm * 4)` for 1/16 notes
- `run_sequencer(frameCount)` increments an internal frame counter and advances steps when the threshold is reached
- On step advance:
  - Current step is updated with region wrapping
  - `play_samples_for_step(step)` triggers column nodes
  - The single state’s `current_step` and `is_playing` are updated using the seqlock writer pattern

### Playback Region and Mode

- Two modes:
  - **Loop**: loop a selected section's range
  - **Song**: span all sections end-to-end, with per-section loop counts
- `playback_set_region(start, end)` sets inclusive start and exclusive end
- `playback_set_mode(song_mode)` switches between song/loop and recomputes the active region using `table` queries

### Section Loops (Song Mode)

In song mode, each section can be configured to loop a specific number of times before advancing to the next section:

- After completing all loops of the final section, playback stops
- Current section and loop progress are tracked and exposed to Flutter

Functions:
- `playback_set_section_loops_num(int section, int loops)`: Set loop count for a section

The sequencer tracks:
- `g_current_section`: Which section is currently playing
- `g_current_section_loop`: Current loop within the section (0-based)
- `sections_loops_num_storage[MAX_SECTIONS]`: Per-section loop counts

## Single State (Native → Flutter)

The engine exposes one read-only state struct via FFI that Flutter reads using the seqlock reader pattern. The FFI-visible prefix (version + scalars + pointer views) is updated in small, bounded critical sections on the audio thread.

State struct (see `app/native/playback.h`):

```
typedef struct {
    uint32_t version;               // even=stable, odd=writer in progress
    int is_playing;                 // 0/1
    int current_step;               // current sequencer step
    int bpm;                        // current BPM
    int region_start;               // inclusive start of playback region
    int region_end;                 // exclusive end of playback region
    int song_mode;                  // 0=loop, 1=song
    int* sections_loops_num;        // &sections_loops_num_storage[0]
    int current_section;            // current section being played
    int current_section_loop;       // current loop within section (0-based)

    int sections_loops_num_storage[MAX_SECTIONS];
} PlaybackState;
```

Writer usage (simplified; see `playback.mm`):

```
static inline void state_write_begin() { g_playback_state.version++; }
static inline void state_write_end()   { g_playback_state.version++; }
static inline void state_update_prefix() {
  g_playback_state.is_playing = g_sequencer_playing;
  g_playback_state.current_step = g_current_step;
  g_playback_state.sections_loops_num = &g_playback_state.sections_loops_num_storage[0];
}
```

The writer wraps updates with `state_write_begin()` and `state_write_end()` on:
- Initialization, start/stop, BPM/region/mode changes
- Each step advance inside the callback (for `current_step`)

The reader (Flutter) mirrors the prefix fields exactly, reads twice with version checks, and only accepts on an even, equal version.

## Native API Surface (exported)

Core functions (see `app/native/playback.h`):
- `int playback_init(void);`
- `void playback_cleanup(void);`
- `int playback_start(int bpm, int start_step);`
- `void playback_stop(void);`
- `int playback_is_playing(void);` (if exposed)
- `void playback_set_bpm(int bpm);`
- `void playback_set_region(int start, int end);`
- `void playback_set_mode(int song_mode);`
- `void playback_set_section_loops_num(int section, int loops);`
- `const PlaybackState* playback_get_state_ptr(void);`

Supporting sample-bank calls are forward-declared in `playback.h` and implemented in `app/native/sample_bank.mm`.

## Flutter Integration

On the Flutter side:
- `app/lib/ffi/playback_bindings.dart` mirrors `PlaybackState` prefix in `NativePlaybackState`
- `app/lib/state/sequencer/playback.dart` implements `syncPlaybackState()` using the seqlock reader pattern and updates `ValueNotifier`s in a single pass, then calls `notifyListeners()` once
- A periodic timer (e.g., ~16ms) can drive `syncPlaybackState()` to keep UI responsive without overloading the main thread

## Design Principles

- **Lock-free audio path**: No mutexes in the callback; seqlock snapshot ensures safe cross-thread reads
- **Zero-copy UI sync**: Flutter reads a stable pointer to a native struct; no allocations per frame
- **Seqlock pattern**: All state exposed via snapshot, no individual getters - native is source of truth
- **A/B node switching**: Avoids abrupt cutoffs and enables rapid retriggers without artifacts
- **Exponential smoothing**: Clean volume ramps with distinct attack/release behavior
- **Deterministic timing**: Step timing derived from sample rate and BPM for stable sequencing

## Resource Management & Lifecycle

- All miniaudio objects (device, node graph, nodes, decoders) are created outside performance-critical paths when possible
- `playback_cleanup()` tears down nodes/decoders, stops the device, uninitializes the graph, and updates the public snapshot to reflect stopped state
- Per-column nodes are uninitialized safely when replaced or when playback stops

## Extending the System

To add a new public playback field:
1. Extend `PublicPlaybackState` in `playback.h`
2. Update `public_state_update()` in `playback.mm`
3. Update the Dart FFI struct in `app/lib/ffi/playback_bindings.dart`
4. Add read/compare logic in `app/lib/state/sequencer/playback.dart` and propagate changes via notifiers

Example: Section loops feature adds per-section loop counts in song mode, tracking current section and loop progress. The entire sections loops array is exposed via pointer for flexible access, with UI controls adjusting values through setters while state syncs through the seqlock pattern.

Other extension ideas:
- Per-column DSP (filters, panning) via additional nodes
- Per-step swing/humanization in `run_sequencer()`
- Parameter automation lanes that modulate smoothing targets

## Platform Notes

- iOS build defines specific miniaudio flags and avoids AVFoundation-side defaults that can force speaker routing; see `playback.mm` preprocessor section for details
- Miniaudio implementation is compiled in `app/native/miniaudio_impl.mm`; headers are included where needed

## References

- Pattern details: `app/docs/native_state_sync_pattern.md`
- Playback engine: `app/native/playback.h`, `app/native/playback.mm`
- Flutter bindings/state: `app/lib/ffi/playback_bindings.dart`, `app/lib/state/sequencer/playback.dart`

