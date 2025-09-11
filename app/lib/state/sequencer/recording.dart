import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../../ffi/playback_bindings.dart';
import 'multitask_panel.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// State management for recording functionality
/// Handles audio recording controls and status
class RecordingState extends ChangeNotifier {
  final PlaybackBindings _playback = PlaybackBindings();
  MultitaskPanelState? _panelState;
  bool _overlayVisible = false;

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
  bool get isOverlayVisible => _overlayVisible;

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
      _currentRecordingPath = outputPath ?? await _generateDateTimeRecordingPath();
      final pathPtr = _currentRecordingPath!.toNativeUtf8();
      final res = _playback.recordingStart(pathPtr.cast<ffi.Char>());
      malloc.free(pathPtr);
      if (res != 0) {
        debugPrint('❌ [RECORDING] Native start failed: $res');
        _currentRecordingPath = null;
        return false;
      }
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;
      _startDurationTimer();
      isRecordingNotifier.value = _isRecording;
      recordingPathNotifier.value = _currentRecordingPath;
      notifyListeners();
      debugPrint('🎙️ [RECORDING] Started → $_currentRecordingPath');
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
      _playback.recordingStop();
      _isRecording = false;
      _stopDurationTimer();
      
      // Update notifiers
      isRecordingNotifier.value = _isRecording;
      if (_currentRecordingPath != null) {
        // Insert newest on top
        _localRecordings.insert(0, _currentRecordingPath!);
        recordingsNotifier.value = List<String>.from(_localRecordings);
      }
      
      notifyListeners();
      debugPrint('⏹️ [RECORDING] Stopped recording. Duration: $formattedDuration');
      // Show overlay over sound grid similar to sample browser
      showOverlay();
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
  
  // Panel wiring (optional)
  void attachPanelState(MultitaskPanelState panel) {
    _panelState = panel;
  }

  void showOverlay() {
    if (!_overlayVisible) {
      _overlayVisible = true;
      notifyListeners();
      debugPrint('🎛️ [RECORDING] Overlay shown');
    }
  }

  void hideOverlay() {
    if (_overlayVisible) {
      _overlayVisible = false;
      notifyListeners();
      debugPrint('🎛️ [RECORDING] Overlay hidden');
    }
  }

  // Recording path helpers (moved from ReliableStorage)
  Future<String> _recordingsDirectory() async {
    final base = await _deriveWritableBasePath();
    final dir = Directory(path.join(base, 'recordings'));
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> _generateDateTimeRecordingPath() async {
    final dir = await _recordingsDirectory();
    final now = DateTime.now();
    final ts = '${now.year.toString().padLeft(4,'0')}'
        '${now.month.toString().padLeft(2,'0')}'
        '${now.day.toString().padLeft(2,'0')}'
        '_'
        '${now.hour.toString().padLeft(2,'0')}'
        '${now.minute.toString().padLeft(2,'0')}'
        '${now.second.toString().padLeft(2,'0')}';
    String p = path.join(dir, '$ts.wav');
    int suffix = 1;
    while (await File(p).exists()) {
      p = path.join(dir, '${ts}_$suffix.wav');
      suffix++;
    }
    return p;
  }
  
  Future<String> _deriveWritableBasePath() async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/niyya_data';
    }
    if (Platform.isIOS) {
      return path.join(Directory.systemTemp.path, 'niyya');
    }
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Documents/niyya';
    }
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Documents\\niyya';
    }
    return path.join(Directory.systemTemp.path, 'niyya');
  }

  // Private methods
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
