import 'package:flutter/foundation.dart';
import 'dart:async';

/// State management for recording functionality
/// Handles audio recording controls and status
class RecordingState extends ChangeNotifier {
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;
  final List<String> _localRecordings = [];
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> recordingDurationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> recordingPathNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> recordingsNotifier = ValueNotifier<List<String>>(<String>[]);
  
  // Getters
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  DateTime? get recordingStartTime => _recordingStartTime;
  Duration get recordingDuration => _recordingDuration;
  List<String> get localRecordings => List.unmodifiable(_localRecordings);
  
  String get formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  // Recording controls
  Future<bool> startRecording({String? outputPath}) async {
    if (_isRecording) {
      debugPrint('❌ [RECORDING] Already recording');
      return false;
    }
    
    try {
      // Generate path if not provided
      _currentRecordingPath = outputPath ?? _generateRecordingPath();
      
      // TODO: Start native recording when ready
      // For now, simulate recording
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;
      
      // Start duration timer
      _startDurationTimer();
      
      // Update notifiers
      isRecordingNotifier.value = _isRecording;
      recordingPathNotifier.value = _currentRecordingPath;
      
      notifyListeners();
      debugPrint('🎙️ [RECORDING] Started recording to $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('❌ [RECORDING] Failed to start recording: $e');
      return false;
    }
  }
  
  Future<bool> stopRecording() async {
    if (!_isRecording) {
      debugPrint('❌ [RECORDING] Not recording');
      return false;
    }
    
    try {
      // TODO: Stop native recording when ready
      // For now, simulate stopping
      _isRecording = false;
      _stopDurationTimer();
      
      // Update notifiers
      isRecordingNotifier.value = _isRecording;
      if (_currentRecordingPath != null) {
        _localRecordings.add(_currentRecordingPath!);
        recordingsNotifier.value = List<String>.from(_localRecordings);
      }
      
      notifyListeners();
      debugPrint('⏹️ [RECORDING] Stopped recording. Duration: $formattedDuration');
      return true;
    } catch (e) {
      debugPrint('❌ [RECORDING] Failed to stop recording: $e');
      return false;
    }
  }
  
  void clearRecording() {
    if (_isRecording) {
      stopRecording();
    }
    
    _currentRecordingPath = null;
    _recordingStartTime = null;
    _recordingDuration = Duration.zero;
    
    recordingPathNotifier.value = null;
    recordingDurationNotifier.value = Duration.zero;
    notifyListeners();
    debugPrint('🗑️ [RECORDING] Cleared current recording');
  }

  void removeRecording(String filePath) {
    _localRecordings.remove(filePath);
    recordingsNotifier.value = List<String>.from(_localRecordings);
    
    notifyListeners();
    debugPrint('🗑️ [RECORDING] Removed recording: $filePath');
  }
  
  // Private methods
  String _generateRecordingPath() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'recording_$timestamp.wav';
  }
  
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        recordingDurationNotifier.value = _recordingDuration;
        notifyListeners();
      }
    });
  }
  
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }
  
  @override
  void dispose() {
    _stopDurationTimer();
    isRecordingNotifier.dispose();
    recordingDurationNotifier.dispose();
    recordingPathNotifier.dispose();
    recordingsNotifier.dispose();
    super.dispose();
  }
}
