# Sequencer V2 Implementation Plan

**Native-Authoritative Architecture with Pointer-Based Data Access**

## Overview

This document outlines the complete rewrite of the sequencer system from Flutter-as-source-of-truth to Native-as-source-of-truth architecture. The new system uses direct memory access via Dart FFI pointers, frame-based change tracking, and Ticker-based synchronization for maximum performance.

## Key Principles

1. **Native (C) is Authoritative**: All sequencer data lives in native `g_cells` array
2. **Zero-Copy Access**: Flutter reads data directly via pointers, no copying
3. **Change-Driven Updates**: Only modified cells trigger UI rebuilds
4. **Frame-Perfect Sync**: Ticker-based polling ensures 60fps updates
5. **Static Memory**: Use static arrays for predictable memory management

---

## 1. Native (C++) Implementation Changes

### A. Enhanced Cell Structure

**File: `app/native/sequencer.mm`**

```c
// Enhanced cell structure with change tracking
typedef struct {
    int   sample_slot;           // -1 = empty
    float volume;               // DEFAULT_CELL_VOLUME means use sample bank  
    float pitch;                // DEFAULT_CELL_PITCH means use sample bank
    bool  changed_last_frame;   // 🆕 Change tracking flag
} Cell;

static Cell g_cells[MAX_SEQUENCER_STEPS][MAX_TOTAL_COLUMNS];
static const Cell DEFAULT_CELL = { -1, DEFAULT_CELL_VOLUME, DEFAULT_CELL_PITCH, false };
```

### B. Change Tracking System

```c
// Change tracking globals
static int g_changed_cells_buffer[MAX_SEQUENCER_STEPS * MAX_TOTAL_COLUMNS * 2]; // [step, col] pairs
static int g_changed_cells_count = 0;
static bool g_change_tracking_enabled = true;

// Mark cell as changed (called whenever cell is modified)
static inline void mark_cell_changed(int step, int col) {
    if (!g_change_tracking_enabled) return;
    
    Cell* cell = cell_at(step, col);
    if (cell && !cell->changed_last_frame) {
        cell->changed_last_frame = true;
        
        // Add to change buffer (if space available)
        if (g_changed_cells_count < (MAX_SEQUENCER_STEPS * MAX_TOTAL_COLUMNS)) {
            g_changed_cells_buffer[g_changed_cells_count * 2] = step;
            g_changed_cells_buffer[g_changed_cells_count * 2 + 1] = col;
            g_changed_cells_count++;
        }
    }
}

// Reset change tracking (called after Flutter reads changes)
static void reset_change_tracking() {
    g_changed_cells_count = 0;
    
    // Reset all changed flags efficiently
    for (int step = 0; step < g_steps_len; step++) {
        for (int col = 0; col < g_columns_len; col++) {
            g_cells[step][col].changed_last_frame = false;
        }
    }
}
```

### C. Section Management

```c
// Section boundary management
typedef struct {
    int start_step;              // First step of this section
    int row_count;              // Number of rows in this section  
    int grid_count;             // Number of grids in this section
} SectionInfo;

static SectionInfo g_sections[MAX_SECTIONS];
static int g_num_sections = 1;
static int g_current_section = 0;

// Initialize default section
static void init_sections() {
    g_sections[0] = (SectionInfo){
        .start_step = 0,
        .row_count = 16,
        .grid_count = 1
    };
    g_num_sections = 1;
    g_current_section = 0;
}

// Helper functions
static int get_section_end_step(int section_index) {
    if (section_index >= g_num_sections) return g_steps_len;
    return g_sections[section_index].start_step + g_sections[section_index].row_count;
}

static int get_absolute_step_from_section(int section_index, int relative_step) {
    if (section_index >= g_num_sections) return -1;
    return g_sections[section_index].start_step + relative_step;
}

static Cell* get_section_grid_cell(int section_index, int grid_index, int row, int col) {
    int absolute_step = get_absolute_step_from_section(section_index, row);
    int absolute_col = grid_index * g_gridColumns + col;
    return cell_at(absolute_step, absolute_col);
}
```

### D. New FFI Function Implementations

