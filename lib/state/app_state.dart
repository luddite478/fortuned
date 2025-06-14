import 'package:flutter/foundation.dart';

// Global application state management
class AppState extends ChangeNotifier {
  // Theme settings
  bool _isDarkMode = true;
  double _masterVolume = 1.0;
  
  // App preferences
  bool _isFirstLaunch = true;
  String? _lastUsedPattern;
  
  // Performance settings
  int _maxConcurrentSounds = 8;
  int _bufferSize = 1024;
  int _sampleRate = 44100;

  // Getters
  bool get isDarkMode => _isDarkMode;
  double get masterVolume => _masterVolume;
  bool get isFirstLaunch => _isFirstLaunch;
  String? get lastUsedPattern => _lastUsedPattern;
  int get maxConcurrentSounds => _maxConcurrentSounds;
  int get bufferSize => _bufferSize;
  int get sampleRate => _sampleRate;

  // Theme methods
  void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  // Audio settings
  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setMaxConcurrentSounds(int maxSounds) {
    _maxConcurrentSounds = maxSounds.clamp(1, 16);
    notifyListeners();
  }

  void setBufferSize(int size) {
    _bufferSize = size;
    notifyListeners();
  }

  void setSampleRate(int rate) {
    _sampleRate = rate;
    notifyListeners();
  }

  // App lifecycle
  void setFirstLaunchComplete() {
    _isFirstLaunch = false;
    notifyListeners();
  }

  void setLastUsedPattern(String? patternId) {
    _lastUsedPattern = patternId;
    notifyListeners();
  }

  // Persistence methods (to be implemented)
  Future<void> loadSettings() async {
    // TODO: Load from SharedPreferences
    notifyListeners();
  }

  Future<void> saveSettings() async {
    // TODO: Save to SharedPreferences
  }
} 