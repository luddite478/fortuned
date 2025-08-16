## SequencerState optimization ideas

### TL;DR
- **Problem**: `app/lib/state/sequencer_state.dart` is a god object mixing domain logic, UI state, native audio bridging, persistence, networking, recording/conversion, and undo/redo.
- **Impact**: Hard to reason about, test, and optimize; duplicated index math; broad rebuilds; heavy undo snapshots; lifecycle hazards.
- **Plan**: Split responsibilities into focused modules, introduce typed models and mapping helpers, replace snapshot-based undo with typed commands, and reduce notifier blast radius.

### Symptoms observed
- **Too many responsibilities** in one `ChangeNotifier`:
  - Sequencing domain (sections, grids, selection, mapping, playback step tracking)
  - Audio/native bridge and playback orchestration
  - Sample bank management (load/unload/preview, volume/pitch)
  - Recording and MP3 conversion, sharing
  - Persistence (save/load JSON, autosave) and filesystem/asset IO
  - HTTP/Threads collaboration wiring
  - UI-only state (panel modes, colors, sample browser visibility, layout selection)
- **Over-notification risk**: batched `Timer` tries to tame rebuilds, but a single notifier still triggers broad listeners and adds ordering/timing edge cases.
- **Heavy undo/redo**: Records `beforeState/afterState` snapshots (`Map<String, dynamic>`), expensive for grid edits and error-prone.
- **Primitive data modeling**: `Map<int, List<List<int?>>>` for sections → grids, with manual `row/col` math and duplicated absolute/relative conversions.
- **Lifecycle and logging**: Multiple timers; many `print`/`debugPrint` in hot paths; ensure all timers/subscriptions are disposed.

### Guiding principles
- **Single responsibility per module**; UI-agnostic core.
- **Typed, immutable models** for clarity and safety.
- **Deterministic commands** for undo/redo over state snapshots.
- **Narrow notifications** using `ValueListenable`s or multiple notifiers.
- **Pure helpers** for index math to remove duplication.

### Proposed module split (incremental)
- `SequencerCore` (pure domain)
  - Owns sections, sound grids, cells, selection, and mapping helpers.
  - No IO, no native calls, no UI types.
- `PlaybackController`
  - Owns bpm, play/stop, current step clock, and only the native `SequencerLibrary` API.
  - Subscribes to core changes to sync native state.
- `SampleBankStore`
  - Owns slot metadata, load/unload/preview, global volume/pitch and per-cell overrides (or split per taste).
- `RecordingController`
  - Recording lifecycle, conversion progress, sharing.
- `PersistenceService`
  - Save/load, autosave, SharedPreferences. Cold paths only.
- `UndoRedoManager` (separate file)
  - Uses typed commands; no `Map<String, dynamic>` snapshots.
- `UiPanelState` (optional)
  - Panel modes, layout selection, colors, sample browser visibility.
- `CollaborationService`
  - Threads/HTTP/collab wiring.

`SequencerState` becomes a thin orchestrator composing these modules, or we expose multiple providers and remove the monolith entirely.

### Typed models and helpers
Introduce explicit structures to replace nested lists and raw indices:

```dart
class CellIndex {
  final int row;
  final int column;
  const CellIndex(this.row, this.column);
}

class SoundGrid {
  final List<int?> cells; // length = gridRows * gridColumns
  const SoundGrid(this.cells);
}

class Section {
  final List<SoundGrid> grids; // ordered
  const Section(this.grids);
}

class SequencerProject {
  final List<Section> sections;
  const SequencerProject(this.sections);
}

class GridMath {
  final int gridColumns;
  final int gridRows;
  const GridMath(this.gridColumns, this.gridRows);

  int get gridSize => gridColumns * gridRows;
  int cellIndex(CellIndex idx) => idx.row * gridColumns + idx.column;
  CellIndex fromIndex(int index) => CellIndex(index ~/ gridColumns, index % gridColumns);

  int absoluteStep(int sectionIndex, int relativeStep) => sectionIndex * gridRows + relativeStep;
  int absoluteColumn(int gridIndex, int relativeColumn) => gridIndex * gridColumns + relativeColumn;
}
```

Use these everywhere to eliminate duplicated `~/` and `%` logic.

### Undo/redo via typed commands
Replace snapshot-based actions with compact, reversible commands.

