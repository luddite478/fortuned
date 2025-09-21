import 'package:flutter/foundation.dart';

/// Unified UI selection state for sequencer: either sample bank OR table cells
enum UiSelectionKind { none, sampleBank, cells }

class UiSelectionState extends ChangeNotifier {
  UiSelectionKind _kind = UiSelectionKind.none;
  int? _selectedSampleSlot;

  // Notifiers for reactive UI (optional usage)
  final ValueNotifier<UiSelectionKind> kindNotifier = ValueNotifier<UiSelectionKind>(UiSelectionKind.none);
  final ValueNotifier<int?> sampleSlotNotifier = ValueNotifier<int?>(null);

  UiSelectionKind get kind => _kind;
  bool get isSampleBank => _kind == UiSelectionKind.sampleBank;
  bool get isCells => _kind == UiSelectionKind.cells;
  bool get isNone => _kind == UiSelectionKind.none;
  int? get selectedSampleSlot => _selectedSampleSlot;

  /// Mark sample bank selection as active and clear cell mode at UI-level
  void selectSampleBank(int slot) {
    _kind = UiSelectionKind.sampleBank;
    _selectedSampleSlot = slot;
    kindNotifier.value = _kind;
    sampleSlotNotifier.value = slot;
    notifyListeners();
    debugPrint('🎯 [UI_SELECTION] Selected sample bank slot $slot');
  }

  /// Mark cells selection as active
  void selectCells() {
    _kind = UiSelectionKind.cells;
    // keep last sample slot for context but not active
    kindNotifier.value = _kind;
    notifyListeners();
    debugPrint('🎯 [UI_SELECTION] Selected cells');
  }

  /// Clear any selection
  void clear() {
    _kind = UiSelectionKind.none;
    _selectedSampleSlot = null;
    kindNotifier.value = _kind;
    sampleSlotNotifier.value = null;
    notifyListeners();
    debugPrint('🎯 [UI_SELECTION] Cleared selection');
  }

  @override
  void dispose() {
    kindNotifier.dispose();
    sampleSlotNotifier.dispose();
    super.dispose();
  }
}









