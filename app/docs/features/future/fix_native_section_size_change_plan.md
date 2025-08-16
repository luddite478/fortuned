## Fix: Native Section Size Change Does Not Affect Playback

### Problem
- **Symptom**: Changing rows per section in the UI reflects visually, but playback still wraps at 16 steps.
- **Root cause**: Native uses `g_steps_per_section` to compute loop boundaries and song end, but it is never updated from Flutter when `_gridRows` changes. Dart’s `setSequencerSteps()` is a stub.

### Goals
- **Native playback independence**: Timing, looping, and progression remain native-driven.
- **Accurate boundaries**: Loop/song boundaries update when section rows (`_gridRows`) change, during or outside playback.
- **Single source of truth**: Flutter owns per-section grid contents; native maintains a single continuous table.

## Proposed Changes

### 1) Native API and behavior
- **Add setter** to update steps per section at runtime (and keep internal state consistent):

```c
// sequencer.mm
void set_steps_per_section(int steps) {
    if (steps <= 0 || steps > MAX_SEQUENCER_STEPS) {
        prnt_err("🔴 [SEQUENCER] Invalid steps per section: %d", steps);
        return;
    }
    g_steps_per_section = steps;
    g_sequencer_steps = steps; // keep in lockstep
    g_section_start_step = g_current_section * g_steps_per_section;

    // Ensure total sections constraint fits MAX_SEQUENCER_STEPS
    int maxSections = MAX_SEQUENCER_STEPS / g_steps_per_section;
    if (g_total_sections > maxSections) {
        g_total_sections = maxSections;
        prnt("⚠️ [SEQUENCER] Clamped total sections to %d due to steps/section", g_total_sections);
    }
    prnt("🎵 [SEQUENCER] Steps per section set to %d", steps);
}
```

- **Update start to set both values** so fresh launches don’t rely on previous defaults:

```c
int start_sequencer(int bpm, int steps, int startStep) {
    ...
    g_sequencer_bpm = bpm;
    g_sequencer_steps = steps;
    g_steps_per_section = steps;           // NEW
    g_section_start_step = g_current_section * g_steps_per_section; // NEW
    ...
}
```

- Optional nicety: a single atomic reconfigure to avoid transients when both columns and steps change in one UI action:

```c
void reconfigure_dimensions(int columns, int stepsPerSection) {
    set_columns(columns);
    set_steps_per_section(stepsPerSection);
}
```

### 2) Dart FFI and library
- **Expose binding** for `set_steps_per_section(int)`.
- **Implement** `SequencerLibrary.setSequencerSteps(int steps)` to call the native setter instead of being a no-op.

```dart
// sequencer_library.dart
void setSequencerSteps(int steps) {
  _bindings.set_steps_per_section(steps);
  print('🎵 Set steps per section to $steps');
}
```

### 3) Flutter call sites and ordering
- On any change to `_gridRows` (increase/decrease):
  - Call `sequencerLibrary.setSequencerSteps(_gridRows)` immediately.
  - Keep `configureColumns(numSoundGrids * _gridColumns)`.
  - Rebuild absolute table via `syncFlutterSequencerGridToNativeSequencerGrid()`.
  - Works both while playing and stopped.

- On `startSequencer()`:
  - Call in this order before starting:
    - `setTotalSections(_numSections)`
    - `setSequencerSteps(_gridRows)`
    - `setSongMode(... )`
    - If loop mode: `setCurrentSection(_currentSectionIndex)` (metadata only)
  - Then `startSequencer(_bpm, _gridRows, startAbsoluteStep: ...)`.

- On loading/restoring state or any structural rebuild (e.g., grid count/columns change):
  - Ensure both `setTotalSections(_numSections)` and `setSequencerSteps(_gridRows)` are called once before `syncFlutterSequencerGridToNativeSequencerGrid()`.

## Rationale
- Native loop and song boundaries are derived from `g_steps_per_section`. Without updating it, playback wraps at the default (16), regardless of UI.
- The absolute grid table sync already exists; the missing piece is updating section length in native.

## Runtime considerations
- Updating steps while playing is safe: the engine wraps/end-checks on the next step tick using the new value.
- After a rows change, `setSequencerSteps(_gridRows)` must precede any computations that depend on section boundaries (e.g., `setCurrentSection` metadata recompute).
- If `_numSections * _gridRows` exceeds `MAX_SEQUENCER_STEPS`, native will clamp `g_total_sections`. We can also guard on the Flutter side and warn/prevent exceeding limits.

## Test checklist
- **Loop mode**
  - Set rows to 12, start in section 0: verify wrap at 12.
  - Switch to section 1 while playing: verify wrap at 12, playback unaffected.
  - Change rows 12 → 24 while playing: verify wrap updates immediately at 24.

- **Song mode**
  - 3 sections, rows 8: verify natural stop at 24 steps.
  - Change rows 8 → 16 mid-song: verify end moves to 48 and playback continues to new end.

- **Sync**
  - After rows change, ensure absolute table contains newly added bottom rows (empty cells) and removed rows are ignored by native.
  - Verify columns reconfiguration and cell addressing remain correct.

## Migration notes
- Add new native symbol to FFI bindings: `set_steps_per_section`.
- Implement Dart wrapper and update call sites:
  - `increaseGridRows()` / `decreaseGridRows()`
  - `startSequencer()`
  - Any state load/setup paths that change `_gridRows` or `_numSections`

This aligns UI-driven structural changes with native playback boundaries while keeping native timing and progression independent.







