import 'package:flutter/foundation.dart';
import 'dart:ffi' as ffi;
// removed unused json ffi imports
import '../../ffi/table_bindings.dart';
import '../../ffi/playback_bindings.dart';
// uses Cell/CellData types from table_bindings.dart

/// ## How to Add a New Property
/// 
/// To add a new property that syncs from native to Flutter state:
/// 
/// 1. **Add private field to PlaybackState:**
///    ```dart
///    int _myNewProperty = 0;
///    ```
/// 
/// 2. **Add ValueNotifier for UI binding:**
///    ```dart
///    final ValueNotifier<int> myNewPropertyNotifier = ValueNotifier<int>(0);
///    ```
/// 
/// 3. **Add field to _NativePlaybackState:**
///    ```dart
///    class _NativePlaybackState {
///      // ... existing fields
///      final int myNewProperty;
///      
///      const _NativePlaybackState({
///        // ... existing parameters
///        required this.myNewProperty,
///      });
///    }
///    ```
/// 
/// 4. **Update syncPlaybackState() to read native value:**
///    ```dart
///    nativePlaybackState = _NativePlaybackState(
///      // ... existing fields
///      myNewProperty: ptr.ref.my_new_property,
///    );
///    ```
/// 
/// 5. **Add comparison in _updateStateFromNative():**
///    ```dart
///    if (_myNewProperty != nativePlaybackState.myNewProperty) {
///      _myNewProperty = nativePlaybackState.myNewProperty;
///      myNewPropertyNotifier.value = nativePlaybackState.myNewProperty;
///      anyChanged = true;
///    }
///    ```
/// 
/// 6. **Add getter (optional):**
///    ```dart
///    int get myNewProperty => _myNewProperty;
///    ```
/// 
/// 7. **Dispose the ValueNotifier:**
///    ```dart
///    myNewPropertyNotifier.dispose();
///    ```
/// 

/// Simple data class to hold native table state snapshot
class _NativeTableState {
  final int sectionsCount;
  final ffi.Pointer<Cell> tablePtr;
  final ffi.Pointer<Section> sectionsPtr;
  final ffi.Pointer<Layer> layersPtr;
  
  const _NativeTableState({
    required this.sectionsCount,
    required this.tablePtr,
    required this.sectionsPtr,
    required this.layersPtr,
  });
}

// Removed Flutter-side TableSnapshot; snapshot handled natively

/// Flutter state management for native sequencer table
/// 
/// This file maintains references/pointers to native table data and provides
/// efficient change tracking using ValueNotifiers for UI updates.
enum SoundGridViewMode { stack, flat }
enum EditButtonsLayoutMode { v1, v2 }

class TableState extends ChangeNotifier {
  static const int defaultSectionSteps = 16;
  static const int maxLayersPerSection = 4;
  static const int maxColsPerLayer = 4;
  static const int maxSections = 64;
  
  final TableBindings _table_ffi;
  final PlaybackBindings _playback_ffi;
  
  // Auto-save callback (set by ThreadsState)
  void Function()? _onStateChanged;
  
  // 2D array of ValueNotifiers for efficient cell updates (sized dynamically based on native table dimensions)
  late final List<List<ValueNotifier<CellData>?>> _cellNotifiers;
  
  // Private state fields (synced from native)
  int _sectionsCount = 1;
  bool _initialized = false;
  ffi.Pointer<Cell> _tablePtr = ffi.nullptr;
  ffi.Pointer<Section> _sectionsPtr = ffi.nullptr;
  
  // Table dimensions (constants from native)
  int _maxSteps = 2048;
  int _maxCols = 16;
  
  // Flutter-only UI selection (for smart sync)
  int _uiSelectedSection = 0;  // Which section UI is currently viewing
  int _uiSelectedLayer = 0;    // Which layer UI is currently viewing
  
  // ValueNotifier for selected layer to ensure UI always updates
  final ValueNotifier<int> uiSelectedLayerNotifier = ValueNotifier<int>(0);
  
