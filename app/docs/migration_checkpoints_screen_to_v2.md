### Migrate CheckpointsScreen from legacy SequencerState to V2 modular states

This document describes how to migrate `CheckpointsScreen` and its entry points (e.g., the left/right buttons in `MessageBarWidget`) away from the legacy monolithic `SequencerState` toward the V2 modular state architecture (`TableState`, `SampleBankState`, `PlaybackState`, etc.).

### Problem

- Navigation to `CheckpointsScreen` currently throws: “Could not find the correct Provider<SequencerState>…”.
- Root cause: `CheckpointsScreen` depends on `SequencerState` (e.g., `Consumer2<ThreadsState, SequencerState>`, `applySnapshot`, `publishToDatabase`), while V2 pages no longer provide `SequencerState` in the tree.

### Goal

- Remove `SequencerState` dependency from `CheckpointsScreen` without altering UI/UX.
- Reuse separate states for applying checkpoints by introducing a small adapter layer for snapshots.

### Affected files

- `app/lib/screens/checkpoints_screen.dart`
- `app/lib/widgets/sequencer/v2/message_bar_widget.dart` (navigation entry points; no logic change needed)
- `app/lib/state/threads_state.dart` (already has `addCheckpointFromV2`; we will factor snapshot-building)
- New: `app/lib/state/sequencer/snapshot.dart` (proposed)

### Target architecture (V2)

- Display: `CheckpointsScreen` renders from `ThreadsState` only (thread, checkpoints, metadata).
- Actions:
  - Apply checkpoint → map `SequencerSnapshot` to V2 via adapter:
    - `applySnapshot(snapshot, {tableState, sampleBankState, playbackState})`
    - `ThreadsState.publishThreadFromV2(...)` (new convenience wrapper)

### Step-by-step migration

1) Remove legacy dependency in `CheckpointsScreen`
- Delete `import '../state/sequencer_state.dart';`.
- Change top-level consumer:
  - Before: `Consumer2<ThreadsState, SequencerState>`
  - After: `Consumer<ThreadsState>`
- All UI rendering continues to use only `ThreadsState` (no change needed in list, preview, timestamps).

2) Introduce a snapshot adapter (new file)
- Create `app/lib/state/sequencer/snapshot.dart` with two pure functions:
  - `SequencerSnapshot buildSnapshotFromV2(TableState table, SampleBankState bank, PlaybackState pb)`
    - Extract code from `ThreadsState.addCheckpointFromV2` to avoid duplication.
    - Captures current section grid, loaded samples, bpm, and basic metadata.
  - `Future<void> applySnapshot(SequencerSnapshot snap, TableState table, SampleBankState bank, PlaybackState pb)`
    - Clears/recreates sections/rows/cells in `TableState` from `snap.audio.sources[0].sections` (best-effort mapping).
    - Loads/assigns samples into `SampleBankState` when possible (by id/name/path if present).
    - Updates `PlaybackState` (bpm, mode if encoded in metadata) and selects the first section.

3) Update actions in `CheckpointsScreen`
- Apply checkpoint action (`_applyCheckpoint(...)`):
  - Instead of `sequencerState.applySnapshot(...)`, resolve V2 states on demand:
    - `final table = Provider.of<TableState>(context, listen: false);`
    - `final bank = Provider.of<SampleBankState>(context, listen: false);`
    - `final pb = Provider.of<PlaybackState>(context, listen: false);`
  - Call `applySnapshot(checkpoint.snapshot, table, bank, pb)`.
  - Keep the existing confirmation dialog and navigation back.

4) Provider wiring sanity
- Ensure `TableState`, `SampleBankState`, `PlaybackState` are provided in the app tree where `CheckpointsScreen` is pushed (they already are in V2 flows).
- In `CheckpointsScreen`, only resolve these states inside action handlers; continue to render with `ThreadsState` only to minimize rebuilds.

### Mapping details (adapter)

- From V2 → Snapshot (covered by existing `addCheckpointFromV2` logic):
  - Rows/cols: derive from current UI-selected section via `TableState`.
  - Cells: iterate steps/cols; if a cell has `sample_slot >= 0`, record `sample_id/sample_name`.
  - Samples: iterate bank slots; include those loaded with `id/name/url` when available.
  - Metadata: include user id/name (if known), `bpm`, `key`, `time_signature`, timestamp.

- From Snapshot → V2:
  - Sections: create at least one section matching snapshot’s first `AudioSource.sections` layout.
  - Cells: for each row/col, if `cell.sample.hasSample`, map to a sample slot. Strategy:
    - Prefer slot by exact `id` match if you encode slot ids like `slot_#`.
    - Else, try to load by `url`/`name` if available; fall back to first free slot.
  - BPM/mode: set via `PlaybackState.setBpm()` and `setSongMode()` if encoded.
  - Selection: update `TableState.setUiSelectedSection(0)` and ensure `PlaybackState.switchToSection(0)` when appropriate.

### Acceptance criteria

- Navigating to `CheckpointsScreen` (from message bar) no longer requires `Provider<SequencerState>` and does not error.
- Applying a checkpoint restores the grid and samples in V2; BPM is updated.
- No UI regressions in checkpoint list, preview, or navigation.

### Edge cases & notes

- Sample mapping may be partial when snapshot references assets not present on device; log misses and continue.
- Large snapshots may be slow to apply; consider progressive apply (current section first) if needed later.
- Keep adapter pure and stateless; centralize snapshot building so `ThreadsState.addCheckpointFromV2` and publishing reuse the same logic.

### Minimal code touch list (for implementation later)

- `checkpoints_screen.dart`
  - Remove `SequencerState` import and `Consumer2<..., SequencerState>` usages.
  - Replace `applySnapshot` with adapter call.

- `state/sequencer/snapshot.dart`
  - New file with `buildSnapshotFromV2` and `applySnapshot`.

- `state/threads_state.dart`
  - Extract snapshot builder code from `addCheckpointFromV2` into the adapter; call adapter from there.

This plan removes the legacy `SequencerState` dependency from `CheckpointsScreen`, aligns actions with the modular V2 architecture, and keeps UI behavior intact.



