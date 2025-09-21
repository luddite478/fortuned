import 'package:flutter/foundation.dart';
import 'table.dart';
import 'ui_selection.dart';
import '../../ffi/table_bindings.dart' show CellData;

/// State management for edit operations (copy, paste, select, jump insert)
/// Handles table editing functionality
class EditState extends ChangeNotifier {
  final TableState _tableState;
  final UiSelectionState _uiSelection;
  final Set<int> _selectedCells = <int>{};
  // Capture grid width at selection time to decode indices consistently
  int _selectionTableCols = 0;
  
  // Selection state
  bool _isInSelectionMode = false;
  int? _lastSelectedCell;
  
  // Clipboard state
  bool _hasClipboardData = false;
  List<CellClipboardData> _clipboardData = [];
  
  // Jump insert state
  bool _isStepInsertMode = false;
  int _stepInsertSize = 1;
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isInSelectionModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Set<int>> selectedCellsNotifier = ValueNotifier<Set<int>>(<int>{});
  final ValueNotifier<bool> hasClipboardDataNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isStepInsertModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> stepInsertSizeNotifier = ValueNotifier<int>(1);
  
  EditState(this._tableState, this._uiSelection) {
    // When unified selection switches to sample bank, clear cell selection without resetting UI selection
    _uiSelection.kindNotifier.addListener(() {
      if (_uiSelection.isSampleBank && _selectedCells.isNotEmpty) {
        _clearSelectionInternal(preserveUiSelection: true);
      }
    });
  }
  
  // Getters
  bool get isInSelectionMode => _isInSelectionMode;
  Set<int> get selectedCells => Set.unmodifiable(_selectedCells);
  bool get hasClipboardData => _hasClipboardData;
  bool get isStepInsertMode => _isStepInsertMode;
  int get stepInsertSize => _stepInsertSize;
  bool get hasSelection => _selectedCells.isNotEmpty;
  
  // Selection methods
  Set<int> _rectSelection(int anchor, int current, int tableCols) {
    final startRow = anchor ~/ tableCols;
    final startCol = anchor % tableCols;
    final endRow = current ~/ tableCols;
    final endCol = current % tableCols;
    final minRow = startRow < endRow ? startRow : endRow;
    final maxRow = startRow > endRow ? startRow : endRow;
    final minCol = startCol < endCol ? startCol : endCol;
    final maxCol = startCol > endCol ? startCol : endCol;
    final Set<int> next = <int>{};
    for (int r = minRow; r <= maxRow; r++) {
      for (int c = minCol; c <= maxCol; c++) {
        next.add(r * tableCols + c);
      }
    }
    return next;
  }

  void _applySelection(Set<int> next, {int? anchor}) {
    _applySelectionInternal(next, anchor: anchor, preserveUiSelection: false);
  }

  void _applySelectionInternal(Set<int> next, {int? anchor, bool preserveUiSelection = false}) {
    _selectedCells
      ..clear()
      ..addAll(next);
    if (anchor != null) {
      _lastSelectedCell = anchor;
    }
    // Record the grid width used during this selection change
    _selectionTableCols = _tableState.getVisibleCols().length;
    selectedCellsNotifier.value = Set.from(_selectedCells);
    // Update unified UI selection kind
    if (!preserveUiSelection) {
      if (_selectedCells.isNotEmpty) {
        _uiSelection.selectCells();
      } else {
        _uiSelection.clear();
      }
    }
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isInSelectionMode = !_isInSelectionMode;
    if (!_isInSelectionMode) {
      clearSelection();
    }
    
    isInSelectionModeNotifier.value = _isInSelectionMode;
    notifyListeners();
    debugPrint('✂️ [EDIT] Selection mode: $_isInSelectionMode');
  }
  
  void selectCell(int cellIndex, {bool extend = false}) {
    if (!_isInSelectionMode) return;
    
    if (extend) {
      final anchor = _lastSelectedCell ?? cellIndex;
      final tableCols = _tableState.getVisibleCols().length;
      final rect = _rectSelection(anchor, cellIndex, tableCols);
      _applySelection(rect, anchor: anchor);
    } else {
      // Single selection replaces previous, set anchor
      _applySelection({cellIndex}, anchor: cellIndex);
    }
    debugPrint('✂️ [EDIT] Selected cells: ${_selectedCells.length}');
  }

  // Select exactly one cell regardless of selection mode
  void selectSingleCell(int cellIndex) {
    _applySelection({cellIndex}, anchor: cellIndex);
    debugPrint('✂️ [EDIT] Selected single cell: $cellIndex');
  }