  // UI: sound grid view mode (stacked cards vs flat tabs)
  SoundGridViewMode _uiSoundGridViewMode = SoundGridViewMode.flat;
  // UI: edit buttons layout mode (v1 classic, v2 right-aligned large)
  EditButtonsLayoutMode _uiEditButtonsLayoutMode = EditButtonsLayoutMode.v2;
  
  // Sound grid stack (multiple grids)
  int _uiCurrentSoundGridIndex = 0;
  final List<int> _uiSoundGridOrder = [0];

  int _activeSectionStepCount = defaultSectionSteps;

  TableState() : _table_ffi = TableBindings(), _playback_ffi = PlaybackBindings() {
    _initializeTable();
  }
  
  void _initializeTable() {
    debugPrint('🏗️ [TABLE_STATE] Initializing native table');
    _table_ffi.tableInit();
    _maxSteps = _table_ffi.tableGetMaxSteps();
    _maxCols = _table_ffi.tableGetMaxCols();
    
    // Initialize notifiers array based on actual table dimensions
    _cellNotifiers = List.generate(_maxSteps, 
      (_) => List.filled(_maxCols, null));
    
    _initialized = true;
    debugPrint('✅ [TABLE_STATE] Table initialized (${_maxSteps}x${_maxCols}, ${_maxSteps * _maxCols} cell capacity)');
  }
  
  /// Set UI selected section (Flutter-only, for smart sync optimization)
  void setUiSelectedSection(int section) {
    if (section >= 0 && section < _sectionsCount) {
      _uiSelectedSection = section;
      notifyListeners();
      debugPrint('🎭 [TABLE_STATE] Set UI selected section to $section');
    }
  }
  
  /// Set UI selected layer (Flutter-only, for smart sync optimization)
  void setUiSelectedLayer(int layer) {
    final layers = totalLayers;
    if (layer >= 0 && layer < layers) {
      final oldLayer = _uiSelectedLayer;
      _uiSelectedLayer = layer;
      uiSelectedLayerNotifier.value = layer; // Update ValueNotifier for reliable UI updates
      
      if (oldLayer != layer) {
        debugPrint('🎨 [TABLE_STATE] ✅ Switched UI layer from $oldLayer to $layer / totalLayers=$layers');
      } else {
        debugPrint('🎨 [TABLE_STATE] Layer $layer reselected (forcing UI update)');
      }
      
      // Always call notifyListeners to ensure UI updates, even if layer didn't change
      // This handles cases where the UI state might be out of sync
      notifyListeners();
    } else {
      debugPrint('⚠️ [TABLE_STATE] Ignored setUiSelectedLayer($layer) out of range [0, ${layers - 1}]');
    }
  }

  /// Set UI view mode for sound grids (stack vs flat)
  void setUiSoundGridViewMode(SoundGridViewMode mode) {
    if (_uiSoundGridViewMode == mode) return;
    _uiSoundGridViewMode = mode;
    notifyListeners();
    debugPrint('🎛️ [TABLE_STATE] Set UI sound grid view mode to $mode');
  }

  /// Set UI edit buttons layout mode (v1 vs v2)
  void setUiEditButtonsLayoutMode(EditButtonsLayoutMode mode) {
    if (_uiEditButtonsLayoutMode == mode) return;
    _uiEditButtonsLayoutMode = mode;
    notifyListeners();
    debugPrint('🎚️ [TABLE_STATE] Set UI edit buttons layout mode to $mode');
  }

  // Removed: setUiColsPerLayer; using native layers config
  
  /// Get pointer to native cell (direct memory access)
  ffi.Pointer<Cell> getCellPointer(int step, int col) {
    return _table_ffi.tableGetCell(step, col);
  }

  /// Get pointer to native table state (for snapshot export)
  ffi.Pointer<NativeTableState> getTableStatePtr() {
    return _table_ffi.tableGetStatePtr();
  }
  
  /// CRUD operations (delegate to native and update UI)
  void setCell(int step, int col, int sampleSlot, double volume, double pitch, {bool undoRecord = true}) {
    _table_ffi.tableSetCell(step, col, sampleSlot, volume, pitch, undoRecord ? 1 : 0);
    // debugPrint('✏️ [TABLE_STATE] Set cell [$step, $col]: slot=$sampleSlot, vol=${volume.toStringAsFixed(2)}');
  }
  