```c
extern "C" {
    // POINTER ACCESS FUNCTIONS
    Cell* get_cells_pointer() {
        return &g_cells[0][0];  // Return pointer to raw table
    }
    
    Cell* get_section_grid_pointer(int section, int grid) {
        if (section >= g_num_sections || grid < 0) return NULL;
        
        int start_step = g_sections[section].start_step;
        int start_col = grid * g_gridColumns;
        return &g_cells[start_step][start_col];
    }
    
    int get_table_rows() {
        return g_steps_len;
    }
    
    int get_table_columns() {
        return g_columns_len;
    }
    
    // SECTION MANAGEMENT FUNCTIONS
    int get_current_section_native() {
        return g_current_section;
    }
    
    void set_current_section_native(int section) {
        if (section >= 0 && section < g_num_sections) {
            g_current_section = section;
        }
    }
    
    int get_section_row_count(int section) {
        if (section >= 0 && section < g_num_sections) {
            return g_sections[section].row_count;
        }
        return 0;
    }
    
    int get_section_start_step(int section) {
        if (section >= 0 && section < g_num_sections) {
            return g_sections[section].start_step;
        }
        return 0;
    }
    
    void set_section_size(int section, int rows) {
        if (section >= 0 && section < g_num_sections && rows > 0) {
            g_sections[section].row_count = rows;
            // Recalculate total steps length
            recalculate_total_steps();
        }
    }
    
    // CHANGE TRACKING FUNCTIONS
    int* get_changed_cells_pointer() {
        return g_changed_cells_buffer;
    }
    
    int get_changed_cells_count() {
        return g_changed_cells_count;
    }
    
    void reset_change_tracking() {
        reset_change_tracking();
    }
    
    void enable_change_tracking(bool enable) {
        g_change_tracking_enabled = enable;
    }
    
    // GRID LAYOUT HELPERS
    Cell* get_grid_cell_pointer(int section, int grid, int row, int col) {
        return get_section_grid_cell(section, grid, row, col);
    }
    
    int calculate_absolute_step(int section, int row) {
        return get_absolute_step_from_section(section, row);
    }
    
    int calculate_absolute_column(int grid, int col) {
        return grid * g_gridColumns + col;
    }
    
    int get_total_sections() {
        return g_num_sections;
    }
}
```

### E. Integration with Existing Functions

**Update existing functions to call `mark_cell_changed()`:**

```c
void set_cell(int step, int column, int sample_slot) {
    // ... existing validation ...
    
    if (column < g_columns_len) {
        Cell* cell = cell_at(step, column);
        if (cell) {
            cell->sample_slot = sample_slot;
            mark_cell_changed(step, column);  // 🆕 Track change
        }
    }
    // ... rest of function ...
}

int set_cell_volume(int step, int column, float volume) {
    // ... existing validation ...
    
    if (column < g_columns_len) {
        Cell* cell = cell_at(step, column);
        if (cell) {
            cell->volume = volume;
            mark_cell_changed(step, column);  // 🆕 Track change
        }
    }
    // ... rest of function ...
}

// Similar updates for set_cell_pitch, clear_cell, etc.
```

---

## 2. FFI Bindings Extension

### A. Update FFI Generation Config

**File: `ffigen_sequencer.yaml`**

```yaml
# Add new functions to be generated
functions:
  include:
    - get_cells_pointer
    - get_section_grid_pointer
    - get_changed_cells_pointer
    - get_changed_cells_count
    - reset_change_tracking
    - get_current_section_native
    - get_section_row_count
    - calculate_absolute_step
    - calculate_absolute_column
    # ... existing functions ...

# Add struct definitions
structs:
  include:
    - Cell
```

### B. Manual Dart Struct Definition

**File: `app/lib/native_types.dart` (new file)**

```dart
import 'dart:ffi' as ffi;

// Mirror the C struct in Dart
base class Cell extends ffi.Struct {
  @ffi.Int32()
  external int sample_slot;
  
  @ffi.Float()  
  external double volume;
  
  @ffi.Float()
  external double pitch;
  
  @ffi.Bool()
  external bool changed_last_frame;
  
  @override
  String toString() => 'Cell(slot: $sample_slot, vol: $volume, pitch: $pitch, changed: $changed_last_frame)';
}
```

### C. Enhanced SequencerLibrary

**File: `app/lib/sequencer_library.dart`**