  // Begin a new drag-based rectangular selection starting at this cell
  void beginDragSelectionAt(int cellIndex) {
    _applySelection({cellIndex}, anchor: cellIndex);
    debugPrint('✂️ [EDIT] Begin drag selection at: $cellIndex');
  }
  
  void clearSelection({bool preserveUiSelection = false}) {
    _clearSelectionInternal(preserveUiSelection: preserveUiSelection);
  }

  void _clearSelectionInternal({bool preserveUiSelection = false}) {
    _lastSelectedCell = null;
    _selectionTableCols = 0;
    _applySelectionInternal({}, preserveUiSelection: preserveUiSelection);
    debugPrint('✂️ [EDIT] Cleared selection');
  }
  
  void selectAll() {
    if (!_isInSelectionMode) return;
    
    final tableCols = _tableState.getVisibleCols().length;
    final tableRows = _tableState.getSectionStepCount(_tableState.uiSelectedSection);
    _applySelection(List<int>.generate(tableRows * tableCols, (i) => i).toSet());
    debugPrint('✂️ [EDIT] Selected all cells: ${_selectedCells.length}');
  }
  
  // Clipboard methods
  void copyCells() {
    if (_selectedCells.isEmpty) return;
    
    _clipboardData.clear();
    final sectionStart = _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart = _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableCols = _selectionTableCols > 0 ? _selectionTableCols : _tableState.getVisibleCols().length;
    // Normalize copied coordinates to the top-left of the current selection
    final minRow = _selectedCells.map((i) => i ~/ tableCols).reduce((a, b) => a < b ? a : b);
    final minCol = _selectedCells.map((i) => i % tableCols).reduce((a, b) => a < b ? a : b);

    for (final cellIndex in _selectedCells) {
      final row = cellIndex ~/ tableCols;
      final colInSlice = cellIndex % tableCols;
      final step = sectionStart + row;
      final col = layerStart + colInSlice;
      
      final cellPtr = _tableState.getCellPointer(step, col);
      if (cellPtr.address != 0) {
        final cellData = CellData.fromPointer(cellPtr);
        _clipboardData.add(CellClipboardData(
          relativeRow: row - minRow,
          relativeCol: colInSlice - minCol,
          sampleSlot: cellData.isNotEmpty ? cellData.sampleSlot : null,
          volume: cellData.volume,
          pitch: cellData.pitch,
        ));
      }
    }
    
    _hasClipboardData = _clipboardData.isNotEmpty;
    hasClipboardDataNotifier.value = _hasClipboardData;
    notifyListeners();
    debugPrint('📋 [EDIT] Copied ${_clipboardData.length} cells');
  }
  