```dart
abstract class SequencerCommand {
  String get description;
  void apply(SequencerCore core);
  void revert(SequencerCore core);
}

class SetCell implements SequencerCommand {
  final int sectionIndex;
  final int gridIndex;
  final CellIndex cell;
  final int? newValue;
  int? _oldValue;
  SetCell(this.sectionIndex, this.gridIndex, this.cell, this.newValue);
  String get description => 'Set cell to $newValue';
  void apply(SequencerCore core) { _oldValue = core.getCell(sectionIndex, gridIndex, cell); core.setCell(sectionIndex, gridIndex, cell, newValue); }
  void revert(SequencerCore core) { core.setCell(sectionIndex, gridIndex, cell, _oldValue); }
}
```

Batch commands (copy/paste, selection moves) can be a single `CompositeCommand` for excellent history compression.

### Notification strategy
- Keep hot signals (`currentStep`, `isPlaying`, `bpm`, perhaps per-cell volume) as `ValueListenable`s.
- Expose derived, read-only views for UI selectors.
- Prefer multiple small notifiers over one global `ChangeNotifier`.
- Remove the batching `Timer` if not needed after split; otherwise ensure it’s cancelled in `dispose()`.

### Low-risk quick wins (do now)
- **Centralize grid size and mapping**
  - Add `int get gridSize => _gridColumns * _gridRows;`
  - Replace `List.filled(_gridColumns * _gridRows, null)` and scattered index math with helpers.
- **Dispose timers**
  - Ensure `_notificationBatchTimer?.cancel(); _notificationBatchTimer = null;` in `dispose()`.
- **Clamp logging**
  - Gate logs behind `kDebugMode` and limit hot-path prints.
- **ID stability for grids**
  - Use stable IDs for grids rather than raw indices for `_soundGridOrder` to avoid identity shifts on removal/reorder.

### Migration plan (incremental, safe)
1) Extract `UndoRedoManager` into `app/lib/state/undo_redo.dart` and change actions to typed commands; keep adapter layer in `SequencerState` temporarily.
2) Add `GridMath` and `CellIndex`, replace raw math in the current file.
3) Extract `PlaybackController` (bpm, play/stop, step clock, native sync). Wire minimal API: `configure(columns, steps)`, `setCell(absoluteStep, absoluteCol, value)`.
4) Move sample browser + asset manifest logic to `SampleBrowserService`. Keep UI state separate from sequencing.
5) Extract `PersistenceService` and route autosave/load through it.
6) Split UI-only state to `UiPanelState` (panel modes, colors, layout version, visibility flags).
7) Remove batch timer if redundant. Profile rebuilds (Flutter DevTools) and add selectors.

These steps can be landed independently with tests per module.

### Proposed public APIs after split (sketch)
- `SequencerCore`
  - `List<Section> get sections;`
  - `SoundGrid grid(int sectionIndex, int gridIndex);`
  - `int? getCell(int sectionIndex, int gridIndex, CellIndex cell);`
  - `void setCell(int sectionIndex, int gridIndex, CellIndex cell, int? value);`
  - `void resizeRows(int newRows);`
  - Emits domain events (cell changed, section changed, rows changed).
- `PlaybackController`
  - `ValueListenable<int> currentStep;`
  - `ValueListenable<bool> isPlaying;`
  - `void start({required int bpm, required int steps, required int startAbsoluteStep});`
  - `void stop();`
  - `void syncCell(int absoluteStep, int absoluteCol, int? value);`
- `UndoRedoManager`
  - `void perform(SequencerCommand cmd);`
  - `bool undo(); bool redo();`

### Risks and mitigations
- **Behavior drift**: Cover core behaviors with golden tests before large moves (cell set/clear, selection ops, row resize, play/stop hand-off).
- **UI breakage**: Provide adapters keeping old getters alive during the transition.
- **Performance surprises**: Profile rebuild counts before/after; add memoized selectors.

### Metrics to track
- Widget rebuild count and frame time when editing cells and during playback.
- Undo/redo memory and latency for common operations (single cell, paste selection).
- CPU usage during playback and while mass-updating grid.

### Action items
- Add `GridMath`, `CellIndex`, `gridSize` and replace call sites.
- Extract `UndoRedoManager` to its own file and convert to typed commands.
- Cancel `_notificationBatchTimer` on dispose.
- Move sample browser and conversion logic to services.
- Add debug logger with categories and throttle hot-path logs.

### References
- Current file: `app/lib/state/sequencer_state.dart`
- Notable hot paths to simplify: cell set/clear, selection operations, grid resize, playback step handler.
