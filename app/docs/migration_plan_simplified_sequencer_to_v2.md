## Migration plan: simplified sequencer → V2

### Context
- We currently use `app/lib/screens/sequencer_screen_updated.dart` backed by new native states: `TableState`, `PlaybackState`, `SampleBankState`, `SampleBrowserState`, and `TimerState`.
- Target is `app/lib/screens/sequencer_screen_v2.dart` and its V2 widgets.
- State logic changed completely; we will bridge with small UI-oriented helpers (prefixed with `ui`) while keeping the native seqlock sync pattern and ValueNotifiers.

### Assumptions (confirmed)
- **Grid**: Start with 16 columns and 4 layers (4×4). Layers are slices of columns. We will keep these as initial constants while preserving the ability to evolve to variable counts.
- **Drag & drop**: Bank → grid DnD must work immediately.
- **Stubs vs. real**: Use simple placeholder implementations where V2 expects APIs that are UI-only; place them in the appropriate state files and keep them minimal.

### High-level approach
1) Wrap V2 screen in the same provider setup as the simplified screen and start the frame timer.
2) Incrementally rewire V2 widgets to the new states via small `ui*` helpers that hide native details.
3) Keep per-frame native sync (seqlock) and only update ValueNotifiers and listeners when values actually change.
4) After the first working pass, refactor V2 grid to read `TableState` cells directly (remove interim adapters).

### Phase-by-phase plan

#### Phase 0 — Providers and timer
- Update `SequencerScreenV2` to use `MultiProvider` for:
  - `TableState`, `PlaybackState(TableState)`, `SampleBankState`, `SampleBrowserState`.
- Construct and start `TimerState(tableState, playbackState)` in `initState()`. Ensure `dispose()` stops timer and disposes states.

#### Phase 1 — Sections and playback
- Drive sections from `TableState`:
  - Count: `TableState.sectionsCount`.
  - Selected section: `TableState.uiSelectedSection` with `setUiSelectedSection(int)`.
- Playback wiring via `PlaybackState`:
  - Start/stop/toggle: `start() / stop() / togglePlayback()`.
  - BPM, mode, region: `setBpm(int)`, `setSongMode(bool)`; region auto-updates with native.
  - Per-section loops: `setSectionLoopsNum(section, loops)`.
  - Section switching: `switchToPreviousSection()` / `switchToNextSection()`; mirror selection to `TableState.setUiSelectedSection()`.
- PageView control in V2 body: on page change, call the above and keep `uiSelectedSection` in sync.

#### Phase 2 — Message bar
- Replace `sequencer.numSections` with `TableState.sectionsCount`.
- Keep thread navigation unchanged (still uses `ThreadsState`).

#### Phase 3 — Sample bank (top bar)
- Replace V2 reads with `SampleBankState` + minimal `ui` helpers:
  - Names/loaded: `slotNames`, `slotsLoaded`.
  - Active slot (selected): `activeSlot`.
  - Colors (UI-only): `uiBankColors` (stable palette of 16).
  - Playing outline (UI-only): `PlaybackState.uiSlotPlaying` (bool[16], initial false).
- Actions:
  - Tap: `SampleBankState.uiHandleBankChange(int slot)` → `setActiveSlot(slot)`.
  - Long-press: `SampleBankState.uiPickFileForSlot(int slot)` → open browser or call `loadSample(slot, path)` after selection.

#### Phase 4 — Sound grid (main area)
Initial pass keeps V2 grid intact via small adapters; then we refactor to direct `TableState` access.

1) Dimensions:
  - `TableState.uiGridColumns` → 16 (constant initial value).
  - `TableState.uiGridRows` → `getSectionStepCount(uiSelectedSection)`.
  - `TableState.uiMaxGridRows` → `maxSteps` from native.

2) Visible layer slicing (4×4):
  - `TableState.getLayerStartCol(layer)` and `getLayerEndCol(layer)` already exist; set them to 4 columns per layer and keep `uiSelectedLayer` to choose the slice.

3) Data mapping for V2 grid (temporary helpers on `TableState`):
  - `List<int?> get uiGridSamples` → builds the flat list (rows×cols for current layer) by reading native cell pointers and extracting `sampleSlot`.
  - `List<int?> uiGetSectionGridSamples(int sectionIndex, {required int gridIndex})` → same for previews.
  - `void uiPlaceSampleInGrid(int sampleSlot, int flatIndex)` → map to (step=row, col=layerStart+colInSlice), then call native `tableSetCell(step, col, sampleSlot, 1.0, 1.0)` and notify the notifiers.
  - `void uiHandlePadPress(int flatIndex)` → set `uiActivePad`, optionally audition via future native preview (stub now).
  - `double uiGetCellVolume(int flatIndex)` / `double uiGetCellPitch(int flatIndex)` → read from cell if available, else return 1.0.

4) Selection and gestures (UI-only on `TableState`):
  - `bool uiIsInSelectionMode`, `void uiToggleSelectionMode()`.
  - `Set<int> uiSelectedGridCells`, `void uiHandleGridCellSelection(int cellIndex, bool extend)`, `void uiHandlePanEnd()`.
  - `bool uiHasClipboardData`, `void uiCopySelectedCells()`, `void uiPasteToSelectedCells()`, `void uiDeleteSelectedCells()`.

5) Current step highlight:
  - Use `PlaybackState.currentStepNotifier` and compare against the row (global step index mapped to section-local row if needed). For loop mode, current section’s first step is `TableState.getSectionStartStep(currentSection)`.

#### Phase 5 — Edit buttons and multitask panel
- Wire `EditButtonsWidget` to `TableState` `ui` selection/clipboard/step-insert APIs:
  - `bool uiIsStepInsertMode`, `int uiStepInsertSize`, `void uiToggleStepInsertMode()`.