  void pasteCells() {
    if (!_hasClipboardData || _clipboardData.isEmpty) return;
    
    final sectionStart = _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart = _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableColsSel = _selectionTableCols > 0 ? _selectionTableCols : _tableState.getVisibleCols().length;
    
    // Find the top-left corner of the selection or use first selected cell
    int baseRow = 0;
    int baseCol = 0;
    if (_selectedCells.isNotEmpty) {
      if (_clipboardData.length == 1 && _lastSelectedCell != null) {
        // For single-cell paste, target exactly the anchor (visually selected cell)
        baseRow = _lastSelectedCell! ~/ tableColsSel;
        baseCol = _lastSelectedCell! % tableColsSel;
      } else {
        // For multi-cell paste, use top-left of the rectangle
        final rows = _selectedCells.map((i) => i ~/ tableColsSel);
        final cols = _selectedCells.map((i) => i % tableColsSel);
        baseRow = rows.reduce((a, b) => a < b ? a : b);
        baseCol = cols.reduce((a, b) => a < b ? a : b);
      }
    }
    
    if (_clipboardData.length > 1) {
      // Group clipboard items by absolute target row and bulk update per row
      final int maxCols = _tableState.maxCols;
      final Map<int, Map<int, CellData>> rowColToCell = <int, Map<int, CellData>>{};
      for (final clipData in _clipboardData) {
        final targetRow = baseRow + clipData.relativeRow;
        final targetCol = baseCol + clipData.relativeCol;
        final rowAbs = sectionStart + targetRow;
        final colAbs = layerStart + targetCol;
        if (rowAbs >= _tableState.maxSteps || colAbs >= maxCols) continue;
        final cell = (clipData.sampleSlot != null)
            ? CellData(sampleSlot: clipData.sampleSlot!, volume: clipData.volume, pitch: clipData.pitch, isProcessing: false)
            : const CellData(sampleSlot: -1, volume: 1.0, pitch: 1.0, isProcessing: false);
        rowColToCell.putIfAbsent(rowAbs, () => <int, CellData>{})[colAbs] = cell;
      }
      for (final rowAbs in rowColToCell.keys.toList()..sort()) {
        // Start from current row baseline
        final List<CellData> rowFlat = List<CellData>.generate(
          maxCols,
          (col) => CellData.fromPointer(_tableState.getCellPointer(rowAbs, col)),
        );
        // Overlay pasted cells for this row
        final overrides = rowColToCell[rowAbs]!;
        overrides.forEach((col, cell) {
          rowFlat[col] = cell;
        });
        _tableState.updateManyCells(rowAbs, rowFlat);
      }
    } else {
      for (final clipData in _clipboardData) {
        final targetRow = baseRow + clipData.relativeRow;
        final targetCol = baseCol + clipData.relativeCol;
        final step = sectionStart + targetRow;
        final col = layerStart + targetCol;
        
        if (step < _tableState.maxSteps && col < _tableState.maxCols) {
          if (clipData.sampleSlot != null) {
            _tableState.setCell(step, col, clipData.sampleSlot!, clipData.volume, clipData.pitch);
          } else {
            _tableState.clearCell(step, col);
          }
        }
      }
    }
    
    notifyListeners();
    debugPrint('📋 [EDIT] Pasted ${_clipboardData.length} cells');

    // Jump insert: after pasting, move selection down by configured cells
    if (_isStepInsertMode) {
      final tableColsAfter = _tableState.getVisibleCols().length;
      final maxRows = _tableState.getSectionStepCount(_tableState.uiSelectedSection);
      final nextBaseRow = (baseRow + _stepInsertSize).clamp(0, maxRows - 1);
      final nextIndex = nextBaseRow * tableColsAfter + baseCol;
      selectSingleCell(nextIndex);
      debugPrint('🔗 [EDIT] Jumped selection by $_stepInsertSize cells to row $nextBaseRow');
    }
  }
  
  void deleteCells() {
    if (_selectedCells.isEmpty) return;
    
    final sectionStart = _tableState.getSectionStartStep(_tableState.uiSelectedSection);
    final layerStart = _tableState.getLayerStartCol(_tableState.uiSelectedLayer);
    final tableCols = _selectionTableCols > 0 ? _selectionTableCols : _tableState.getVisibleCols().length;
    
    for (final cellIndex in _selectedCells) {
      final row = cellIndex ~/ tableCols;
      final colInSlice = cellIndex % tableCols;
      final step = sectionStart + row;
      final col = layerStart + colInSlice;
      
      if (step < _tableState.maxSteps && col < _tableState.maxCols) {
        _tableState.clearCell(step, col);
      }
    }
    
    notifyListeners();
    debugPrint('🗑️ [EDIT] Deleted ${_selectedCells.length} cells');
  }
  
  // Jump insert methods
  void toggleStepInsertMode() {
    _isStepInsertMode = !_isStepInsertMode;
    isStepInsertModeNotifier.value = _isStepInsertMode;
    notifyListeners();
    debugPrint('🔗 [EDIT] Jump insert mode: $_isStepInsertMode');
  }
  
  void setStepInsertSize(int size) {
    _stepInsertSize = size.clamp(1, 16);
    stepInsertSizeNotifier.value = _stepInsertSize;
    notifyListeners();
    debugPrint('🔗 [EDIT] Jump insert size: $_stepInsertSize');
  }
  
  void insertStepsAtPosition(int step) {
    _tableState.insertStep(_tableState.uiSelectedSection, step);
    notifyListeners();
    debugPrint('➕ [EDIT] Inserted step at position $step');
  }
  
  void deleteStepAtPosition(int step) {
    _tableState.deleteStep(_tableState.uiSelectedSection, step);
    notifyListeners();
    debugPrint('➖ [EDIT] Deleted step at position $step');
  }
  
  @override
  void dispose() {
    isInSelectionModeNotifier.dispose();
    selectedCellsNotifier.dispose();
    hasClipboardDataNotifier.dispose();
    isStepInsertModeNotifier.dispose();
    stepInsertSizeNotifier.dispose();
    super.dispose();
  }
}

/// Data structure for clipboard operations
class CellClipboardData {
  final int relativeRow;
  final int relativeCol;
  final int? sampleSlot;
  final double volume;
  final double pitch;
  
  const CellClipboardData({
    required this.relativeRow,
    required this.relativeCol,
    required this.sampleSlot,
    required this.volume,
    required this.pitch,
  });
}
