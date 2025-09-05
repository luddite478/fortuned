import 'package:flutter/foundation.dart';

/// State management for section settings and controls
/// Handles section overlay visibility and section management
class SectionSettingsState extends ChangeNotifier {
  // Section overlay state
  bool _isSectionControlOpen = false;
  bool _isSectionCreationOpen = false;
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isSectionControlOpenNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isSectionCreationOpenNotifier = ValueNotifier<bool>(false);
  
  // Getters
  bool get isSectionControlOpen => _isSectionControlOpen;
  bool get isSectionCreationOpen => _isSectionCreationOpen;
  
  // Section control overlay methods
  void openSectionControlOverlay() {
    _isSectionControlOpen = true;
    isSectionControlOpenNotifier.value = _isSectionControlOpen;
    notifyListeners();
    debugPrint('🎛️ [SECTION_SETTINGS] Opened section control overlay');
  }
  
  void closeSectionControlOverlay() {
    _isSectionControlOpen = false;
    isSectionControlOpenNotifier.value = _isSectionControlOpen;
    notifyListeners();
    debugPrint('🎛️ [SECTION_SETTINGS] Closed section control overlay');
  }
  
  void toggleSectionControlOverlay() {
    if (_isSectionControlOpen) {
      closeSectionControlOverlay();
    } else {
      openSectionControlOverlay();
    }
  }
  
  // Section creation overlay methods
  void openSectionCreationOverlay() {
    _isSectionCreationOpen = true;
    isSectionCreationOpenNotifier.value = _isSectionCreationOpen;
    notifyListeners();
    debugPrint('🎛️ [SECTION_SETTINGS] Opened section creation overlay');
  }
  
  void closeSectionCreationOverlay() {
    _isSectionCreationOpen = false;
    isSectionCreationOpenNotifier.value = _isSectionCreationOpen;
    notifyListeners();
    debugPrint('🎛️ [SECTION_SETTINGS] Closed section creation overlay');
  }
  
  void toggleSectionCreationOverlay() {
    if (_isSectionCreationOpen) {
      closeSectionCreationOverlay();
    } else {
      openSectionCreationOverlay();
    }
  }
  
  @override
  void dispose() {
    isSectionControlOpenNotifier.dispose();
    isSectionCreationOpenNotifier.dispose();
    super.dispose();
  }
}