  void clearCell(int step, int col, {bool undoRecord = true}) {
    _table_ffi.tableClearCell(step, col, undoRecord ? 1 : 0);
    // debugPrint('🧹 [TABLE_STATE] Cleared cell [$step, $col]');  // Commented out to reduce log spam
  }

  /// Bulk clear all cells in the table (efficient for import/reset operations)
  /// This clears all cells without syncing to SunVox (patterns are managed separately)
  void clearAllCells() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot clear cells - table not initialized');
      return;
    }
    
    debugPrint('🧹 [TABLE_STATE] Bulk clearing all cells');
    _table_ffi.tableClearAllCells();
    debugPrint('✅ [TABLE_STATE] Bulk clear complete');
  }

  /// Disable automatic SunVox sync (for bulk operations like import)
  void disableSunvoxSync() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot disable sync - table not initialized');
      return;
    }
    
    _table_ffi.tableDisableSunvoxSync();
  }

  /// Re-enable automatic SunVox sync
  void enableSunvoxSync() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot enable sync - table not initialized');
      return;
    }
    
    _table_ffi.tableEnableSunvoxSync();
  }

  /// Update cell audio settings (volume, pitch) while preserving sample slot
  void setCellSettings(int step, int col, {double? volume, double? pitch, bool undoRecord = true}) {
    final cellPtr = getCellPointer(step, col);
    if (cellPtr.address == 0) return;
    final current = cellPtr.ref;
    // Preserve sentinel (-1.0) for volume if not explicitly set
    double nextVolume = volume ?? current.settings.volume;
    if (nextVolume >= 0.0) nextVolume = nextVolume.clamp(0.0, 1.0);

    // For pitch, keep sentinel when not explicitly set; otherwise clamp to valid range
    double nextPitch = pitch ?? current.settings.pitch;
    if (nextPitch >= 0.0) nextPitch = nextPitch.clamp(0.03125, 32.0);
    
    _table_ffi.tableSetCell(step, col, current.sample_slot, nextVolume, nextPitch, undoRecord ? 1 : 0);
    debugPrint('🎚️ [TABLE_STATE] Set cell settings [$step, $col]: vol=${nextVolume.toStringAsFixed(2)}, pitch=${nextPitch.toStringAsFixed(2)}');
  }

  void insertStep(int sectionIndex, int atStep, {bool undoRecord = true}) {
    _table_ffi.tableInsertStep(sectionIndex, atStep, undoRecord ? 1 : 0);
    debugPrint('➕ [TABLE_STATE] Inserted step at $atStep in section $sectionIndex');
  }
  
  void deleteStep(int sectionIndex, int atStep, {bool undoRecord = true}) {
    _table_ffi.tableDeleteStep(sectionIndex, atStep, undoRecord ? 1 : 0);
    debugPrint('➖ [TABLE_STATE] Deleted step at $atStep in section $sectionIndex');
  }

  /// Bulk update of many cells (flat list of cells, row-major by MAX_COLS)
  /// cellsFlat length must be a multiple of _maxCols. Number of rows is inferred.
  void updateManyCells(int startRow, List<CellData> cellsFlat) {
    if (cellsFlat.isEmpty) return;
    if (cellsFlat.length % _maxCols != 0) {
      throw ArgumentError('cellsFlat length (${cellsFlat.length}) must be a multiple of maxCols ($_maxCols)');
    }
    final numRows = cellsFlat.length ~/ _maxCols;
    int idx = 0;
    for (int r = 0; r < numRows; r++) {
      final step = startRow + r;
      for (int c = 0; c < _maxCols; c++) {
        final cell = cellsFlat[idx++];
        final isLast = (r == numRows - 1) && (c == _maxCols - 1);
        _table_ffi.tableSetCell(step, c, cell.sampleSlot, cell.volume, cell.pitch, isLast ? 1 : 0);
      }
    }
    debugPrint('🧩 [TABLE_STATE] Updated many cells from row $startRow, rows=$numRows');
  }

  /// Bulk update of many sections using SectionData list
  void updateManySections(int startIndex, List<SectionData> sections) {
    if (sections.isEmpty) return;
    final count = sections.length;
    for (int i = 0; i < count; i++) {
      final s = sections[i];
      final isLast = (i == count - 1);
      _table_ffi.tableSetSection(startIndex + i, s.startStep, s.numSteps, isLast ? 1 : 0);
    }
    debugPrint('🧭 [TABLE_STATE] Updated many sections from index $startIndex, count=$count');
  }

  /// Bulk update of many layers. layersLenFlat is row-major per section with MAX_LAYERS_PER_SECTION entries each
  void updateManyLayers(int startSection, int countSections, List<int> layersLenFlat) {
    if (countSections <= 0) return;
    if (layersLenFlat.length != countSections * maxLayersPerSection) {
      throw ArgumentError('layersLenFlat length (${layersLenFlat.length}) must equal countSections($countSections) * maxLayersPerSection($maxLayersPerSection)');
    }
    int k = 0;
    for (int s = 0; s < countSections; s++) {
      final sectionIndex = startSection + s;
      for (int l = 0; l < maxLayersPerSection; l++) {
        final isLast = (s == countSections - 1) && (l == maxLayersPerSection - 1);
        _table_ffi.tableSetLayerLen(sectionIndex, l, layersLenFlat[k++], isLast ? 1 : 0);
      }
    }
    debugPrint('🎚️ [TABLE_STATE] Updated many layers from section $startSection, count=$countSections');
  }
    
  /// Get notifier for specific cell (efficient 2D array access, lazy initialization)
  ValueNotifier<CellData> getCellNotifier(int step, int col) {
    if (step >= _maxSteps || col >= _maxCols) {
      throw ArgumentError('Cell out of bounds: [$step, $col] (max: $_maxSteps x $_maxCols)');
    }
    
    // Lazy initialization of notifiers
    _cellNotifiers[step][col] ??= ValueNotifier(
      CellData.fromPointer(getCellPointer(step, col))
    );
    
    return _cellNotifiers[step][col]!;
  }

  // Convenience: read a single cell snapshot (no notifier) using direct pointer
  CellData readCell(int step, int col) {
    final ptr = getCellPointer(step, col);
    return CellData.fromPointer(ptr);
  }
  
  /// Sync table state from native using seqlock pattern (called by timer each frame)
  void syncTableState() {
    if (!_initialized) return;
    
    final ffi.Pointer<NativeTableState> ptr = _table_ffi.tableGetStatePtr();
    int tries = 0;
    const maxTries = 3;
    late final _NativeTableState nativeTableState;
    
    // Seqlock pattern: read with version check for consistency
    while (true) {
      final v1 = ptr.ref.version;
      if ((v1 & 1) != 0) { // writer in progress
        if (++tries >= maxTries) return; // skip this frame
        continue;
      }
      nativeTableState = _NativeTableState(
        sectionsCount: ptr.ref.sections_count,
        tablePtr: ptr.ref.table_ptr,
        sectionsPtr: ptr.ref.sections_ptr,
        layersPtr: ptr.ref.layers_ptr,
      );
      final v2 = ptr.ref.version;
      if (v1 == v2) break;
      if (++tries >= maxTries) return;
    }
    
    _updateStateFromNative(nativeTableState);
  }

  /// Update local state when native state changes
  void _updateStateFromNative(_NativeTableState nativeTableState) {
    bool anyChanged = false;
    
    // Check and update each property
    if (_sectionsCount != nativeTableState.sectionsCount) {
      _sectionsCount = nativeTableState.sectionsCount;
      anyChanged = true;
    }
    
    if (_tablePtr != nativeTableState.tablePtr) {
      _tablePtr = nativeTableState.tablePtr;
      anyChanged = true;
    }
    
    if (_sectionsPtr != nativeTableState.sectionsPtr) {
      _sectionsPtr = nativeTableState.sectionsPtr;
      anyChanged = true;
    }

    final activeSectionNumSteps = (_sectionsPtr + _uiSelectedSection).ref.num_steps;
    if (activeSectionNumSteps != _activeSectionStepCount) {
      _activeSectionStepCount = activeSectionNumSteps;
      anyChanged = true;
    }
    
    if (anyChanged) {
      notifyListeners();
    }
    
    _updateVisibleCells();
  }
  
  /// Smart cell synchronization: only sync cells in visible UI section/layer
  void _updateVisibleCells() {
    if (_tablePtr == ffi.nullptr || _sectionsPtr == ffi.nullptr) return;
    if (_uiSelectedSection >= _sectionsCount) return;
    
    // Direct sections access: Get section bounds without FFI calls
    final sectionPtr = _sectionsPtr + _uiSelectedSection;
    final sectionStartStep = sectionPtr.ref.start_step;
    final sectionStepCount = sectionPtr.ref.num_steps;
    final sectionEndStep = sectionStartStep + sectionStepCount;
    
    // Calculate visible layer bounds (columns) using native layers config
    final layerStartCol = getLayerStartCol(_uiSelectedLayer);
    final layerEndCol = getLayerEndCol(_uiSelectedLayer);
    
    // Direct table access: Only sync cells in the visible rectangular area
    for (int step = sectionStartStep; step < sectionEndStep && step < _maxSteps; step++) {
      for (int col = layerStartCol; col < layerEndCol && col < _maxCols; col++) {
        _notifyCellChangeDirect(step, col);
      }
    }
  }
  
  /// Direct cell change notification using table pointer
  void _notifyCellChangeDirect(int step, int col) {
    if (step < _maxSteps && col < _maxCols) {
      final notifier = _cellNotifiers[step][col];
      if (notifier != null) {
        // Direct access: calculate cell pointer from base table pointer
        final cellIndex = step * _maxCols + col;
        final cellPtr = _tablePtr + cellIndex;
        notifier.value = CellData.fromPointer(cellPtr);
      }
    }
  }
  
  /// Set section step count
  void setSectionStepCount(int sectionIndex, int steps, {bool undoRecord = true}) {
    if (steps > 0 && steps <= _maxSteps) {
      _table_ffi.tableSetSectionStepCount(sectionIndex, steps, undoRecord ? 1 : 0);
      // notifyListeners();
      debugPrint('📏 [TABLE_STATE] Set section $sectionIndex step count to $steps');
    }
  }

  void appendSection({int? copyFrom, bool undoRecord = true}) {
    _table_ffi.tableAppendSection!(defaultSectionSteps, (copyFrom ?? -1), undoRecord ? 1 : 0);
    final newIndex = (_sectionsCount); // new section will be at current count index
    _uiSelectedSection = newIndex;
    notifyListeners();
    debugPrint('🆕 [TABLE_STATE] Appended section and selected index $newIndex');
  }

  void deleteSection(int sectionIndex, {bool undoRecord = true}) {
    _table_ffi.tableDeleteSection!(sectionIndex, undoRecord ? 1 : 0);
    // notifyListeners();
    debugPrint('🗑️ [TABLE_STATE] Deleted section $sectionIndex');
  }

  void reorderSection(int fromIndex, int toIndex, {bool undoRecord = false}) {
    if (fromIndex == toIndex) return;
    _table_ffi.tableReorderSection!(fromIndex, toIndex, undoRecord ? 1 : 0);
    debugPrint('🔄 [TABLE_STATE] Reordered section $fromIndex → $toIndex');
  }

  // Section management clipboard
  int? _copiedSectionIndex;
  
  bool get hasCopiedSection => _copiedSectionIndex != null && _copiedSectionIndex! < sectionsCount;
  
  void copySectionToClipboard(int sectionIndex) {
    _copiedSectionIndex = sectionIndex;
    debugPrint('📋 [TABLE_STATE] Copied section $sectionIndex to clipboard');
    notifyListeners();
  }
  
  // Helper: Validate clipboard has valid section
  bool _hasValidClipboard() {
    if (_copiedSectionIndex == null || _copiedSectionIndex! >= sectionsCount) {
      debugPrint('⚠️ [TABLE_STATE] Cannot paste - no valid section in clipboard');
      return false;
    }
    return true;
  }
  
  // Helper: Insert section and reorder to target position
  void _insertSectionAt(int targetPosition, {int? copyFrom}) {
    final newIndex = _sectionsCount; // Read BEFORE appending
    appendSection(copyFrom: copyFrom ?? -1, undoRecord: true);
    
    if (newIndex != targetPosition) {
      reorderSection(newIndex, targetPosition);
    }
    
    _uiSelectedSection = targetPosition;
  }
  
  void pasteSection(int targetSection) {
    if (!_hasValidClipboard()) return;
    
    if (targetSection < 0 || targetSection >= sectionsCount) {
      debugPrint('⚠️ [TABLE_STATE] Invalid target section: $targetSection');
      return;
    }
    
    // Get section pointers and bounds
    final sourceSectionPtr = _sectionsPtr + _copiedSectionIndex!;
    final targetSectionPtr = _sectionsPtr + targetSection;
    final sourceStartStep = sourceSectionPtr.ref.start_step;
    final sourceStepCount = sourceSectionPtr.ref.num_steps;
    final targetStartStep = targetSectionPtr.ref.start_step;
    final targetStepCount = targetSectionPtr.ref.num_steps;
    
    // Resize target if needed
    if (targetStepCount != sourceStepCount) {
      setSectionStepCount(targetSection, sourceStepCount, undoRecord: true);
    }
    
    // Copy all cells
    for (int step = 0; step < sourceStepCount && step < _maxSteps; step++) {
      for (int col = 0; col < _maxCols; col++) {
        final sourceCell = getCellPointer(sourceStartStep + step, col).ref;
        final targetStep = targetStartStep + step;
        
        if (sourceCell.sample_slot >= 0) {
          setCell(targetStep, col, sourceCell.sample_slot, 
                 sourceCell.settings.volume, sourceCell.settings.pitch, undoRecord: false);
        } else {
          clearCell(targetStep, col, undoRecord: false);
        }
      }
    }
    
    debugPrint('📋 [TABLE_STATE] Pasted section $_copiedSectionIndex contents into section $targetSection');
    notifyListeners();
  }
  
  void pasteSectionAfter(int afterIndex) {
    if (!_hasValidClipboard()) return;
    
    _insertSectionAt(afterIndex + 1, copyFrom: _copiedSectionIndex);
    debugPrint('📋 [TABLE_STATE] Pasted section from clipboard after section $afterIndex');
    notifyListeners();
  }
  
  void addSectionAfter(int afterIndex) {
    _insertSectionAt(afterIndex + 1);
    debugPrint('➕ [TABLE_STATE] Added new section after section $afterIndex');
    notifyListeners();
  }
  
  // Getters
  int get maxSteps => _maxSteps;
  int get maxCols => _maxCols;
  int get sectionsCount => _sectionsCount;
  int get uiSelectedSection => _uiSelectedSection;
  int get uiSelectedLayer => _uiSelectedLayer;
  bool get initialized => _initialized;
  SoundGridViewMode get uiSoundGridViewMode => _uiSoundGridViewMode;
  EditButtonsLayoutMode get uiEditButtonsLayoutMode => _uiEditButtonsLayoutMode;

  /// Get layers-per-section count including empty layers (length = sectionsCount)
  List<int> getLayersLengthPerSection() {
    final count = sectionsCount;
    if (count <= 0) return const <int>[];
    // All sections expose the same maxLayersPerSection, include empty ones
    return List<int>.filled(count, maxLayersPerSection);
  }
  
  // Get section-specific data using direct sections access
  int getSectionStepCount([int? sectionIndex]) {
    final index = sectionIndex ?? _uiSelectedSection;
    if (_sectionsPtr == ffi.nullptr || index >= _sectionsCount) return 16; // default
    return (_sectionsPtr + index).ref.num_steps;
  }
  
  int getSectionStartStep([int? sectionIndex]) {
    final index = sectionIndex ?? _uiSelectedSection;
    if (_sectionsPtr == ffi.nullptr || index >= _sectionsCount) return 0; // default
    return (_sectionsPtr + index).ref.start_step;
  }
  
  int getSectionAtStep(int step) {
    if (_sectionsPtr == ffi.nullptr) return _table_ffi.tableGetSectionAtStep(step);
    
    // Direct search through sections
    for (int i = 0; i < _sectionsCount; i++) {
      final sectionPtr = _sectionsPtr + i;
      final start = sectionPtr.ref.start_step;
      final end = start + sectionPtr.ref.num_steps;
      if (step >= start && step < end) {
        return i;
      }
    }
    return -1; // Not in any section
  }
  
  // Helper methods for UI layer calculations
  int getLayerStartCol([int? layer]) {
    final targetLayer = layer ?? _uiSelectedLayer;
    final layersBase = _table_ffi.tableGetStatePtr().ref.layers_ptr;
    int start = 0;
    for (int l = 0; l < targetLayer; l++) {
      final li = _uiSelectedSection * maxLayersPerSection + l;
      start += (layersBase + li).ref.len;
    }
    return start;
  }
  
  int getLayerEndCol([int? layer]) {
    final targetLayer = layer ?? _uiSelectedLayer;
    if (_sectionsPtr == ffi.nullptr) return ((targetLayer + 1) * maxColsPerLayer).clamp(0, _maxCols);
    final layersBase = _table_ffi.tableGetStatePtr().ref.layers_ptr;
    final len = (layersBase + (_uiSelectedSection * maxLayersPerSection + targetLayer)).ref.len;
    final start = getLayerStartCol(targetLayer);
    final end = (start + len).clamp(0, _maxCols);
    return end;
  }
  
  List<int> getVisibleCols([int? layer]) {
    final start = getLayerStartCol(layer);
    final end = getLayerEndCol(layer);
    return List.generate(end - start, (i) => start + i);
  }

  // Derived UI info
  int get totalLayers => maxLayersPerSection;
  

  void uiAppendStep() {
    final currentSteps = getSectionStepCount(_uiSelectedSection);
    if (currentSteps < _maxSteps) {
      final sectionStart = getSectionStartStep(_uiSelectedSection);
      insertStep(_uiSelectedSection, sectionStart + currentSteps);
      _playback_ffi.playbackSetRegion(sectionStart, sectionStart + currentSteps + 1);
    }
  }
  
  void uiDeleteLastStep() {
    final currentSteps = getSectionStepCount(_uiSelectedSection);
    if (currentSteps > 1) {
      final sectionStart = getSectionStartStep(_uiSelectedSection);
      deleteStep(_uiSelectedSection, sectionStart + currentSteps - 1);
      _playback_ffi.playbackSetRegion(sectionStart, sectionStart + currentSteps - 1);
    }
  }

  
  // Sound grid stack
  int get uiCurrentSoundGridIndex => _uiCurrentSoundGridIndex;
  List<int> get uiSoundGridOrder => List.unmodifiable(_uiSoundGridOrder);
  
  void uiInitializeSoundGrids(int count) {
    _uiSoundGridOrder.clear();
    for (int i = 0; i < count; i++) {
      _uiSoundGridOrder.add(i);
    }
    _uiCurrentSoundGridIndex = 0;
    notifyListeners();
  }
  
  void uiBringGridToFront(int gridIndex) {
    if (_uiSoundGridOrder.contains(gridIndex)) {
      _uiSoundGridOrder.remove(gridIndex);
      _uiSoundGridOrder.insert(0, gridIndex);
      _uiCurrentSoundGridIndex = gridIndex;
      notifyListeners();
    }
  }
  
  // (Removed) uiSlotPlaying accessors
  
  // Essential grid methods (use ValueNotifiers from getCellNotifier instead of helper functions)
  
  void uiPlaceSampleInGrid(int sampleSlot, int flatIndex) {
    final visibleCols = getVisibleCols().length;
    final row = flatIndex ~/ visibleCols;
    final colInSlice = flatIndex % visibleCols;
    final layerStart = getLayerStartCol(_uiSelectedLayer);
    final col = layerStart + colInSlice;
    final step = row + getSectionStartStep(_uiSelectedSection);
    
    if (col < _maxCols && step < _maxSteps) {
      // Use sentinel defaults so volume/pitch inherit from sample bank until overridden
      setCell(step, col, sampleSlot, -1.0, -1.0);
    }
  }
  
  void uiHandlePadPress(int flatIndex) {
    // Set active pad for UI highlighting
    debugPrint('🎵 [TABLE_STATE] Pad pressed: $flatIndex');
    // Could trigger sample preview in the future
  }

  /// Sync a single section to its SunVox pattern
  /// This ensures all cells in the section are properly synced to SunVox
  void syncSectionToSunVox(int sectionIndex) {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot sync section - table not initialized');
      return;
    }
    
    if (sectionIndex < 0 || sectionIndex >= _sectionsCount) {
      debugPrint('⚠️ [TABLE_STATE] Invalid section index: $sectionIndex (have $_sectionsCount sections)');
      return;
    }
    
    try {
      _playback_ffi.sunvoxSyncSection(sectionIndex);
    } catch (e) {
      debugPrint('❌ [TABLE_STATE] Failed to sync section $sectionIndex: $e');
    }
  }

  /// Sync all sections to SunVox patterns
  /// This ensures all table cells are properly synced to SunVox after bulk operations like import
  void syncAllSectionsToSunVox() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot sync sections - table not initialized');
      return;
    }
    
    try {
      debugPrint('🔄 [TABLE_STATE] Syncing all $_sectionsCount sections to SunVox');
      for (int i = 0; i < _sectionsCount; i++) {
        _playback_ffi.sunvoxSyncSection(i);
      }
      debugPrint('✅ [TABLE_STATE] All sections synced to SunVox');
    } catch (e) {
      debugPrint('❌ [TABLE_STATE] Failed to sync sections: $e');
    }
  }

  /// Reset ALL SunVox patterns (used before import to ensure clean state)
  /// This completely removes all existing patterns and clears all mappings
  void resetAllSunVoxPatterns() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot reset patterns - table not initialized');
      return;
    }
    
    try {
      debugPrint('🔄 [TABLE_STATE] Resetting all SunVox patterns');
      _playback_ffi.sunvoxResetAllPatterns();
      debugPrint('✅ [TABLE_STATE] All SunVox patterns reset');
    } catch (e) {
      debugPrint('❌ [TABLE_STATE] Failed to reset patterns: $e');
    }
  }

  /// Update the SunVox timeline seamlessly (recalculate pattern X positions)
  /// This ensures all pattern X positions match the table layout without stopping playback
  /// Call this after bulk operations that create/resize patterns (like import)
  void updateTimelineSeamless() {
    if (!_initialized) {
      debugPrint('⚠️ [TABLE_STATE] Cannot update timeline - table not initialized');
      return;
    }
    
    try {
      // Pass -1 to update all patterns (not a specific section)
      _playback_ffi.sunvoxUpdateTimelineSeamless(-1);
    } catch (e) {
      debugPrint('❌ [TABLE_STATE] Failed to update timeline: $e');
    }
  }

  /// Set callback for state changes (used by ThreadsState for auto-save)
  void setOnStateChanged(void Function()? callback) {
    _onStateChanged = callback;
  }
  
  @override
  void notifyListeners() {
    super.notifyListeners();
    
    // Trigger auto-save if callback is set
    _onStateChanged?.call();
  }
  
  @override
  void dispose() {
    debugPrint('🧹 [TABLE_STATE] Disposing state and notifiers');
    
    // Dispose all notifiers
    for (var row in _cellNotifiers) {
      for (var notifier in row) {
        notifier?.dispose();
      }
    }
    
    uiSelectedLayerNotifier.dispose();
    
    super.dispose();
  }
}
