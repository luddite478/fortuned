import '../../utils/log.dart';
import 'package:flutter/foundation.dart';

/// Unified UI selection state for sequencer: either sample bank OR table cells OR sections OR section gaps
enum UiSelectionKind { none, sampleBank, cells, section, sectionGap }

class UiSelectionState extends ChangeNotifier {
  UiSelectionKind _kind = UiSelectionKind.none;
  int? _selectedSampleSlot;
  int? _selectedSection;
  int? _selectedSectionGap;

  // Notifiers for reactive UI (optional usage)
  final ValueNotifier<UiSelectionKind> kindNotifier = ValueNotifier<UiSelectionKind>(UiSelectionKind.none);
  final ValueNotifier<int?> sampleSlotNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<int?> sectionNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<int?> sectionGapNotifier = ValueNotifier<int?>(null);

  UiSelectionKind get kind => _kind;
  bool get isSampleBank => _kind == UiSelectionKind.sampleBank;
  bool get isCells => _kind == UiSelectionKind.cells;
  bool get isSection => _kind == UiSelectionKind.section;
  bool get isSectionGap => _kind == UiSelectionKind.sectionGap;
  bool get isNone => _kind == UiSelectionKind.none;
  int? get selectedSampleSlot => _selectedSampleSlot;
  int? get selectedSection => _selectedSection;
  int? get selectedSectionGap => _selectedSectionGap;

  /// Mark sample bank selection as active and clear other selections
  void selectSampleBank(int slot) {
    _kind = UiSelectionKind.sampleBank;
    _selectedSampleSlot = slot;
    _selectedSection = null; // Clear section selection
    _selectedSectionGap = null; // Clear gap selection
    kindNotifier.value = _kind;
    sampleSlotNotifier.value = slot;
    sectionNotifier.value = null;
    sectionGapNotifier.value = null;
    notifyListeners();
    Log.d('🎯 [UI_SELECTION] Selected sample bank slot $slot (cleared other selections)');
  }

  /// Mark cells selection as active (clears all other selections)
  void selectCells() {
    _kind = UiSelectionKind.cells;
    _selectedSampleSlot = null; // Clear sample bank selection
    _selectedSection = null; // Clear section selection
    _selectedSectionGap = null; // Clear gap selection
    kindNotifier.value = _kind;
    sampleSlotNotifier.value = null;
    sectionNotifier.value = null;
    sectionGapNotifier.value = null;
    notifyListeners();
    Log.d('🎯 [UI_SELECTION] Selected cells (cleared other selections)');
  }

  /// Mark section selection as active (clears all other selections)
  void selectSection(int sectionIndex) {
    _kind = UiSelectionKind.section;
    _selectedSection = sectionIndex;
    _selectedSectionGap = null; // Clear gap selection
    _selectedSampleSlot = null; // Clear sample bank selection
    kindNotifier.value = _kind;
    sectionNotifier.value = sectionIndex;
    sectionGapNotifier.value = null;
    sampleSlotNotifier.value = null;
    notifyListeners();
    Log.d('🎯 [UI_SELECTION] Selected section $sectionIndex (cleared other selections)');
  }

  /// Mark section gap selection as active (clears all other selections)
  void selectSectionGap(int gapIndex) {
    _kind = UiSelectionKind.sectionGap;
    _selectedSectionGap = gapIndex;
    _selectedSection = null; // Clear section selection
    _selectedSampleSlot = null; // Clear sample bank selection
    kindNotifier.value = _kind;
    sectionGapNotifier.value = gapIndex;
    sectionNotifier.value = null;
    sampleSlotNotifier.value = null;
    notifyListeners();
    Log.d('🎯 [UI_SELECTION] Selected section gap $gapIndex (cleared other selections)');
  }

  /// Clear any selection
  void clear() {
    _kind = UiSelectionKind.none;
    _selectedSampleSlot = null;
    _selectedSection = null;
    _selectedSectionGap = null;
    kindNotifier.value = _kind;
    sampleSlotNotifier.value = null;
    sectionNotifier.value = null;
    sectionGapNotifier.value = null;
    notifyListeners();
    Log.d('🎯 [UI_SELECTION] Cleared selection');
  }

  @override
  void dispose() {
    kindNotifier.dispose();
    sampleSlotNotifier.dispose();
    sectionNotifier.dispose();
    sectionGapNotifier.dispose();
    super.dispose();
  }
}









