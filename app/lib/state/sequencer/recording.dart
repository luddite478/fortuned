import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../../ffi/playback_bindings.dart';
import '../../conversion_library.dart';
import 'multitask_panel.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// State management for recording functionality
/// Handles audio recording controls and status
class RecordingState extends ChangeNotifier {
  final PlaybackBindings _playback = PlaybackBindings();
  final ConversionLibrary _conversion = ConversionLibrary();
  MultitaskPanelState? _panelState;
  bool _overlayVisible = false;

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;
  final List<String> _localRecordings = [];
  
  // Conversion state
  bool _isConverting = false;
  String? _conversionError;
  String? _convertedMp3Path;
  bool _isPreviewing = false;
  Timer? _previewTimer;
  
  // Value notifiers for UI binding
  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> recordingDurationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> recordingPathNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<List<String>> recordingsNotifier = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<bool> isConvertingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> conversionErrorNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> convertedMp3PathNotifier = ValueNotifier<String?>(null);
  
  // Getters
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  DateTime? get recordingStartTime => _recordingStartTime;
  Duration get recordingDuration => _recordingDuration;
  List<String> get localRecordings => List.unmodifiable(_localRecordings);
  bool get isOverlayVisible => _overlayVisible;
  bool get isConverting => _isConverting;
  String? get conversionError => _conversionError;
  String? get convertedMp3Path => _convertedMp3Path;
  bool get isPreviewing => _isPreviewing;

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
      // Overwrite previous: remove prior WAV/MP3 if any
      await _deleteExistingRecordingFiles();

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
      // Ensure previous timer is stopped and UI shows 00:00 immediately
      _stopDurationTimer();
      recordingDurationNotifier.value = Duration.zero;
      isRecordingNotifier.value = _isRecording;
      recordingPathNotifier.value = _currentRecordingPath;
      notifyListeners();
      clearConversionStatus(); // Clear any previous conversion status
      _startDurationTimer();
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
      // Auto-convert WAV -> MP3 in background
      unawaited(convertToMp3(bitrateKbps: 320));
      // Immediately show overlay (don't wait for conversion)
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

  // Conversion methods
  Future<bool> convertToMp3({int bitrateKbps = 192}) async {
    if (_currentRecordingPath == null) {
      debugPrint('❌ [CONVERSION] No recording to convert');
      return false;
    }

    if (_isConverting) {
      debugPrint('❌ [CONVERSION] Conversion already in progress');
      return false;
    }

    try {
      _isConverting = true;
      _conversionError = null;
      _convertedMp3Path = null;
      
      isConvertingNotifier.value = _isConverting;
      conversionErrorNotifier.value = _conversionError;
      convertedMp3PathNotifier.value = _convertedMp3Path;
      notifyListeners();

      debugPrint('🔄 [CONVERSION] Starting WAV to MP3 conversion...');
      
      // Initialize conversion library if needed
      if (!_conversion.isLoaded) {
        _conversion.initialize();
      }
      
      if (!_conversion.isLoaded) {
        throw Exception('Failed to load conversion library: ${_conversion.loadError}');
      }

      // Initialize the conversion engine
      if (!_conversion.init()) {
        throw Exception('Failed to initialize conversion engine');
      }

      // Generate MP3 output path
      final wavPath = _currentRecordingPath!;
      final mp3Path = wavPath.replaceAll('.wav', '.mp3');
      
      // Check if WAV file exists
      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('WAV file does not exist: $wavPath');
      }

      // Perform conversion in background isolate
      final success = await ConversionLibrary.convertInBackground(wavPath, mp3Path, bitrateKbps);
      
      if (success) {
        _convertedMp3Path = mp3Path;
        convertedMp3PathNotifier.value = _convertedMp3Path;
        debugPrint('✅ [CONVERSION] Successfully converted to MP3: $mp3Path');
        // Delete WAV after successful conversion
        try {
          await File(wavPath).delete();
          debugPrint('🗑️ [CONVERSION] Deleted source WAV: $wavPath');
        } catch (e) {
          debugPrint('⚠️ [CONVERSION] Could not delete WAV: $e');
        }
        notifyListeners();
        return true;
      } else {
        throw Exception('Conversion failed - check logs for details');
      }
      
    } catch (e) {
      _conversionError = e.toString();
      conversionErrorNotifier.value = _conversionError;
      debugPrint('❌ [CONVERSION] Conversion failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isConverting = false;
      isConvertingNotifier.value = _isConverting;
      notifyListeners();
    }
  }

  void clearConversionError() {
    _conversionError = null;
    conversionErrorNotifier.value = _conversionError;
    notifyListeners();
  }

  void clearConversionStatus() {
    _conversionError = null;
    _convertedMp3Path = null;
    conversionErrorNotifier.value = _conversionError;
    convertedMp3PathNotifier.value = _convertedMp3Path;
    notifyListeners();
  }

  // Playback preview controls for the latest recording (prefers MP3 if available)
  Future<void> togglePreview() async {
    if (_isPreviewing) {
      _playback.previewStopSample();
      _isPreviewing = false;
      _previewTimer?.cancel();
      _previewTimer = null;
      notifyListeners();
      return;
    }

    final pathToPlay = _convertedMp3Path ?? _currentRecordingPath;
    if (pathToPlay == null) return;
    try {
      final cPath = pathToPlay.toNativeUtf8();
      try {
        final rc = _playback.previewSamplePath(cPath, 1.0, 1.0);
        if (rc == 0) {
          _isPreviewing = true;
          // Start timer to detect when playback ends (estimate 30 seconds max)
          _previewTimer = Timer(const Duration(seconds: 30), () {
            if (_isPreviewing) {
              _isPreviewing = false;
              _previewTimer?.cancel();
              _previewTimer = null;
              notifyListeners();
            }
          });
          notifyListeners();
        }
      } finally {
        malloc.free(cPath);
      }
    } catch (_) {}
  }

  void stopPreviewIfActive() {
    if (_isPreviewing) {
      _playback.previewStopSample();
      _isPreviewing = false;
      _previewTimer?.cancel();
      _previewTimer = null;
      notifyListeners();
    }
  }

  // Returns MP3 path, converting first if needed
  Future<String?> getShareableMp3Path({int bitrateKbps = 320}) async {
    if (_convertedMp3Path != null) return _convertedMp3Path;
    final ok = await convertToMp3(bitrateKbps: bitrateKbps);
    return ok ? _convertedMp3Path : null;
  }

  // Delete any existing WAV/MP3 files for current recording
  Future<void> _deleteExistingRecordingFiles() async {
    try {
      if (_currentRecordingPath != null) {
        final wav = File(_currentRecordingPath!);
        if (await wav.exists()) {
          await wav.delete();
        }
        final mp3 = File(_currentRecordingPath!.replaceAll('.wav', '.mp3'));
        if (await mp3.exists()) {
          await mp3.delete();
        }
      }
      _convertedMp3Path = null;
      _conversionError = null;
      _isConverting = false;
      isConvertingNotifier.value = _isConverting;
      convertedMp3PathNotifier.value = _convertedMp3Path;
      conversionErrorNotifier.value = _conversionError;
    } catch (_) {}
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
    _previewTimer?.cancel();
    isRecordingNotifier.dispose();
    recordingDurationNotifier.dispose();
    recordingPathNotifier.dispose();
    recordingsNotifier.dispose();
    isConvertingNotifier.dispose();
    conversionErrorNotifier.dispose();
    convertedMp3PathNotifier.dispose();
    super.dispose();
  }
}