```dart
class SequencerLibrary {
  // ... existing code ...
  
  // 🆕 POINTER ACCESS METHODS
  ffi.Pointer<Cell> getCellsPointer() {
    return _bindings.get_cells_pointer().cast<Cell>();
  }
  
  ffi.Pointer<Cell> getSectionGridPointer(int section, int grid) {
    return _bindings.get_section_grid_pointer(section, grid).cast<Cell>();
  }
  
  // 🆕 CHANGE TRACKING METHODS
  ffi.Pointer<ffi.Int32> getChangedCellsPointer() {
    return _bindings.get_changed_cells_pointer();
  }
  
  int getChangedCellsCount() {
    return _bindings.get_changed_cells_count();
  }
  
  void resetChangeTracking() {
    _bindings.reset_change_tracking();
  }
  
  // 🆕 SECTION MANAGEMENT METHODS  
  int getCurrentSectionNative() {
    return _bindings.get_current_section_native();
  }
  
  int getSectionRowCount(int section) {
    return _bindings.get_section_row_count(section);
  }
  
  int calculateAbsoluteStep(int section, int row) {
    return _bindings.calculate_absolute_step(section, row);
  }
  
  int calculateAbsoluteColumn(int grid, int col) {
    return _bindings.calculate_absolute_column(grid, col);
  }
  
  int getTotalSections() {
    return _bindings.get_total_sections();
  }
}
```

---

## 3. New Flutter Architecture

### A. File Structure Changes

```
lib/
├── state/
│   ├── sequencer_state_old.dart          // 🔄 Renamed existing file
│   ├── sequencer_state.dart               // 🆕 New native-authoritative state  
│   ├── native_grid_view.dart              // 🆕 Pointer-based grid access
│   ├── change_tracker.dart                // 🆕 Change tracking system
│   └── section_manager.dart               // 🆕 Section boundary management
├── native_types.dart                      // 🆕 Native struct definitions
└── ... existing files ...
```

### B. NativeGridView Implementation

**File: `app/lib/state/native_grid_view.dart`**

```dart
import 'dart:ffi' as ffi;
import 'package:flutter/foundation.dart';
import '../sequencer_library.dart';
import '../native_types.dart';

class NativeGridView {
  final ffi.Pointer<Cell> _dataPointer;
  final int _sectionIndex;
  final int _gridIndex; 
  final int _rows;
  final int _columns;
  final SequencerLibrary _lib;
  
  // Cache for ValueNotifiers (created on demand)
  final Map<int, ValueNotifier<Cell>> _cellNotifiers = {};
  
  NativeGridView({
    required ffi.Pointer<Cell> dataPointer,
    required int sectionIndex,
    required int gridIndex,
    required int rows, 
    required int columns,
    required SequencerLibrary lib,
  }) : _dataPointer = dataPointer,
       _sectionIndex = sectionIndex,
       _gridIndex = gridIndex,
       _rows = rows,
       _columns = columns,
       _lib = lib;
  
  // Getters
  int get sectionIndex => _sectionIndex;
  int get gridIndex => _gridIndex;
  int get rows => _rows;
  int get columns => _columns;
  
  // Direct memory access - zero copy!
  Cell getCellDirect(int row, int col) {
    if (row < 0 || row >= _rows || col < 0 || col >= _columns) {
      throw RangeError('Cell coordinates out of bounds: ($row, $col)');
    }
    final index = row * _columns + col;
    return _dataPointer[index];
  }
  
  // For UI binding - creates ValueNotifier on demand
  ValueNotifier<Cell> getCellNotifier(int row, int col) {
    final index = row * _columns + col;
    return _cellNotifiers.putIfAbsent(index, () {
      return ValueNotifier<Cell>(getCellDirect(row, col));
    });
  }
  
  // Update specific cell notifier (called by change tracker)
  void updateCellNotifier(int row, int col) {
    final index = row * _columns + col;
    final notifier = _cellNotifiers[index];
    if (notifier != null) {
      notifier.value = getCellDirect(row, col);
    }
  }
  
  // Cleanup
  void dispose() {
    for (final notifier in _cellNotifiers.values) {
      notifier.dispose();
    }
    _cellNotifiers.clear();
  }
}
```

### C. ChangeTracker Implementation

**File: `app/lib/state/change_tracker.dart`**

