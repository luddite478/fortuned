import 'package:flutter/foundation.dart';

/// State management for sound settings (cell, sample bank, master)
/// Handles volume, pitch, and other audio parameters
class SoundSettingsState extends ChangeNotifier {
  // Cell settings
  int? _selectedCellStep;
  int? _selectedCellCol;
  double _cellVolume = 1.0;
  double _cellPitch = 1.0;
  
  // Sample bank settings
  int? _selectedSampleBank;
  double _sampleBankVolume = 1.0;
  double _sampleBankPitch = 1.0;
  
  // Master settings
  double _masterVolume = 1.0;
  double _masterPitch = 1.0;
  
  // Value notifiers for UI binding
  final ValueNotifier<double> cellVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<double> cellPitchNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<double> sampleBankVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<double> sampleBankPitchNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<double> masterVolumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<double> masterPitchNotifier = ValueNotifier<double>(1.0);
  
  // Getters
  int? get selectedCellStep => _selectedCellStep;
  int? get selectedCellCol => _selectedCellCol;
  double get cellVolume => _cellVolume;
  double get cellPitch => _cellPitch;
  int? get selectedSampleBank => _selectedSampleBank;
  double get sampleBankVolume => _sampleBankVolume;
  double get sampleBankPitch => _sampleBankPitch;
  double get masterVolume => _masterVolume;
  double get masterPitch => _masterPitch;
  
  bool get hasCellSelected => _selectedCellStep != null && _selectedCellCol != null;
  bool get hasSampleBankSelected => _selectedSampleBank != null;
  
  // Cell selection and settings
  void selectCell(int step, int col) {
    _selectedCellStep = step;
    _selectedCellCol = col;
    // Load current cell settings
    _loadCellSettings();
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Selected cell [$step, $col]');
  }
  
  void clearCellSelection() {
    _selectedCellStep = null;
    _selectedCellCol = null;
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Cleared cell selection');
  }
  
  void setCellVolume(double volume) {
    _cellVolume = volume.clamp(0.0, 2.0);
    cellVolumeNotifier.value = _cellVolume;
    notifyListeners();
    debugPrint('🔊 [SOUND_SETTINGS] Set cell volume to $_cellVolume');
  }
  
  void setCellPitch(double pitch) {
    _cellPitch = pitch.clamp(0.25, 4.0);
    cellPitchNotifier.value = _cellPitch;
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Set cell pitch to $_cellPitch');
  }
  
  // Sample bank selection and settings
  void selectSampleBank(int bank) {
    _selectedSampleBank = bank;
    // Load current sample bank settings
    _loadSampleBankSettings();
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Selected sample bank $bank');
  }
  
  void clearSampleBankSelection() {
    _selectedSampleBank = null;
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Cleared sample bank selection');
  }
  
  void setSampleBankVolume(double volume) {
    _sampleBankVolume = volume.clamp(0.0, 2.0);
    sampleBankVolumeNotifier.value = _sampleBankVolume;
    notifyListeners();
    debugPrint('🔊 [SOUND_SETTINGS] Set sample bank volume to $_sampleBankVolume');
  }
  
  void setSampleBankPitch(double pitch) {
    _sampleBankPitch = pitch.clamp(0.25, 4.0);
    sampleBankPitchNotifier.value = _sampleBankPitch;
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Set sample bank pitch to $_sampleBankPitch');
  }
  
  // Master settings
  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 2.0);
    masterVolumeNotifier.value = _masterVolume;
    notifyListeners();
    debugPrint('🔊 [SOUND_SETTINGS] Set master volume to $_masterVolume');
  }
  
  void setMasterPitch(double pitch) {
    _masterPitch = pitch.clamp(0.25, 4.0);
    masterPitchNotifier.value = _masterPitch;
    notifyListeners();
    debugPrint('🎵 [SOUND_SETTINGS] Set master pitch to $_masterPitch');
  }
  
  // Private methods
  void _loadCellSettings() {
    // TODO: Load from native backend when ready
    // For now, use default values
    setCellVolume(1.0);
    setCellPitch(1.0);
  }
  
  void _loadSampleBankSettings() {
    // TODO: Load from native backend when ready
    // For now, use default values
    setSampleBankVolume(1.0);
    setSampleBankPitch(1.0);
  }
  
  @override
  void dispose() {
    cellVolumeNotifier.dispose();
    cellPitchNotifier.dispose();
    sampleBankVolumeNotifier.dispose();
    sampleBankPitchNotifier.dispose();
    masterVolumeNotifier.dispose();
    masterPitchNotifier.dispose();
    super.dispose();
  }
}
