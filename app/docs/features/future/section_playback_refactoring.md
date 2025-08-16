# Section Playback Refactoring

## Terminology
- Sound Grids: vertical layers (a.k.a. layers) shown in the UI. Each section contains one or more sound grids.
- Grid Cell: a single cell in a sound grid; holds an optional sample slot index (`int?`).

## Problems Identified
1. Two sources of truth for section grids
   - `_soundGridSamples` (working copy) vs `_sectionGridData` (persistence) caused drift and timing bugs when switching sections, especially in song mode auto-advance.
2. Section switch side-effects
   - `_switchToSection` used to save/load and sometimes call native, leading to race conditions and unexpected UI states.
3. Native loop boundary mismatch when starting in loop mode from non-zero section
   - Native loop used `g_current_section` and a fixed `g_steps_per_section = 16`. If not set to the UI section before start, playback wrapped to Section 1.
4. Autosave/undo captured only current section
   - Serializing `soundGridSamples` dropped other sections’ data.
5. Structural changes applied only to current section
   - Add/remove grid and resize rows modified only `_soundGridSamples`, leaving other sections out of sync.

## New Approach
1. Single source of truth
   - `_sectionGridData[int → List<List<int?>>]` stores all section grids.
   - `_soundGridSamples` is a reference to the current section’s lists.
2. UI-only section switching
   - Switch = set index + rebind reference + notify. No native calls, no data copying.
3. Native independence
   - Full sync (Flutter→Native) on app start/structure changes.
   - Per-cell absolute updates on edit. Section switches don’t touch native.
4. Consistent structural updates
   - Add/remove sound grid and grid row resize applied to all sections; current rebinding follows.
5. Correct loop start behavior
   - When starting in loop mode from a non-zero section, call native `set_current_section` before start.

## Implementation Notes
- Sample mapping: absoluteStep = (sectionIndex × gridRows) + row; absoluteColumn = (gridIndex × gridColumns) + col.
- Song mode UI tracking: currentSectionIndex = currentStep ~/ gridRows; relativeStep = currentStep % gridRows.
- Autosave now persists `numSections`, `currentSectionIndex`, and `sectionGridData` (all sections).

## Next Steps
1. Dynamic rows per section
   - Flutter: introduce per-section row counts; resize only that section; compute absolute step via cumulative sums.
   - Native: replace single `g_steps_per_section` with per-section sizes; loop/song boundaries computed from per-section arrays.
2. Native setter for steps-per-section (stopgap)
   - Until per-section sizes are implemented natively, add `set_steps_per_section(int steps)` and update whenever rows change.

This refactor aligns the UI and native layers, removes save/load churn on section switches, and prepares the codebase for per-section sizes.