```dart
import 'dart:ffi' as ffi;
import '../sequencer_library.dart';
import 'native_grid_view.dart';

class ChangeTracker {
  final SequencerLibrary _lib;
  final Map<int, NativeGridView> _gridViews = {};
  
  ChangeTracker(this._lib);
  
  void registerGridView(int sectionIndex, int gridIndex, NativeGridView view) {
    final key = _generateKey(sectionIndex, gridIndex);
    _gridViews[key] = view;
  }
  
  void unregisterGridView(int sectionIndex, int gridIndex) {
    final key = _generateKey(sectionIndex, gridIndex);
    _gridViews.remove(key);
  }
  
  // Called every frame by Ticker
  void processChanges() {
    final changedCount = _lib.getChangedCellsCount();
    if (changedCount == 0) return;
    
    final changesPointer = _lib.getChangedCellsPointer();
    
    // Process each changed cell
    for (int i = 0; i < changedCount; i++) {
      final step = changesPointer[i * 2];
      final col = changesPointer[i * 2 + 1];
      
      // Find which section/grid this belongs to and update UI
      _updateCellInUI(step, col);
    }
    
    // Reset native change tracking
    _lib.resetChangeTracking();
  }
  
  void _updateCellInUI(int absoluteStep, int absoluteCol) {
    // Calculate section and grid from absolute coordinates
    final (sectionIndex, relativeRow) = _calculateSectionFromStep(absoluteStep);
    final (gridIndex, relativeCol) = _calculateGridFromColumn(absoluteCol);
    
    if (sectionIndex == -1 || gridIndex == -1) return;
    
    // Update the specific UI element
    final key = _generateKey(sectionIndex, gridIndex);
    final gridView = _gridViews[key];
    if (gridView != null && relativeRow >= 0 && relativeRow < gridView.rows) {
      gridView.updateCellNotifier(relativeRow, relativeCol);
    }
  }
  
  (int, int) _calculateSectionFromStep(int absoluteStep) {
    // Iterate through sections to find which one contains this step
    for (int section = 0; section < _lib.getTotalSections(); section++) {
      final sectionStart = _lib.getSectionStartStep(section);
      final sectionRows = _lib.getSectionRowCount(section);
      final sectionEnd = sectionStart + sectionRows;
      
      if (absoluteStep >= sectionStart && absoluteStep < sectionEnd) {
        return (section, absoluteStep - sectionStart);
      }
    }
    return (-1, -1); // Not found
  }
  
  (int, int) _calculateGridFromColumn(int absoluteCol) {
    // Assuming fixed grid column count (need to get from native)
    const gridColumns = 4; // TODO: Get from native
    final gridIndex = absoluteCol ~/ gridColumns;
    final relativeCol = absoluteCol % gridColumns;
    return (gridIndex, relativeCol);
  }
  
  int _generateKey(int sectionIndex, int gridIndex) {
    return sectionIndex * 100 + gridIndex; // Simple hash
  }
  
  void dispose() {
    _gridViews.clear();
  }
}
```

### D. New SequencerState Implementation

