## Sequencer Snapshot (Flutter-side JSON)

### Overview

- Centralized composite snapshot for the entire sequencer state.
- Powers Undo/Redo by providing a consistent, module-wide snapshot.
- JSON import/export is handled in Flutter; native exposes one single authoritative state struct per module via FFI (with seqlock prefix).
- Replaces any table-specific JSON export/import. There is one source of truth for snapshot composition and JSON shape.

### Native Types and APIs

 - `SequencerSnapshot`
  - `TableState table` (single state)
  - `PlaybackState playback` (single state)
  - `SampleBankState sample_bank` (single state)

 - Functions (C exports)
  - `void sequencer_capture_snapshot(SequencerSnapshot* out)`
    - Captures the current native state of all modules into `out`.
  - `void sequencer_apply_snapshot(const SequencerSnapshot* s)`
    - Applies a composite snapshot back to native modules (table → playback → sample bank order).

### JSON Layout (High-Level)

Top-level object contains three sections: `table`, `playback`, and `sampleBank`.

- `table`
  - `sectionsCount: number`
  - `sections: [ { start_step: number, num_steps: number }, ... ]`
  - `layers: [ [len, len, len, len], ... ]  // one row per section`
  - `tableCells: [ [ { sampleSlot, volume, pitch }, ... MAX_COLS ], ... activeRows ]`

- `playback`
  - `bpm: number`
  - `regionStart: number`, `regionEnd: number`
  - `songMode: number`
  - `currentSection: number`, `currentSectionLoop: number`
  - `sectionsLoopsNum: [number; MAX_SECTIONS]`

- `sampleBank`
  - `maxSlots: number`
  - `samples: [ { slot, loaded, volume, pitch, filePath, displayName, sampleId }, ... MAX_SAMPLE_SLOTS ]`

Notes:
- Transient transport like `is_playing` and `current_step` are intentionally omitted from the snapshot/JSON to avoid unintended transport side‑effects when applying.
- The `tableCells` grid includes only active rows (sum of section lengths), not the entire `MAX_SEQUENCER_STEPS`.

### Flutter Usage

Compose JSON on Flutter by reading native state via module FFI and serializing.

### Rationale

- One composite snapshot avoids divergence across modules and ensures consistent state for Undo/Redo and export.
- JSON building is centralized and easy to extend by editing a single place.
- Table-level JSON helpers were removed to reduce duplication and ambiguity.

### Deprecations

- Removed native JSON functions; JSON is Flutter-only now.