- Multitask panel:
  - Add to `PlaybackState`: `MultitaskPanelMode uiPanelMode`, `void uiSetPanelMode(MultitaskPanelMode)`.
  - Recording placeholder: `String? uiLastRecordingPath` (null for now).

#### Phase 6 — Remove legacy `SequencerState` coupling
- After widgets read from `TableState`/`PlaybackState`/`SampleBankState`/`SampleBrowserState`, drop `SequencerState` usage in V2 widgets.
- Final refactor for the grid: replace temporary `uiGridSamples`/`uiGetSectionGridSamples` with direct `getCellNotifier(step, col)` usage and computed mapping to the current layer slice.

### Placeholder API checklist

#### TableState
- Grid and layers
  - `int get uiGridColumns` → 16
  - `int get uiGridRows`
  - `int get uiMaxGridRows`
  - `void uiIncreaseGridRows()` / `void uiDecreaseGridRows()`
  - `int get uiSelectedLayer`, `void setUiSelectedLayer(int)`
- Section overlays
  - `bool uiIsSectionControlOpen`, `void uiOpenSectionControlOverlay()`, `void uiCloseSectionControlOverlay()`
  - `bool uiIsSectionCreationOpen`, `void uiOpenSectionCreationOverlay()`, `void uiCloseSectionCreationOverlay()`
- Sound grid stack
  - `int uiCurrentSoundGridIndex`, `List<int> uiSoundGridOrder`, `void uiInitializeSoundGrids(int)`, `void uiBringGridToFront(int)`
  - `String uiGetGridLabel(int)`
- Selection & clipboard
  - `bool uiIsInSelectionMode`, `void uiToggleSelectionMode()`
  - `Set<int> uiSelectedGridCells`, `void uiHandleGridCellSelection(int, bool)`, `void uiHandlePanEnd()`
  - `bool uiHasClipboardData`, `void uiCopySelectedCells()`, `void uiPasteToSelectedCells()`, `void uiDeleteSelectedCells()`
- Grid adapters (temporary)
  - `List<int?> get uiGridSamples`
  - `List<int?> uiGetSectionGridSamples(int sectionIndex, {required int gridIndex})`
  - `void uiPlaceSampleInGrid(int sampleSlot, int flatIndex)`
  - `void uiHandlePadPress(int flatIndex)`
  - `double uiGetCellVolume(int flatIndex)`, `double uiGetCellPitch(int flatIndex)`

#### PlaybackState
- Already present: `start/stop/toggle`, `setBpm`, `setSongMode`, `setSectionLoopsNum`, `currentStepNotifier`, `isPlayingNotifier`, `bpmNotifier`, `currentSectionNotifier`, `currentSectionLoopNotifier`, `currentSectionLoopsNumNotifier`, `switchToPreviousSection/switchToNextSection`.
- UI-only:
  - `List<bool> uiSlotPlaying` (len 16, all false initially)
  - `MultitaskPanelMode uiPanelMode`, `void uiSetPanelMode(MultitaskPanelMode)`
  - `String? uiLastRecordingPath`

#### SampleBankState
- UI-only:
  - `List<Color> uiBankColors` (16 stable colors)
  - `void uiHandleBankChange(int slot)` → `setActiveSlot(slot)`
  - `Future<void> uiPickFileForSlot(int slot)` → open sample browser, then `loadSample(slot, path)`

#### SampleBrowserState (optional convenience)
- `void showForSlot(int slot)` (or reuse existing APIs by setting a target slot when opening)

### Widget mapping (what changes)
- `SampleBanksWidget` → read from `SampleBankState` and `PlaybackState.uiSlotPlaying`; use new `ui*` actions.
- `SequencerBody` → use `TableState.sectionsCount` and `TableState.uiSelectedSection`; call `PlaybackState` section navigation; overlays from `TableState.ui*`.
- `SampleGridWidget` → dimensions, data, selection, and actions via `TableState.ui*` helpers; current step highlight via `PlaybackState.currentStepNotifier`.
- `EditButtonsWidget` → selection/clipboard/step insert via `TableState.ui*`.
- `MultitaskPanelWidget` → `PlaybackState.uiPanelMode` and `uiLastRecordingPath`.
- `MessageBarWidget` → `TableState.sectionsCount`.

### DnD behavior (bank → grid)
- On drop, compute:
  - `row = flatIndex ~/ uiGridColumns`
  - `colInSlice = flatIndex % uiGridColumns`
  - `layerStart = getLayerStartCol(uiSelectedLayer)`
  - `col = layerStart + colInSlice`
  - `step = row + getSectionStartStep(uiSelectedSection)`
- Call `tableSetCell(step, col, sampleSlot, volume=1.0, pitch=1.0)` and notify affected cell notifiers.

### Per-frame native sync
- `TimerState` calls each frame:
  - `tableState.syncTableState()`
  - `playbackState.syncPlaybackState()`
- Each state updates its ValueNotifiers and calls `notifyListeners()` once per frame if anything changed.

### Acceptance criteria (first pass)
- V2 screen renders using new states.
- Play/stop works; BPM changes reflected.
- Section switching via PageView and buttons; loops count adjustable.
- Sample bank shows loaded slots and selection; DnD places samples into the grid slice.
- Grid highlights current step while playing; selection and row add/remove controls work.
- No dependency on legacy `SequencerState` in the updated widgets on the main path.

### Risks & follow-ups
- Interim adapters (`uiGridSamples`, etc.) should be removed after direct cell notifier integration.
- `uiSlotPlaying` needs real data later (from native playback per-column state) to indicate flashing/playing in bank.
- Audition on pad press can be added when native preview is ready.