**File: `app/lib/state/sequencer_state.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../sequencer_library.dart';
import 'native_grid_view.dart';
import 'change_tracker.dart';

class SequencerState extends ChangeNotifier with TickerProviderStateMixin {
  final SequencerLibrary _lib = SequencerLibrary.instance;
  
  // Core state - minimal, native-backed
  late Ticker _syncTicker;
  late ChangeTracker _changeTracker;
  bool _isInitialized = false;
  
  // Current section (synced from native)  
  final ValueNotifier<int> _currentSectionNotifier = ValueNotifier(0);
  ValueListenable<int> get currentSectionNotifier => _currentSectionNotifier;
  
  // Current playback step (synced from native)
  final ValueNotifier<int> _currentStepNotifier = ValueNotifier(-1);  
  ValueListenable<int> get currentStepNotifier => _currentStepNotifier;
  
  // Playback state (synced from native)
  final ValueNotifier<bool> _isSequencerPlayingNotifier = ValueNotifier(false);
  ValueListenable<bool> get isSequencerPlayingNotifier => _isSequencerPlayingNotifier;
  
  // Section views (lazy-loaded)
  final Map<int, Map<int, NativeGridView>> _sectionGridViews = {};
  
  // Initialization
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (!_lib.initialize()) {
      throw Exception('Failed to initialize native sequencer library');
    }
    
    _changeTracker = ChangeTracker(_lib);
    _syncTicker = createTicker(_onTick);
    _isInitialized = true;
    
    // Enable change tracking in native
    _lib.enableChangeTracking(true);
    
    print('✅ SequencerState V2 initialized');
  }
  
  // Core tick function - called every frame when active
  void _onTick(Duration elapsed) {
    if (!_isInitialized) return;
    
    // 1. Sync current section from native
    final nativeSection = _lib.getCurrentSectionNative();
    if (nativeSection != _currentSectionNotifier.value) {
      _currentSectionNotifier.value = nativeSection;
    }
    
    // 2. Sync current step from native  
    final nativeStep = _lib.getCurrentStep();
    if (nativeStep != _currentStepNotifier.value) {
      _currentStepNotifier.value = nativeStep;
    }
    
    // 3. Sync playback state
    final isPlaying = _lib.isSequencerPlaying();
    if (isPlaying != _isSequencerPlayingNotifier.value) {
      _isSequencerPlayingNotifier.value = isPlaying;
    }
    
    // 4. Process changed cells (efficient updates)
    _changeTracker.processChanges();
  }
  
  // Get grid view for specific section/grid (lazy creation)
  NativeGridView getGridView(int sectionIndex, int gridIndex) {
    if (!_isInitialized) {
      throw StateError('SequencerState not initialized');
    }
    
    return _sectionGridViews
      .putIfAbsent(sectionIndex, () => {})
      .putIfAbsent(gridIndex, () {
        final pointer = _lib.getSectionGridPointer(sectionIndex, gridIndex);
        final rows = _lib.getSectionRowCount(sectionIndex);
        final columns = _lib.getGridColumns(); // TODO: Add this to FFI
        
        final view = NativeGridView(
          dataPointer: pointer,
          sectionIndex: sectionIndex,
          gridIndex: gridIndex, 
          rows: rows,
          columns: columns,
          lib: _lib,
        );
        
        _changeTracker.registerGridView(sectionIndex, gridIndex, view);
        return view;
      });
  }
  
  // Sequencer controls
  void startSequencer({required int bpm}) {
    if (!_isInitialized) return;
    
    _lib.startSequencer(bpm, _getTotalSteps(), 0);
    _syncTicker.start(); // Begin frame-based polling
    
    // Immediate sync
    _isSequencerPlayingNotifier.value = true;
  }
  
  void stopSequencer() {
    if (!_isInitialized) return;
    
    _lib.stopSequencer();  
    _syncTicker.stop(); // Stop polling
    
    // Immediate sync
    _isSequencerPlayingNotifier.value = false;
    _currentStepNotifier.value = -1;
  }
  
  // Cell operations (immediately call FFI)
  void setCell(int sectionIndex, int gridIndex, int row, int col, int? sampleSlot) {
    if (!_isInitialized) return;
    
    final absoluteStep = _lib.calculateAbsoluteStep(sectionIndex, row);
    final absoluteCol = _lib.calculateAbsoluteColumn(gridIndex, col);
    
    if (sampleSlot != null) {
      _lib.setGridCell(absoluteStep, absoluteCol, sampleSlot);
    } else {
      _lib.clearGridCell(absoluteStep, absoluteCol);
    }
    // Change will be detected and UI updated on next frame
  }
  
  void setCellVolume(int sectionIndex, int gridIndex, int row, int col, double volume) {
    if (!_isInitialized) return;
    
    final absoluteStep = _lib.calculateAbsoluteStep(sectionIndex, row);
    final absoluteCol = _lib.calculateAbsoluteColumn(gridIndex, col);
    
    _lib.setCellVolume(absoluteStep, absoluteCol, volume);
  }
  
  void setCellPitch(int sectionIndex, int gridIndex, int row, int col, double pitch) {
    if (!_isInitialized) return;
    
    final absoluteStep = _lib.calculateAbsoluteStep(sectionIndex, row);
    final absoluteCol = _lib.calculateAbsoluteColumn(gridIndex, col);
    
    _lib.setCellPitch(absoluteStep, absoluteCol, pitch);
  }
  
  // Section management
  void switchToSection(int sectionIndex) {
    if (!_isInitialized) return;
    
    _lib.setCurrentSectionNative(sectionIndex);
    // Section change will be detected on next tick
  }
  
  void createNewSection() {
    if (!_isInitialized) return;
    
    // TODO: Implement section creation in native
    // This would involve:
    // 1. Expanding native section array
    // 2. Updating total steps
    // 3. Invalidating cached grid views
  }
  
  // Private helpers
  int _getTotalSteps() {
    if (!_isInitialized) return 0;
    
    int total = 0;
    final numSections = _lib.getTotalSections();
    for (int i = 0; i < numSections; i++) {
      total += _lib.getSectionRowCount(i);
    }
    return total;
  }
  
  @override
  void dispose() {
    if (_isInitialized) {
      _syncTicker.dispose();
      
      // Dispose all grid views
      for (final sectionGrids in _sectionGridViews.values) {
        for (final gridView in sectionGrids.values) {
          gridView.dispose();
        }
      }
      _sectionGridViews.clear();
      
      _changeTracker.dispose();
      _lib.cleanup();
    }
    
    _currentSectionNotifier.dispose();
    _currentStepNotifier.dispose();
    _isSequencerPlayingNotifier.dispose();
    
    super.dispose();
  }
  
  // Getters for compatibility
  bool get isSequencerPlaying => _isSequencerPlayingNotifier.value;
  int get currentStep => _currentStepNotifier.value;
  int get currentSection => _currentSectionNotifier.value;
}
```

---

## 4. UI Integration Examples

### A. Grid Cell Widget

**File: `app/lib/widgets/sequencer/grid_cell_widget.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import '../../state/native_grid_view.dart';
import '../../native_types.dart';

class GridCellWidget extends StatelessWidget {
  final int sectionIndex;
  final int gridIndex;
  final int row;
  final int column;
  
  const GridCellWidget({
    required this.sectionIndex,
    required this.gridIndex,
    required this.row,
    required this.column,
    super.key,
  });
  
  @override
  Widget build(BuildContext context) {
    final sequencer = context.watch<SequencerState>();
    final gridView = sequencer.getGridView(sectionIndex, gridIndex);
    
    // Direct binding to native memory via ValueListenable
    return ValueListenableBuilder<Cell>(
      valueListenable: gridView.getCellNotifier(row, column),
      builder: (context, cell, _) {
        return GestureDetector(
          onTap: () => _onCellTap(context, sequencer, cell),
          child: Container(
            decoration: BoxDecoration(
              color: _getCellColor(cell),
              border: Border.all(color: Colors.black26, width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: _buildCellContent(cell),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCellContent(Cell cell) {
    if (cell.sample_slot >= 0) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${cell.sample_slot}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (cell.volume != -1.0 || cell.pitch != -1.0)
            Text(
              'V${cell.volume.toStringAsFixed(1)} P${cell.pitch.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 6,
                color: Colors.white70,
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
  
  Color _getCellColor(Cell cell) {
    if (cell.sample_slot >= 0) {
      // Color based on sample slot
      final colors = [
        Colors.blue[600]!,
        Colors.green[600]!,
        Colors.red[600]!,
        Colors.purple[600]!,
        Colors.orange[600]!,
        Colors.teal[600]!,
      ];
      return colors[cell.sample_slot % colors.length];
    }
    return Colors.grey[300]!;
  }
  
  void _onCellTap(BuildContext context, SequencerState sequencer, Cell cell) {
    // Toggle sample (simple example)
    final newSample = cell.sample_slot >= 0 ? null : 0;
    sequencer.setCell(sectionIndex, gridIndex, row, column, newSample);
  }
}
```

### B. Grid Widget

**File: `app/lib/widgets/sequencer/sound_grid_widget.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sequencer_state.dart';
import 'grid_cell_widget.dart';

class SoundGridWidget extends StatelessWidget {
  final int sectionIndex;
  final int gridIndex;
  
  const SoundGridWidget({
    required this.sectionIndex,
    required this.gridIndex,
    super.key,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<SequencerState, (int, int)>(
      selector: (context, state) => (
        state.currentSection, 
        state.getGridView(sectionIndex, gridIndex).rows,
      ),
      builder: (context, data, child) {
        final (currentSection, rows) = data;
        final sequencer = context.read<SequencerState>();
        final gridView = sequencer.getGridView(sectionIndex, gridIndex);
        
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: currentSection == sectionIndex 
                ? Colors.blue 
                : Colors.grey[400]!,
              width: currentSection == sectionIndex ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridView.columns,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 1.0,
            ),
            itemCount: rows * gridView.columns,
            itemBuilder: (context, index) {
              final row = index ~/ gridView.columns;
              final col = index % gridView.columns;
              
              return GridCellWidget(
                sectionIndex: sectionIndex,
                gridIndex: gridIndex,
                row: row,
                column: col,
              );
            },
          ),
        );
      },
    );
  }
}
```

---

## 5. Migration Plan

### Phase 1: Preparation (1 week)
- [ ] **Native Implementation**: Add enhanced Cell structure with change tracking
- [ ] **FFI Extensions**: Implement all new native functions
- [ ] **FFI Bindings**: Update `ffigen_sequencer.yaml` and regenerate bindings
- [ ] **File Rename**: Rename `sequencer_state.dart` → `sequencer_state_old.dart`
- [ ] **Testing**: Create unit tests for native change tracking functions

### Phase 2: New Architecture (1-2 weeks)  
- [ ] **Core Classes**: Implement `NativeGridView`, `ChangeTracker`
- [ ] **New SequencerState**: Create new `sequencer_state.dart` from scratch
- [ ] **Basic UI**: Create `GridCellWidget`, `SoundGridWidget` using new architecture
- [ ] **Integration Testing**: Test pointer access and change tracking in isolation

### Phase 3: Feature Parity (2-3 weeks)
- [ ] **Sequencer Controls**: Implement play/stop/BPM controls
- [ ] **Section Management**: Add section switching, creation, sizing 
- [ ] **Cell Operations**: Implement set/clear/volume/pitch operations
- [ ] **Advanced Features**: Add recording, preview systems, undo/redo
- [ ] **Performance Testing**: Profile and optimize Ticker polling

### Phase 4: Migration & Cleanup (1 week)
- [ ] **App Integration**: Switch main app to use new `SequencerState`
- [ ] **Compatibility Layer**: Create temporary compatibility wrapper if needed
- [ ] **Code Removal**: Remove old state management code
- [ ] **Documentation**: Update all documentation and examples
- [ ] **Final Testing**: Comprehensive testing on all platforms

---

## 6. Performance Characteristics

### Memory Usage
- **Static Memory**: All data in native static arrays, predictable usage
- **Zero Copy**: Dart accesses native memory directly via pointers
- **Minimal Flutter State**: Only UI-related ValueNotifiers in Flutter

### Update Efficiency  
- **Change-Driven**: Only modified cells trigger UI updates
- **Batched Updates**: All changes processed once per frame
- **Frame-Perfect**: Ticker ensures 60fps synchronization

### Scalability
- **Large Tables**: Direct pointer access scales with table size
- **Multiple Sections**: Section boundaries calculated in native
- **Complex Grids**: Grid layering handled efficiently in native

---

## 7. Benefits & Trade-offs

### Benefits ✅
1. **🎯 Single Source of Truth**: Native `g_cells` is authoritative
2. **⚡ Zero-Copy Access**: Direct pointer access eliminates data copying
3. **🔄 Efficient Updates**: Only changed cells trigger UI rebuilds  
4. **📈 Frame-Perfect Sync**: Ticker ensures smooth 60fps updates
5. **🏗️ Clean Architecture**: Clear separation between native data and Flutter UI
6. **🚀 Performance**: Eliminates sync overhead, reduces memory usage
7. **🎪 Per-Section Sizes**: Native tracks individual section sizes correctly
8. **🛡️ Memory Safety**: Static arrays eliminate allocation/deallocation bugs

### Trade-offs ⚖️
1. **Complexity**: More complex FFI integration
2. **Platform Differences**: Pointer behavior may vary across platforms
3. **Debugging**: Native memory issues harder to debug than Dart objects
4. **Migration Risk**: Large codebase changes require careful testing

---

## 8. Testing Strategy

### Unit Tests
- [ ] Native change tracking functions
- [ ] Section boundary calculations  
- [ ] Pointer arithmetic validation
- [ ] Memory safety checks

### Integration Tests
- [ ] FFI binding functionality
- [ ] Ticker synchronization accuracy
- [ ] Change detection reliability
- [ ] Cross-platform compatibility

### Performance Tests
- [ ] Memory usage profiling
- [ ] Frame timing analysis
- [ ] Large table scalability
- [ ] Concurrent access safety

### User Acceptance Tests
- [ ] Feature parity verification
- [ ] UI responsiveness testing
- [ ] Audio quality validation
- [ ] Stability testing

This architecture provides a robust foundation for high-performance audio sequencing with minimal Flutter-native synchronization overhead and precise, efficient UI updates.


