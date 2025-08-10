import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reliable_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../sequencer_library.dart';
import '../services/http_client.dart';
import '../services/audio_conversion_service.dart';
import 'threads_state.dart';
import '../services/threads_service.dart';

// Section playback modes
enum SectionPlaybackMode { loop, song }

// Multitask panel modes
enum MultitaskPanelMode {
  placeholder,
  sampleSelection,
  cellSettings,
  sampleSettings,
  masterSettings,
  stepInsertSettings,
  shareWidget,
  recordingWidget,
}

// Sequencer layout options
enum SequencerLayoutVersion {
  v1,
  v2,
  v3,
}

extension SequencerLayoutVersionExtension on SequencerLayoutVersion {
  String get displayName {
    switch (this) {
      case SequencerLayoutVersion.v1:
        return 'V1';
      case SequencerLayoutVersion.v2:
        return 'V2';
      case SequencerLayoutVersion.v3:
        return 'V3';
    }
  }
  
  String get folderName {
    switch (this) {
      case SequencerLayoutVersion.v1:
        return 'v1';
      case SequencerLayoutVersion.v2:
        return 'v2';
      case SequencerLayoutVersion.v3:
        return 'v3';
    }
  }
}

// Undo-Redo System for Sequencer State
enum UndoRedoActionType {
  gridCellChange,
  sampleLoad,
  sampleRemove,
  volumeChange,
  pitchChange,
  gridAdd,
  gridRemove,
  gridReorder,
  gridResize, // For grid row/column dimension changes
  multipleCellChange, // For batch operations like copy/paste/delete
}

class UndoRedoAction {
  final UndoRedoActionType type;
  final int timestamp;
  final Map<String, dynamic> beforeState;
  final Map<String, dynamic> afterState;
  final String description;

  UndoRedoAction({
    required this.type,
    required this.beforeState,
    required this.afterState,
    required this.description,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch;

  @override
  String toString() => '$description (${type.name})';
}

class UndoRedoManager {
  static const int maxHistorySize = 100;
  final List<UndoRedoAction> _history = [];
  int _currentIndex = -1;

  bool get canUndo => _currentIndex >= 0;
  bool get canRedo => _currentIndex < _history.length - 1;
  int get historySize => _history.length;
  String? get currentActionDescription => canUndo ? _history[_currentIndex].description : null;

  void addAction(UndoRedoAction action) {
    // Remove any actions after current index (when adding new action after undo)
    if (_currentIndex < _history.length - 1) {
      _history.removeRange(_currentIndex + 1, _history.length);
    }

    // Add new action
    _history.add(action);
    _currentIndex = _history.length - 1;

    // Maintain max history size
    while (_history.length > maxHistorySize) {
      _history.removeAt(0);
      _currentIndex--;
    }

    debugPrint('🔄 Added undo action: ${action.description} (${_history.length} actions, index: $_currentIndex)');
  }

  UndoRedoAction? undo() {
    if (!canUndo) return null;
    final action = _history[_currentIndex];
    _currentIndex--;
    debugPrint('↶ Undo: ${action.description} (index now: $_currentIndex)');
    return action;
  }

  UndoRedoAction? redo() {
    if (!canRedo) return null;
    _currentIndex++;
    final action = _history[_currentIndex];
    debugPrint('↷ Redo: ${action.description} (index now: $_currentIndex)');
    return action;
  }

  void clear() {
    _history.clear();
    _currentIndex = -1;
    debugPrint('🗑️ Cleared undo history');
  }

  List<String> getHistoryDescriptions() {
    return _history.map((action) => action.description).toList();
  }
}

// Sample browser item model
class SampleBrowserItem {
  final String name;
  final String path;
  final bool isFolder;
  final int size;

  const SampleBrowserItem({
    required this.name,
    required this.path,
    required this.isFolder,
    this.size = 0,
  });
}

// Sample slot data model
class SampleSlot {
  final int index;
  final String? filePath;
  final String? fileName;
  final bool isLoaded;
  final bool isPlaying;
  final int memoryUsage; // in bytes
  final DateTime? loadedAt;

  const SampleSlot({
    required this.index,
    this.filePath,
    this.fileName,
    this.isLoaded = false,
    this.isPlaying = false,
    this.memoryUsage = 0,
    this.loadedAt,
  });

  SampleSlot copyWith({
    int? index,
    String? filePath,
    String? fileName,
    bool? isLoaded,
    bool? isPlaying,
    int? memoryUsage,
    DateTime? loadedAt,
  }) {
    return SampleSlot(
      index: index ?? this.index,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      isLoaded: isLoaded ?? this.isLoaded,
      isPlaying: isPlaying ?? this.isPlaying,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  bool get isEmpty => filePath == null;
  bool get hasFile => filePath != null;
}

// 🎯 PERFORMANCE: Add change type enum for smart notifications
enum SequencerChangeType {
  volume,
  pitch,
  grid,
  sampleBank,
  playback,
  ui,
  selection,
  all,
}

// Sequencer state management - Complete sequencer functionality
class SequencerState extends ChangeNotifier {
  static const int maxSlots = 16;
  
  // BPM range constants
  static const int minBpm = 1;
  static const int maxBpm = 320;
  static const int defaultBpm = 120;
  
  late final SequencerLibrary _sequencerLibrary;
  late final int _slotCount;
  
  // Max sequencer steps from environment variable (read once during initialization)
  late final int _maxSequencerSteps;

  // 🎯 PERFORMANCE: ValueNotifiers for high-frequency updates
  final Map<int, ValueNotifier<double>> _sampleVolumeNotifiers = {};
  final Map<int, ValueNotifier<double>> _samplePitchNotifiers = {};
  final Map<int, ValueNotifier<double>> _cellVolumeNotifiers = {};
  final Map<int, ValueNotifier<double>> _cellPitchNotifiers = {};
  final ValueNotifier<int> _currentStepNotifier = ValueNotifier(-1);
  final ValueNotifier<bool> _isSequencerPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _bpmNotifier = ValueNotifier(defaultBpm);
  
  // 🎯 PERFORMANCE: Batched notification system
  Timer? _notificationBatchTimer;
  Set<SequencerChangeType> _pendingChanges = {};
  static const Duration _batchDelay = Duration(milliseconds: 16); // ~60fps

  // Audio state
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  // UI state
  int _activeBank = 0;
  int? _activePad;
  int? _selectedSampleSlot; // Track which sample is selected for placement
  
  // Layout settings
  SequencerLayoutVersion _selectedLayout = SequencerLayoutVersion.v2;
  
  // Grid configuration
  int _gridColumns = 4;
  int _gridRows = 16; // Will be validated against _maxSequencerSteps in init
  
  // Section chain configuration
  int _numSections = 1; // Number of sections in the chain
  int _currentSectionIndex = 0; // Currently active section (0-based)
  List<int> _sectionLoopCounts = [1]; // Loop count for each section
  SectionPlaybackMode _sectionPlaybackMode = SectionPlaybackMode.loop; // Current playback mode
  bool _isSectionControlOverlayOpen = false; // Section control overlay state
  bool _isSectionCreationOverlayOpen = false; // Section creation overlay state
  
  // Section-specific storage (persistence) - as per documentation
  Map<int, List<List<int?>>> _sectionGridData = {}; // Maps section index to grid data
  
  // Grid state - tracks which sample slot is assigned to each grid cell for each sound grid
  late List<List<int?>> _soundGridSamples; // Each sound grid has its own grid samples
  
  // Grid selection state
  Set<int> _selectedGridCells = {};
  bool _isSelecting = false;
  bool _isInSelectionMode = false; // New: Track if we're in selection mode
  bool _isDragging = false; // New: Track if user is currently dragging
  int? _selectionStartCell;
  int? _currentSelectionCell;
  
  // Sequencer state
  int _bpm = defaultBpm;
  int _currentStep = -1; // -1 means not playing, 0-(maxGridRows-1) for current step
  bool _isSequencerPlaying = false;
  Timer? _sequencerTimer;
  
  // Recording state
  bool _isRecording = false;
  String? _currentRecordingPath;
  String? _lastRecordingPath;
  DateTime? _lastRecordingTime;
  
  // MP3 conversion state
  bool _isConverting = false;
  double _conversionProgress = 0.0;
  String? _lastMp3Path;
  String? _conversionError;
  
  // Track which samples are currently playing in each column
  late List<int?> _columnPlayingSample;

  // Copy/Paste clipboard
  Map<int, int?> _clipboard = {}; // Maps relative position to sample slot
  bool _hasClipboardData = false;

  // Grid colors for each bank
  final List<Color> _bankColors = [
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.indigo,
    Colors.teal,
    Colors.cyan,
    Colors.amber,
    Colors.lime,
    Colors.deepOrange,
    Colors.blueGrey,
    Colors.brown,
    Colors.lightGreen,
    Colors.deepPurple,
  ];

  // Track double-tap timing
  DateTime? _lastTapTime;
  int? _lastTappedCell;
  static const Duration _doubleTapThreshold = Duration(milliseconds: 300);

  // Sound Grid stack state
  int _currentSoundGridIndex = 0;
  List<int> _soundGridOrder = []; // Order of sound grids from back to front (initialized dynamically)

  // Multitask panel state
  MultitaskPanelMode _currentPanelMode = MultitaskPanelMode.placeholder;
  
  // Sample selection state
  int? _sampleSelectionSlot;
  List<String> _currentSamplePath = [];
  List<SampleBrowserItem> _currentSampleItems = [];
  
  // Body element sample browser state (separate from multitask panel)
  bool _isBodyElementSampleBrowserOpen = false;
  int? _bodyElementSampleBrowserSlot;

  // Share widget state
  List<String> _localRecordings = []; // List of local recording file paths

  // Cell settings state
  int? _selectedCellForSettings;
  
  // Step insert feature state
  bool _isStepInsertMode = false; // Toggle for step insert mode
  int _stepInsertSize = 2; // Number of steps to jump (1-maxGridRows)
  
  // Volume control state
  late List<double> _sampleVolumes; // Global sample volumes (affects all instances)
  late Map<int, double> _cellVolumes; // Individual cell volume overrides
  late List<double> _samplePitches; // Global sample pitches (affects all instances)
  late Map<int, double> _cellPitches; // Individual cell pitch overrides

  // Slider interaction tracking for overlay display
  bool _isSliderInteracting = false;
  String _currentSliderSetting = '';
  String _currentSliderValue = '';
  final ValueNotifier<bool> _sliderInteractionNotifier = ValueNotifier(false);
  final ValueNotifier<String> _sliderSettingNotifier = ValueNotifier('');
  final ValueNotifier<String> _sliderValueNotifier = ValueNotifier('');

  // Grid labeling system
  List<String> _soundGridLabels = [];

  // Thread integration
  ThreadsState? _threadsState;

  // Collaboration state
  bool _isCollaborating = false;
  Thread? _sourceThread;

  // Collaboration getters
  bool get isCollaborating => _isCollaborating;
  Thread? get sourceThread => _sourceThread;

  // Slider interaction getters
  bool get isSliderInteracting => _isSliderInteracting;
  String get currentSliderSetting => _currentSliderSetting;
  String get currentSliderValue => _currentSliderValue;
  ValueNotifier<bool> get sliderInteractionNotifier => _sliderInteractionNotifier;
  ValueNotifier<String> get sliderSettingNotifier => _sliderSettingNotifier;
  ValueNotifier<String> get sliderValueNotifier => _sliderValueNotifier;

  // Slider interaction methods
  void startSliderInteraction(String setting, String value) {
    _isSliderInteracting = true;
    _currentSliderSetting = setting;
    _currentSliderValue = value;
    _sliderInteractionNotifier.value = true;
    _sliderSettingNotifier.value = setting;
    _sliderValueNotifier.value = value;
  }

  void updateSliderValue(String value) {
    _currentSliderValue = value;
    _sliderValueNotifier.value = value;
  }

  void stopSliderInteraction() {
    _isSliderInteracting = false;
    _currentSliderSetting = '';
    _currentSliderValue = '';
    _sliderInteractionNotifier.value = false;
    _sliderSettingNotifier.value = '';
    _sliderValueNotifier.value = '';
  }

  // Undo-Redo getters
  bool get canUndo => _undoRedoManager.canUndo;
  bool get canRedo => _undoRedoManager.canRedo;
  int get undoHistorySize => _undoRedoManager.historySize;
  String? get currentUndoDescription => _undoRedoManager.currentActionDescription;

  // Undo-Redo Core Methods
  void undo() {
    if (!canUndo || _isPerformingUndoRedo) return;
    
    // Flush any pending debounced actions before undoing
    _flushPendingUndoAction();
    
    _isPerformingUndoRedo = true;
    final action = _undoRedoManager.undo();
    if (action != null) {
      _applyUndoRedoState(action.beforeState, isUndo: true);
      notifyListeners();
    }
    _isPerformingUndoRedo = false;
  }

  void redo() {
    if (!canRedo || _isPerformingUndoRedo) return;
    
    // Flush any pending debounced actions before redoing
    _flushPendingUndoAction();
    
    _isPerformingUndoRedo = true;
    final action = _undoRedoManager.redo();
    if (action != null) {
      _applyUndoRedoState(action.afterState, isUndo: false);
      notifyListeners();
    }
    _isPerformingUndoRedo = false;
  }

  // Helper method to flush any pending debounced undo action immediately
  void _flushPendingUndoAction() {
    if (_pendingUndoBeforeState != null) {
      _undoDebounceTimer?.cancel();
      
      final action = UndoRedoAction(
        type: _pendingUndoType!,
        beforeState: _pendingUndoBeforeState!,
        afterState: _captureCurrentState(),
        description: _pendingUndoDescription!,
      );

      _undoRedoManager.addAction(action);

      // Clear pending state
      _pendingUndoBeforeState = null;
      _pendingUndoDescription = null;
      _pendingUndoType = null;
    }
  }

  void clearUndoHistory() {
    _flushPendingUndoAction();
    _undoRedoManager.clear();
    notifyListeners();
  }

  // Helper method to capture current state for undo-redo
  Map<String, dynamic> _captureCurrentState() {
    return {
      'soundGridSamples': _soundGridSamples.map((grid) => List<int?>.from(grid)).toList(),
      'filePaths': List<String?>.from(_filePaths),
      'fileNames': List<String?>.from(_fileNames),
      'slotLoaded': List<bool>.from(_slotLoaded),
      'sampleVolumes': List<double>.from(_sampleVolumes),
      'samplePitches': List<double>.from(_samplePitches),
      'cellVolumes': Map<int, double>.from(_cellVolumes),
      'cellPitches': Map<int, double>.from(_cellPitches),
      'soundGridLabels': List<String>.from(_soundGridLabels),
      'soundGridOrder': List<int>.from(_soundGridOrder),
      'bpm': _bpm,
    };
  }

  // Helper method to apply state from undo-redo
  void _applyUndoRedoState(Map<String, dynamic> state, {required bool isUndo}) {
    // Apply sound grid samples
    if (state.containsKey('soundGridSamples')) {
      final gridSamples = (state['soundGridSamples'] as List<dynamic>)
          .map((grid) => (grid as List<dynamic>).cast<int?>())
          .toList();
      _soundGridSamples.clear();
      _soundGridSamples.addAll(gridSamples);
    }

    // Apply sample data
    if (state.containsKey('filePaths')) {
      _filePaths = (state['filePaths'] as List<dynamic>).cast<String?>();
    }
    if (state.containsKey('fileNames')) {
      _fileNames = (state['fileNames'] as List<dynamic>).cast<String?>();
    }
    if (state.containsKey('slotLoaded')) {
      _slotLoaded = (state['slotLoaded'] as List<dynamic>).cast<bool>();
    }

    // Apply volume and pitch settings
    if (state.containsKey('sampleVolumes')) {
      _sampleVolumes = (state['sampleVolumes'] as List<dynamic>).cast<double>();
    }
    if (state.containsKey('samplePitches')) {
      _samplePitches = (state['samplePitches'] as List<dynamic>).cast<double>();
    }
    if (state.containsKey('cellVolumes')) {
      _cellVolumes = Map<int, double>.from(state['cellVolumes'] as Map);
    }
    if (state.containsKey('cellPitches')) {
      _cellPitches = Map<int, double>.from(state['cellPitches'] as Map);
    }

    // Apply grid metadata
    if (state.containsKey('soundGridLabels')) {
      _soundGridLabels = (state['soundGridLabels'] as List<dynamic>).cast<String>();
    }
    if (state.containsKey('soundGridOrder')) {
      _soundGridOrder = (state['soundGridOrder'] as List<dynamic>).cast<int>();
    }

    // Apply BPM
    if (state.containsKey('bpm')) {
      _bpm = state['bpm'] as int;
    }

    // Sync changes to native sequencer
    syncFlutterSequencerGridToNativeSequencerGrid();

    debugPrint('🔄 Applied ${isUndo ? 'undo' : 'redo'} state successfully');
  }

  // Helper method to record an undo action
  void _recordUndoAction({
    required UndoRedoActionType type,
    required String description,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
  }) {
    if (_isPerformingUndoRedo) return; // Don't record actions during undo/redo

    final before = beforeState ?? _captureCurrentState();
    final after = afterState ?? _captureCurrentState();

    final action = UndoRedoAction(
      type: type,
      beforeState: before,
      afterState: after,
      description: description,
    );

    _undoRedoManager.addAction(action);
  }

  // Helper method to record undo action with debouncing for rapid changes (like sliders)
  void _recordDebouncedUndoAction({
    required UndoRedoActionType type,
    required String description,
    Map<String, dynamic>? beforeState,
  }) {
    if (_isPerformingUndoRedo) return; // Don't record actions during undo/redo

    // If this is the first change in a sequence, capture the initial state
    if (_pendingUndoBeforeState == null) {
      _pendingUndoBeforeState = beforeState ?? _captureCurrentState();
      _pendingUndoType = type;
      _pendingUndoDescription = description;
    } else {
      // Update the description to reflect the latest change
      _pendingUndoDescription = description;
    }

    // Cancel any existing timer
    _undoDebounceTimer?.cancel();

    // Start new timer - will trigger after user stops making changes
    _undoDebounceTimer = Timer(_undoDebounceDelay, () {
      if (_pendingUndoBeforeState != null) {
        final action = UndoRedoAction(
          type: _pendingUndoType!,
          beforeState: _pendingUndoBeforeState!,
          afterState: _captureCurrentState(),
          description: _pendingUndoDescription!,
        );

        _undoRedoManager.addAction(action);

        // Clear pending state
        _pendingUndoBeforeState = null;
        _pendingUndoDescription = null;
        _pendingUndoType = null;
      }
    });
  }

  // Helper method to get a human-readable cell position string
  String _getCellPositionString(int cellIndex) {
    final row = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    return 'R${row + 1}C${col + 1}'; // 1-indexed for user display
  }
  
  // Testing/Debug getters and setters
  bool get clearSavedDataOnInit => _clearSavedDataOnInit;
  void setClearSavedDataOnInit(bool clear) {
    _clearSavedDataOnInit = clear;
    debugPrint('🧪 Clear saved data on init set to: $clear');
  }

  // Autosave functionality
  bool _autosaveEnabled = false;
  Timer? _autosaveTimer;
  Timer? _debounceTimer;
  static const String _autosaveKey = 'sequencer_autosave';
  static const Duration _autosaveInterval = Duration(seconds: 30);
  static const Duration _debounceDelay = Duration(seconds: 3);
  DateTime? _lastSaveTime;
  bool _hasUnsavedChanges = false;
  bool _isCurrentlySaving = false;
  
  // Testing/Debug functionality
  bool _clearSavedDataOnInit = true; // Set to true to start fresh, ignoring autosaved data

  // Undo-Redo Manager
  final UndoRedoManager _undoRedoManager = UndoRedoManager();
  bool _isPerformingUndoRedo = false; // Flag to prevent recording undo actions during undo/redo

  // Debounced undo recording for rapid changes (like sliders)
  Timer? _undoDebounceTimer;
  Map<String, dynamic>? _pendingUndoBeforeState;
  String? _pendingUndoDescription;
  UndoRedoActionType? _pendingUndoType;
  
  // Preview timer to automatically stop preview after user stops adjusting
  Timer? _previewTimer;
  
  // Debounced native calls for performance (prevent rapid native calls)
  Timer? _nativePitchDebounceTimer;
  Timer? _nativeVolumeDebounceTimer;
  Map<String, double> _pendingNativePitchCalls = {}; // key: "cell_$index" or "sample_$index"
  Map<String, double> _pendingNativeVolumeCalls = {}; // key: "cell_$index" or "sample_$index"
  
  static const Duration _undoDebounceDelay = Duration(milliseconds: 800); // 800ms delay
  static const Duration _previewAutoStopDelay = Duration(milliseconds: 1500); // 1.5s preview auto-stop
  static const Duration _nativeCallDebounceDelay = Duration(milliseconds: 50); // 50ms delay for native calls

  // 🎯 PERFORMANCE: ValueNotifier getters for high-frequency updates
  ValueNotifier<double> getSampleVolumeNotifier(int sampleIndex) {
    return _sampleVolumeNotifiers.putIfAbsent(sampleIndex, () {
      final initialValue = sampleIndex < _sampleVolumes.length ? _sampleVolumes[sampleIndex] : 1.0;
      return ValueNotifier(initialValue);
    });
  }
  
  ValueNotifier<double> getSamplePitchNotifier(int sampleIndex) {
    return _samplePitchNotifiers.putIfAbsent(sampleIndex, () {
      final initialValue = sampleIndex < _samplePitches.length ? _samplePitches[sampleIndex] : 1.0;
      return ValueNotifier(initialValue);
    });
  }
  
  ValueNotifier<double> getCellVolumeNotifier(int cellIndex) {
    return _cellVolumeNotifiers.putIfAbsent(cellIndex, () {
      return ValueNotifier(getCellVolume(cellIndex));
    });
  }
  
  ValueNotifier<double> getCellPitchNotifier(int cellIndex) {
    return _cellPitchNotifiers.putIfAbsent(cellIndex, () {
      return ValueNotifier(getCellPitch(cellIndex));
    });
  }
  
  ValueNotifier<int> get currentStepNotifier => _currentStepNotifier;
  ValueNotifier<bool> get isSequencerPlayingNotifier => _isSequencerPlayingNotifier;
  ValueNotifier<int> get bpmNotifier => _bpmNotifier;

  // 🎯 PERFORMANCE: Selector-friendly getters (prevent unnecessary rebuilds)
  List<int?> get currentGridSamplesForSelector => 
    _soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length 
      ? List.unmodifiable(_soundGridSamples[_currentSoundGridIndex]) 
      : List.filled(_gridColumns * _gridRows, null);
      
  List<String?> get fileNamesForSelector => List.unmodifiable(_fileNames);
  List<bool> get slotLoadedForSelector => List.unmodifiable(_slotLoaded);
  Set<int> get selectedGridCellsForSelector => Set.unmodifiable(_selectedGridCells);
  MultitaskPanelMode get currentPanelModeForSelector => _currentPanelMode;
  
  // 🎯 PERFORMANCE: Smart notification system
  void _scheduleNotification(SequencerChangeType changeType) {
    _pendingChanges.add(changeType);
    
    _notificationBatchTimer?.cancel();
    _notificationBatchTimer = Timer(_batchDelay, () {
      if (_pendingChanges.isNotEmpty) {
        // Only notify if we have actual changes
        notifyListeners();
        _pendingChanges.clear();
      }
    });
  }
  
  void _notifyImmediately(SequencerChangeType changeType) {
    _notificationBatchTimer?.cancel();
    _pendingChanges.clear();
    notifyListeners();
  }

  // Initialize sequencer
  SequencerState() {
    _sequencerLibrary = SequencerLibrary.instance;
    
    // Initialize max sequencer steps from environment variable
    final envValue = dotenv.env['SEQUENCER_MAX_STEPS'];
    _maxSequencerSteps = int.parse(envValue!); // Fail if not set or invalid
    
    // Validate grid rows against max steps
    if (_gridRows > _maxSequencerSteps) {
      _gridRows = _maxSequencerSteps;
    }
    
    _initializeAudio();

    _slotCount = _sequencerLibrary.slotCount;
    _filePaths = List.filled(_slotCount, null);
    _fileNames = List.filled(_slotCount, null);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
    _soundGridSamples = []; // Will be initialized when sound grids are created
    _columnPlayingSample = List.filled(_gridColumns, null);
    
    // Initialize volume control arrays
    _sampleVolumes = List.filled(_slotCount, 1.0); // Default to 100% volume
    _cellVolumes = {}; // Empty map - cells use sample volume by default
    
    // Initialize pitch control arrays
    _samplePitches = List.filled(_slotCount, 1.0); // Default to normal pitch
    _cellPitches = {}; // Empty map - cells use sample pitch by default
    
    // Start autosave timer
    _startAutosave();
    
    // Load saved state on initialization (unless disabled for testing)
    if (!_clearSavedDataOnInit) {
      _loadAutosavedState();
    } else {
      debugPrint('🧪 Skipping autosaved state loading (clearSavedDataOnInit = true)');
      // Optionally clear any existing saved data
      clearAutosavedState();
    }
    
    // Load saved recordings asynchronously (don't block constructor)
    _loadSavedRecordings().catchError((e) {
      debugPrint('❌ Failed to load saved recordings during initialization: $e');
    });
  }

  // Set threads state for collaboration tracking
  void setThreadsState(ThreadsState threadsState) {
    _threadsState = threadsState;
  }

  // Create a snapshot of current sequencer state for threads (matches database structure)
  SequencerSnapshot createSnapshot({String? name, String? comment}) {
    final now = DateTime.now();
    final snapshotId = 'snapshot_${now.millisecondsSinceEpoch}';
    
    // Convert current sequencer state to database-compatible structure
    final layers = <SequencerLayer>[];
    
    // Create layers from current sound grids
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final gridSamples = _soundGridSamples[gridIndex];
      
      // Group cells into rows (assuming _gridColumns cells per row)
      final rows = <SequencerRow>[];
      for (int rowIndex = 0; rowIndex < _gridRows; rowIndex++) {
        final cells = <SequencerCell>[];
        for (int colIndex = 0; colIndex < _gridColumns; colIndex++) {
          final cellIndex = rowIndex * _gridColumns + colIndex;
          final sampleSlot = cellIndex < gridSamples.length ? gridSamples[cellIndex] : null;
          
          cells.add(SequencerCell(
            sample: sampleSlot != null ? CellSample(
              sampleId: 'slot_$sampleSlot',
              sampleName: sampleSlot < _fileNames.length 
                ? _fileNames[sampleSlot] ?? 'Sample $sampleSlot'
                : 'Sample $sampleSlot',
            ) : null,
          ));
        }
        rows.add(SequencerRow(cells: cells));
      }
      
      layers.add(SequencerLayer(
        id: 'layer_${gridIndex.toString().padLeft(3, '0')}',
        index: gridIndex,
        rows: rows,
      ));
    }
    
    // Create sample info from loaded samples
    final samples = <SampleInfo>[];
    for (int i = 0; i < _filePaths.length; i++) {
      if (_filePaths[i] != null) {
        samples.add(SampleInfo(
          id: 'slot_$i',
          name: _fileNames[i] ?? 'Sample $i',
          url: _filePaths[i]!,
          isPublic: true, // Default to public for now
        ));
      }
    }
    
    // Create the section with metadata
    final section = SequencerSection(
      layers: layers,
      metadata: SectionMetadata(
        user: _threadsState?.currentUserId ?? 'unknown',
        createdAt: now,
        bpm: _bpm,
        key: 'C Major', // Default for now, could be enhanced
        timeSignature: '4/4', // Default for now
      ),
    );
    
    // Create the audio source
    final audioSource = AudioSource(
      sections: [section],
      samples: samples,
    );
    
        // Create the full audio structure
    final audio = ProjectAudio(
      format: 'mp3',
      duration: 0.0, // Could calculate based on BPM and pattern length
      sampleRate: 48000,
      channels: 2,
      url: '', // Empty URL since this is a live snapshot
      renders: [], // No renders yet
      sources: [audioSource],
    );

    return SequencerSnapshot(
      id: snapshotId,
      name: name ?? comment ?? 'Sequencer State ${now.toString().substring(11, 19)}',
      createdAt: now,
      version: '1.0', // Default version
      audio: audio,
    );
  }

  // Apply a snapshot to current sequencer state (for receiving thread messages)
  void applySnapshot(SequencerSnapshot snapshot) {
    try {
      final audio = snapshot.audio;
      if (audio.sources.isEmpty) return;
      
      final source = audio.sources.first;
          if (source.sections.isEmpty) return;
    
        final section = source.sections.first;
    
    // Apply BPM from metadata
    _bpm = section.metadata.bpm;
      
      // Clear current state
      _soundGridSamples.clear();
      
      // Rebuild sample mappings from snapshot samples
      final sampleIdToSlot = <String, int>{};
      for (int i = 0; i < source.samples.length; i++) {
        final sample = source.samples[i];
        if (i < _filePaths.length) {
          _filePaths[i] = sample.url;
          _fileNames[i] = sample.name;
          _slotLoaded[i] = true;
          sampleIdToSlot[sample.id] = i;
        }
      }
      
      // Apply layers as sound grids
      for (int layerIndex = 0; layerIndex < section.layers.length; layerIndex++) {
        final layer = section.layers[layerIndex];
        final gridSamples = <int?>[];
        
        // Convert rows back to grid format
        for (final row in layer.rows) {
          for (final cell in row.cells) {
            if (cell.sample?.hasSample == true && sampleIdToSlot.containsKey(cell.sample!.sampleId)) {
              gridSamples.add(sampleIdToSlot[cell.sample!.sampleId]);
            } else {
              gridSamples.add(null);
            }
          }
        }
        
        // Ensure grid has the right size
        while (gridSamples.length < _gridColumns * _gridRows) {
          gridSamples.add(null);
        }
        
        if (layerIndex < _soundGridSamples.length) {
          _soundGridSamples[layerIndex] = gridSamples;
        } else {
          _soundGridSamples.add(gridSamples);
        }
      }
      
      // Update grid order if needed
      while (_soundGridOrder.length < _soundGridSamples.length) {
        _soundGridOrder.add(_soundGridOrder.length);
      }
      
      // Reload samples that are marked as loaded
      for (int i = 0; i < _slotLoaded.length; i++) {
        if (_slotLoaded[i] && _filePaths[i] != null) {
          loadSlot(i);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error applying sequencer snapshot: $e');
    }
  }

  // Getters
  List<String?> get filePaths => List.unmodifiable(_filePaths);
  List<String?> get fileNames => List.unmodifiable(_fileNames);
  List<bool> get slotLoaded => List.unmodifiable(_slotLoaded);
  List<bool> get slotPlaying => List.unmodifiable(_slotPlaying);
  int get activeBank => _activeBank;
  int? get activePad => _activePad;
  int? get selectedSampleSlot => _selectedSampleSlot;
  int get gridColumns => _gridColumns;
  int get gridRows => _gridRows;
  int get numSections => _numSections;
  List<int?> get gridSamples => _soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length 
      ? List.unmodifiable(_soundGridSamples[_currentSoundGridIndex]) 
      : List.filled(_gridColumns * _gridRows, null);
  Set<int> get selectedGridCells => Set.unmodifiable(_selectedGridCells);
  bool get isSelecting => _isSelecting;
  bool get isInSelectionMode => _isInSelectionMode;
  int get bpm => _bpm;
  int get currentStep => _currentStep;
  bool get isSequencerPlaying => _isSequencerPlaying;
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  String? get lastRecordingPath => _lastRecordingPath;
  DateTime? get lastRecordingTime => _lastRecordingTime;
  String get formattedRecordingDuration => _sequencerLibrary.formattedOutputRecordingDuration;
  bool get isConverting => _isConverting;
  double get conversionProgress => _conversionProgress;
  String? get lastMp3Path => _lastMp3Path;
  String? get conversionError => _conversionError;
  List<Color> get bankColors => List.unmodifiable(_bankColors);
  bool get hasClipboardData => _hasClipboardData;
  int get slotCount => _slotCount;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool get isCurrentlySaving => _isCurrentlySaving;
  bool get autosaveEnabled => _autosaveEnabled;
  MultitaskPanelMode get currentPanelMode => _currentPanelMode;
  bool get isSelectingSample => _currentPanelMode == MultitaskPanelMode.sampleSelection;
  bool get isShowingShareWidget => _currentPanelMode == MultitaskPanelMode.shareWidget;
  bool get isShowingSampleSettings => _currentPanelMode == MultitaskPanelMode.sampleSettings;
  bool get isShowingCellSettings => _currentPanelMode == MultitaskPanelMode.cellSettings;
  SequencerLayoutVersion get selectedLayout => _selectedLayout;
  int? get selectedCellForSettings => _selectedCellForSettings;
  bool get showMasterSettings => _currentPanelMode == MultitaskPanelMode.masterSettings;
  bool get isStepInsertMode => _isStepInsertMode;
  int get stepInsertSize => _stepInsertSize;
  bool get isShowingStepInsertSettings => _currentPanelMode == MultitaskPanelMode.stepInsertSettings;
  List<String> get localRecordings => List.unmodifiable(_localRecordings);
  int? get sampleSelectionSlot => _sampleSelectionSlot;
  List<String> get currentSamplePath => List.unmodifiable(_currentSamplePath);
  List<SampleBrowserItem> get currentSampleItems => List.unmodifiable(_currentSampleItems);
  
  // Body element sample browser getters
  bool get isBodyElementSampleBrowserOpen => _isBodyElementSampleBrowserOpen;
  int? get bodyElementSampleBrowserSlot => _bodyElementSampleBrowserSlot;
  int get currentSoundGridIndex => _currentSoundGridIndex;
  List<int> get soundGridOrder => List.unmodifiable(_soundGridOrder);
  int get columnsPerGrid => _gridColumns;
  int get numSoundGrids => _soundGridSamples.length;
  
  List<SampleSlot> get loadedSlots {
    List<SampleSlot> slots = [];
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        slots.add(SampleSlot(
          index: i,
          filePath: _filePaths[i],
          fileName: _fileNames[i],
          isLoaded: _slotLoaded[i],
          isPlaying: _slotPlaying[i],
        ));
      }
    }
    return slots;
  }

  Future<void> _initializeAudio() async {
    bool success = _sequencerLibrary.initialize();
    if (!success) {
      debugPrint('Failed to initialize audio engine');
    }
  }

  Future<String> _copyAssetToTemp(String assetPath, String fileName) async {
    try {
      // Load the asset data
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Use system temp directory
      final Directory tempDir = Directory.systemTemp;
      
      // Create a unique temporary file name to avoid conflicts
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String tempFileName = '${timestamp}_$fileName';
      final String tempPath = path.join(tempDir.path, tempFileName);
      final File tempFile = File(tempPath);
      
      // Write the asset data to the temporary file
      await tempFile.writeAsBytes(bytes);
      
      print('📁 Created temp file: $tempPath');
      return tempPath;
    } catch (e) {
      throw Exception('Failed to copy asset to temp file: $e');
    }
  }

  // Panel mode setters - 🎯 PERFORMANCE OPTIMIZED
  void setPanelMode(MultitaskPanelMode mode) {
    // 🎯 PERFORMANCE: Only update if mode actually changed
    if (_currentPanelMode != mode) {
      _currentPanelMode = mode;
      // UI changes need immediate notification for responsiveness
      _notifyImmediately(SequencerChangeType.ui);
    }
  }
  
  // Layout selection setter
  void setSelectedLayout(SequencerLayoutVersion layout) {
    if (_selectedLayout != layout) {
      _selectedLayout = layout;
      // Trigger autosave when layout changes
      _triggerAutosave();
      // UI changes need immediate notification
      _notifyImmediately(SequencerChangeType.ui);
      debugPrint('🎨 Layout changed to ${layout.displayName}');
    }
  }
  
  void setShowSampleSettings(bool show) {
    _currentPanelMode = show ? MultitaskPanelMode.sampleSettings : MultitaskPanelMode.placeholder;
    notifyListeners();
  }
  
  void setShowCellSettings(bool show) {
    _currentPanelMode = show ? MultitaskPanelMode.cellSettings : MultitaskPanelMode.placeholder;
    notifyListeners();
  }
  
  void setShowMasterSettings(bool show) {
    _currentPanelMode = show ? MultitaskPanelMode.masterSettings : MultitaskPanelMode.placeholder;
    notifyListeners();
  }
  
  void setShowStepInsertSettings(bool show) {
    _currentPanelMode = show ? MultitaskPanelMode.stepInsertSettings : MultitaskPanelMode.placeholder;
    notifyListeners();
  }
  
  void setShowShareWidget(bool show) {
    _currentPanelMode = show ? MultitaskPanelMode.shareWidget : MultitaskPanelMode.placeholder;
    notifyListeners();
  }

  Future<void> pickFileForSlot(int slot, BuildContext context) async {
    _currentPanelMode = MultitaskPanelMode.sampleSelection;
    _sampleSelectionSlot = slot;
    _currentSamplePath.clear();
    await _loadSamples();
    notifyListeners();
  }

  void cancelSampleSelection() {
    _currentPanelMode = MultitaskPanelMode.placeholder;
    _sampleSelectionSlot = null;
    _currentSamplePath.clear();
    _currentSampleItems.clear();
    notifyListeners();
  }

  /// Initialize sample browser for body element usage (independent of multitask panel)
  Future<void> initializeSampleBrowserForBodyElement() async {
    _currentSamplePath.clear();
    await _loadSamples();
    notifyListeners();
  }
  
  /// Copy asset to temp for body element usage (wrapper method)
  Future<String> copyAssetToTempForBodyElement(String assetPath, String fileName) async {
    return await _copyAssetToTemp(assetPath, fileName);
  }
  
  /// Load sample to slot from body element (bypasses multitask panel system)
  Future<void> loadSampleToSlotFromBodyElement(int slot, String filePath, String fileName) async {
    // Flush any pending debounced actions before sample loading
    _flushPendingUndoAction();
    
    // Capture state before loading sample
    final beforeState = _captureCurrentState();
    
    _filePaths[slot] = filePath;
    _fileNames[slot] = fileName;
    _slotLoaded[slot] = false;
    
    // Always load sample to memory immediately
    loadSlot(slot);
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.sampleLoad,
      description: 'Load Sample ${String.fromCharCode(65 + slot)}: $fileName',
      beforeState: beforeState,
    );
    
    notifyListeners();
  }
  
  /// Open body element sample browser for slot (instead of multitask panel)
  Future<void> openBodyElementSampleBrowserForSlot(int slot) async {
    _bodyElementSampleBrowserSlot = slot;
    _currentSamplePath.clear();
    await _loadSamples();
    
    // Open body element browser (NOT multitask panel)
    _isBodyElementSampleBrowserOpen = true;
    
    notifyListeners();
  }
  
  /// Close body element sample browser
  void closeBodyElementSampleBrowser() {
    _isBodyElementSampleBrowserOpen = false;
    _bodyElementSampleBrowserSlot = null;
    _currentSamplePath.clear();
    _currentSampleItems.clear();
    notifyListeners();
  }

  Future<void> selectSampleItem(SampleBrowserItem item) async {
    if (item.isFolder) {
      _currentSamplePath.add(item.name);
      await _loadSamples();
      notifyListeners();
    } else {
      // Select the sample file
      await _selectSampleFile(item.path, item.name);
    }
  }

  void navigateBackInSamples() {
    if (_currentSamplePath.isNotEmpty) {
      _currentSamplePath.removeLast();
      _loadSamples();
      notifyListeners();
    }
  }

  Future<void> _selectSampleFile(String path, String name) async {
    // Check which browser is active
    final isBodyBrowser = _isBodyElementSampleBrowserOpen;
    final slot = isBodyBrowser ? _bodyElementSampleBrowserSlot : _sampleSelectionSlot;
    
    if (slot == null) return;
    
    try {
      // Flush any pending debounced actions before sample loading
      _flushPendingUndoAction();
      
      // Capture state before loading sample
      final beforeState = _captureCurrentState();
      
      String finalPath = path;
      
      // Check if this is a bundled asset path (starts with "samples/")
      if (path.startsWith('samples/')) {
        print('🎵 Loading bundled asset: $path');
        finalPath = await _copyAssetToTemp(path, name);
        print('📁 Copied to temp file: $finalPath');
      }
      
      _filePaths[slot] = finalPath;
      _fileNames[slot] = name;
      _slotLoaded[slot] = false;
      
      // Always load sample to memory immediately
      loadSlot(slot);
      
      // Record undo action
      _recordUndoAction(
        type: UndoRedoActionType.sampleLoad,
        description: 'Load Sample ${String.fromCharCode(65 + slot)}: $name',
        beforeState: beforeState,
      );
      
      // Close appropriate sample selection
      if (isBodyBrowser) {
        closeBodyElementSampleBrowser();
      } else {
        cancelSampleSelection();
      }
      
    } catch (e) {
      print('❌ Error loading sample: $e');
    }
  }

  Future<void> _loadSamples() async {
    try {
      // Load and parse the asset manifest to discover all sample files
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      // Get all sample file paths (only audio files)
      final samplePaths = manifestMap.keys
          .where((path) => path.startsWith('samples/') && _isAudioFile(path))
          .toList();
      
      // Build dynamic folder structure
      _currentSampleItems = _buildDynamicStructure(samplePaths, _currentSamplePath);
      
    } catch (e) {
      print('Error loading samples: $e');
      _currentSampleItems = [];
    }
  }

  List<SampleBrowserItem> _buildDynamicStructure(List<String> allSamplePaths, List<String> currentPath) {
    final currentPathPrefix = currentPath.isEmpty ? 'samples/' : 'samples/${currentPath.join('/')}/';
    
    final folders = <String>{};
    final files = <SampleBrowserItem>[];
    
    for (final samplePath in allSamplePaths) {
      if (samplePath.startsWith(currentPathPrefix)) {
        // Remove the current path prefix to get relative path
        final relativePath = samplePath.substring(currentPathPrefix.length);
        final pathParts = relativePath.split('/');
        
        if (pathParts.length == 1 && pathParts[0].isNotEmpty) {
          // It's a file in the current directory
          files.add(SampleBrowserItem(
            name: pathParts[0],
            path: samplePath,
            isFolder: false,
            size: 0,
          ));
        } else if (pathParts.length > 1 && pathParts[0].isNotEmpty) {
          // It's a file in a subdirectory, so we add the subdirectory as a folder
          folders.add(pathParts[0]);
        }
      }
    }
    
    // Convert folders to SampleBrowserItems
    final folderItems = folders.map((folderName) => SampleBrowserItem(
      name: folderName,
      path: '', // Folders don't have file paths
      isFolder: true,
      size: 0,
    )).toList();
    
    // Sort everything alphabetically
    folderItems.sort((a, b) => a.name.compareTo(b.name));
    files.sort((a, b) => a.name.compareTo(b.name));
    
    return [...folderItems, ...files];
  }

  bool _isAudioFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['wav', 'mp3', 'aac', 'm4a', 'flac', 'ogg'].contains(ext);
  }

  Future<void> previewSample(String assetPath) async {
    try {
      // Copy asset to temp file for preview
      final fileName = path.basename(assetPath);
      final tempPath = await _copyAssetToTemp(assetPath, fileName);
      
      // Use a dedicated preview slot (999) that doesn't interfere with regular slots (0-7)
      const int previewSlot = 999;
      bool loadSuccess = _sequencerLibrary.loadSoundToSlot(previewSlot, tempPath, loadToMemory: true);
      if (loadSuccess) {
        _sequencerLibrary.reconfigureAudioSession();
        _sequencerLibrary.playSlot(previewSlot);
      }
    } catch (e) {
      print('❌ Error previewing sample: $e');
    }
  }

  void stopSamplePreview() {
    // Stop and unload the preview slot
    const int previewSlot = 999;
    _sequencerLibrary.stopSlot(previewSlot);
    _sequencerLibrary.unloadSlot(previewSlot);
  }

  void loadSlot(int slot) {
    final path = _filePaths[slot];
    if (path == null) return;
    bool success = _sequencerLibrary.loadSoundToSlot(
      slot,
      path,
      loadToMemory: true,
    );
    _slotLoaded[slot] = success;
    
    // Trigger autosave when sample is loaded
    _triggerAutosave();
    
    notifyListeners();
  }

  void playSlot(int slot) {
    // Sample should already be loaded in memory
    if (!_slotLoaded[slot]) {
      // If not loaded for some reason, try loading first
      loadSlot(slot);
      if (!_slotLoaded[slot]) return; // Give up if loading failed
    }
    
    // Ensure Bluetooth audio routing is active before playback
    _sequencerLibrary.reconfigureAudioSession();
    
    bool success = _sequencerLibrary.playSlot(slot);
    if (success) {
      _slotPlaying[slot] = true;
      notifyListeners();
    }
  }

  void stopSlot(int slot) {
    _sequencerLibrary.stopSlot(slot);
    _slotPlaying[slot] = false;
    notifyListeners();
  }

  void stopAll() {
    _sequencerLibrary.stopAllSounds();
    for (int i = 0; i < _slotCount; ++i) {
      _slotPlaying[i] = false;
    }
    notifyListeners();
  }

  void playAll() {
    // First, ensure any slots with files are loaded
    for (int i = 0; i < _slotCount; i++) {
      if (_filePaths[i] != null && !_slotLoaded[i]) {
        loadSlot(i);
      }
    }

    // Ensure Bluetooth audio routing is active before playback
    _sequencerLibrary.reconfigureAudioSession();

    // Then play all loaded slots
    _sequencerLibrary.playAllLoadedSlots();

    // Update UI state for all loaded slots
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        _slotPlaying[i] = true;
      }
    }
    notifyListeners();
  }

  void handleBankChange(int bankIndex, BuildContext context) {
    final hasFile = _fileNames[bankIndex] != null;
    
    // Always set as selected sample slot
    _selectedSampleSlot = bankIndex;
    
    // Always open appropriate menu based on slot content
    if (!hasFile) {
      // Empty slot - open body element sample browser (V2+ layout) or multitask panel (V1)
      if (_selectedLayout == SequencerLayoutVersion.v2 || _selectedLayout == SequencerLayoutVersion.v3) {
        // Use body element approach for V2+ layouts
        openBodyElementSampleBrowserForSlot(bankIndex);
      } else {
        // Use original multitask panel approach for V1 layout
        pickFileForSlot(bankIndex, context);
      }
    } else {
      // Loaded slot - always open sample settings
      _activeBank = bankIndex;
      setShowSampleSettings(true);
      
      // ALSO perform step insert if mode is active and cells are selected
      if (_isStepInsertMode && _selectedGridCells.isNotEmpty) {
        performStepInsert(bankIndex);
      }
    }
    notifyListeners();
  }

  void removeSample(int slot) {
    if (slot < 0 || slot >= _slotCount) return;
    
    // Flush any pending debounced actions before sample removal
    _flushPendingUndoAction();
    
    // Capture state before removal (including sample name for description)
    final beforeState = _captureCurrentState();
    final sampleName = _fileNames[slot] ?? 'Sample ${String.fromCharCode(65 + slot)}';
    
    // Stop playing if currently playing
    if (_slotPlaying[slot]) {
      stopSlot(slot);
    }
    
    // Unload from native audio engine
    _sequencerLibrary.unloadSlot(slot);
    
    // Clear slot state
    _slotLoaded[slot] = false;
    _slotPlaying[slot] = false;
    _filePaths[slot] = null;
    _fileNames[slot] = null;
    
    // Clear any grid cells that were using this sample
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final gridSamples = _soundGridSamples[gridIndex];
      for (int cellIndex = 0; cellIndex < gridSamples.length; cellIndex++) {
        if (gridSamples[cellIndex] == slot) {
          gridSamples[cellIndex] = null;
          // Also clear from native sequencer
          final row = cellIndex ~/ _gridColumns;
          final col = cellIndex % _gridColumns;
          final absoluteColumn = gridIndex * _gridColumns + col;
          final absoluteStep = _currentSectionIndex * _gridRows + row;
          _sequencerLibrary.clearGridCell(absoluteStep, absoluteColumn);
        }
      }
    }
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.sampleRemove,
      description: 'Remove $sampleName',
      beforeState: beforeState,
    );
    
    // Trigger autosave
    _triggerAutosave();
    
    notifyListeners();
  }

  void handlePadPress(int padIndex) {
    // Ignore tap events if user is currently dragging
    if (_isDragging) {
      return;
    }
    
    final now = DateTime.now();
    final currentGrid = _getCurrentGridSamples();
    final cellHasSample = padIndex < currentGrid.length && currentGrid[padIndex] != null;
    
    // Check for double-tap
    if (_lastTapTime != null && 
        _lastTappedCell == padIndex &&
        now.difference(_lastTapTime!) <= _doubleTapThreshold) {
      // Double-tap detected
      if (cellHasSample) {
        // Double-tap on cell with sample - open cell settings
        setSelectedCellForSettings(padIndex);
        _lastTapTime = null;
        _lastTappedCell = null;
        return;
      } else {
        // Double-tap on empty cell - clear all selections and exit selection mode
        _clearAllSelections();
        _lastTapTime = null;
        _lastTappedCell = null;
        return;
      }
    }
    
    // Update last tap info for double-tap detection
    _lastTapTime = now;
    _lastTappedCell = padIndex;
    
    // Normal single tap behavior (not in selection mode)
    if (!_isInSelectionMode) {
      if (_selectedGridCells.contains(padIndex)) {
        // Tapping on an already selected cell - just remove the selection without adding new
        _selectedGridCells.clear();
        _selectionStartCell = null;
        _currentSelectionCell = null;
      } else {
        // Step 1: Always unselect any previous selections first
        _selectedGridCells.clear();
        _selectionStartCell = null;
        _currentSelectionCell = null;
        
        // Step 2: Select the new cell
        _selectedGridCells.add(padIndex);
        _selectionStartCell = padIndex;
        _currentSelectionCell = padIndex;
        
        // Step 3: If cell has a sample, open cell settings menu
        if (cellHasSample) {
          setSelectedCellForSettings(padIndex);
          
          // Step 4: Preview the cell if sequencer is not playing
          if (!_isSequencerPlaying) {
            _previewCellFromPadPress(padIndex);
          }
        }
      }
    } else {
      // In selection mode
      if (_selectedGridCells.isEmpty) {
        // No cells selected - select the tapped cell
        _selectedGridCells.add(padIndex);
        _selectionStartCell = padIndex;
        _currentSelectionCell = padIndex;
        
        // If cell has a sample, open cell settings menu
        if (cellHasSample) {
          setSelectedCellForSettings(padIndex);
          
          // Preview the cell if sequencer is not playing
          if (!_isSequencerPlaying) {
            _previewCellFromPadPress(padIndex);
          }
        }
      } else if (_selectedGridCells.contains(padIndex)) {
        // Tapping on an already selected cell - just remove the selection without adding new
        _selectedGridCells.clear();
        _selectionStartCell = null;
        _currentSelectionCell = null;
      } else if (_selectedGridCells.length == 1) {
        // Exactly one cell selected and tapping a different cell - unselect previous and select new
        _selectedGridCells.clear();
        _selectedGridCells.add(padIndex);
        _selectionStartCell = padIndex;
        _currentSelectionCell = padIndex;
        
        // If cell has a sample, open cell settings menu
        if (cellHasSample) {
          setSelectedCellForSettings(padIndex);
          
          // Preview the cell if sequencer is not playing
          if (!_isSequencerPlaying) {
            _previewCellFromPadPress(padIndex);
          }
        }
      } else {
        // Multiple cells selected and tapping an unselected cell - clear all selections
        _selectedGridCells.clear();
        _selectionStartCell = null;
        _currentSelectionCell = null;
      }
    }
    
    notifyListeners();
  }
  
  void _clearAllSelections() {
    _selectedGridCells.clear();
    _selectionStartCell = null;
    _currentSelectionCell = null;
    _isInSelectionMode = false; // Exit selection mode
    _isSelecting = false;
    notifyListeners();
  }

  void handleGridCellSelection(int cellIndex, bool isInside) {
    // Only handle grid cell selection if we're in selection mode
    if (!_isInSelectionMode) {
      return;
    }
    
    if (!isInside) {
      // End of drag - reset dragging state
      _isSelecting = false;
      _isDragging = false;
      notifyListeners();
      return;
    }

    if (!_isSelecting) {
      // Start drag selection immediately when touching down
      _isSelecting = true;
      _isDragging = true; // Mark as dragging
      _selectionStartCell = cellIndex;
      _currentSelectionCell = cellIndex;
      
      // Start with just the touched cell selected
      _selectedGridCells = {cellIndex};
    } else {
      // Update selection rectangle during drag
      _currentSelectionCell = cellIndex;
      _updateRectangularSelection();
    }
    notifyListeners();
  }

  void _updateRectangularSelection() {
    if (_selectionStartCell == null || _currentSelectionCell == null) return;

    // Convert cell indices to row,col coordinates
    final startRow = _selectionStartCell! ~/ _gridColumns;
    final startCol = _selectionStartCell! % _gridColumns;
    final currentRow = _currentSelectionCell! ~/ _gridColumns;
    final currentCol = _currentSelectionCell! % _gridColumns;

    // Calculate rectangle bounds (inclusive)
    final minRow = startRow < currentRow ? startRow : currentRow;
    final maxRow = startRow > currentRow ? startRow : currentRow;
    final minCol = startCol < currentCol ? startCol : currentCol;
    final maxCol = startCol > currentCol ? startCol : currentCol;

    // Select all cells in the rectangle
    Set<int> newSelection = {};
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        final cellIndex = row * _gridColumns + col;
        // Ensure we don't go out of bounds
        final currentGrid = _getCurrentGridSamples();
        if (cellIndex >= 0 && cellIndex < currentGrid.length) {
          newSelection.add(cellIndex);
        }
      }
    }

    // Only update if selection actually changed (optimization)
    if (newSelection.length != _selectedGridCells.length || 
        !newSelection.every((cell) => _selectedGridCells.contains(cell))) {
      _selectedGridCells = newSelection;
    }
  }

  // OLD Drag & drop sample placement (replaced by version with sequencer sync below)

  // Copy/paste/delete operations
  void copySelectedCells() {
    if (_selectedGridCells.isEmpty) return;

    _clipboard.clear();
    final currentGrid = _getCurrentGridSamples();
    
    // Find the top-left corner of the selection to use as origin
    int minRow = _gridRows;
    int minCol = _gridColumns;
    
    for (int cellIndex in _selectedGridCells) {
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      if (row < minRow) minRow = row;
      if (col < minCol) minCol = col;
    }
    
    // Store relative positions and their sample data
    for (int cellIndex in _selectedGridCells) {
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final relativeRow = row - minRow;
      final relativeCol = col - minCol;
      final relativeIndex = relativeRow * _gridColumns + relativeCol;
      
      if (cellIndex >= 0 && cellIndex < currentGrid.length) {
        _clipboard[relativeIndex] = currentGrid[cellIndex];
      }
    }
    
    _hasClipboardData = true;
    notifyListeners();
  }

  void pasteToSelectedCells() {
    if (!_hasClipboardData || _selectedGridCells.isEmpty) return;

    // Flush any pending debounced actions before paste operation
    _flushPendingUndoAction();

    // Capture state before pasting
    final beforeState = _captureCurrentState();
    int pastedCells = 0;

    // Find the top-left corner of the current selection
    int minRow = _gridRows;
    int minCol = _gridColumns;
    
    for (int cellIndex in _selectedGridCells) {
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      if (row < minRow) minRow = row;
      if (col < minCol) minCol = col;
    }
    
    // Paste clipboard data starting from the top-left of selection
    for (MapEntry<int, int?> entry in _clipboard.entries) {
      final relativeIndex = entry.key;
      final sampleSlot = entry.value;
      
      final relativeRow = relativeIndex ~/ _gridColumns;
      final relativeCol = relativeIndex % _gridColumns;
      final targetRow = minRow + relativeRow;
      final targetCol = minCol + relativeCol;
      
      // Check bounds
      if (targetRow >= 0 && targetRow < _gridRows && 
          targetCol >= 0 && targetCol < _gridColumns) {
        final targetIndex = targetRow * _gridColumns + targetCol;
        _setCurrentGridSample(targetIndex, sampleSlot);
        pastedCells++;
      }
    }

    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.multipleCellChange,
      description: 'Paste to $pastedCells cells',
      beforeState: beforeState,
    );

    notifyListeners();
  }

  void deleteSelectedCells() {
    if (_selectedGridCells.isEmpty) return;

    // Flush any pending debounced actions before delete operation
    _flushPendingUndoAction();

    // Capture state before deletion
    final beforeState = _captureCurrentState();
    final deletedCount = _selectedGridCells.length;

    final currentGrid = _getCurrentGridSamples();
    for (int cellIndex in _selectedGridCells) {
      if (cellIndex >= 0 && cellIndex < currentGrid.length) {
        _setCurrentGridSample(cellIndex, null);
        // Sync deletion to native sequencer using absolute column calculation
        final row = cellIndex ~/ _gridColumns;
        final col = cellIndex % _gridColumns;
        final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
        final absoluteStep = _currentSectionIndex * _gridRows + row;
        _sequencerLibrary.clearGridCell(absoluteStep, absoluteColumn);
      }
    }

    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.multipleCellChange,
      description: 'Delete $deletedCount cells',
      beforeState: beforeState,
    );

    // Clear selection after deletion
    _selectedGridCells.clear();
    _selectionStartCell = null;
    _currentSelectionCell = null;
    notifyListeners();
  }

  void clearCell(int cellIndex) {
    final currentGrid = _getCurrentGridSamples();
    if (cellIndex >= 0 && cellIndex < currentGrid.length) {
      _setCurrentGridSample(cellIndex, null);
      // Sync deletion to native sequencer using absolute column calculation
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      final absoluteStep = _currentSectionIndex * _gridRows + row;
      _sequencerLibrary.clearGridCell(absoluteStep, absoluteColumn);
      notifyListeners();
    }
  }

  // Sequencer functionality with sample-accurate timing
  void startSequencer() {
    if (_sequencerLibrary.isSequencerPlaying) return;
    
    // If grid is empty, ensure native grid is cleared to avoid stale cells
    final hasAnyCell = _soundGridSamples.any((grid) => grid.any((cell) => cell != null));
    if (!hasAnyCell) {
      _sequencerLibrary.clearAllGridCells();
    }

    // For song mode: pre-sync all sections once so native has the complete concatenated table
    // Ensure native has the complete concatenated table
    syncFlutterSequencerGridToNativeSequencerGrid();
    
    // Set playback mode in native
    _sequencerLibrary.setSongMode(_sectionPlaybackMode == SectionPlaybackMode.song);
    
    // Note: Grid sync is now called explicitly when needed
    // For simple stop/start, nodes are preserved via ma_node_set_state
    
    // Reset song mode tracking when starting (legacy variables, can be removed later)
    _currentSectionLoopCounter = 0;
    _lastAbsoluteStepForSongMode = -1;
    
    // Start sequencer with current BPM, grid size, and start absolute step based on current section
    final int startAbsoluteStep = (_currentSectionIndex * _gridRows) + 0; // start at step 0 of current section
    bool success = _sequencerLibrary.startSequencer(_bpm, _gridRows, startAbsoluteStep: startAbsoluteStep);
    if (success) {
      _isSequencerPlaying = true;
      
      // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
      _isSequencerPlayingNotifier.value = true;
      
      // Start a timer just for UI updates (not audio timing)
      _startUIUpdateTimer();
      
      // 🎯 PERFORMANCE: Immediate notification for playback state changes
      _notifyImmediately(SequencerChangeType.playback);
    }
  }
  
  void stopSequencer() {
    _sequencerLibrary.stopSequencer();
    _isSequencerPlaying = false;
    _currentStep = -1;
    _currentSectionLoopCounter = 0;
    _lastAbsoluteStepForSongMode = -1;
    
    // 🎯 PERFORMANCE: Update ValueNotifiers for instant UI feedback
    _isSequencerPlayingNotifier.value = false;
    _currentStepNotifier.value = -1;
    
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    
    // Reset column tracking
    for (int i = 0; i < _gridColumns; i++) {
      _columnPlayingSample[i] = null;
    }
    
    // 🎯 PERFORMANCE: Immediate notification for playback state changes
    _notifyImmediately(SequencerChangeType.playback);
  }
  
  /// Transfer Flutter grid state to native sequencer
  /// Call this when:
  /// - App startup after loading saved state
  /// - Loading new saved state  
  /// - Switching sound grids
  /// - Major grid changes
  void syncFlutterSequencerGridToNativeSequencerGrid() {
    // Clear everything and rebuild (simpler and more reliable)
    _sequencerLibrary.clearAllGridCells();
    print('🔄 [SYNC] Cleared native sequencer completely');
    
    // Transfer ALL SECTIONS for ALL sound grids to native table
    int totalCellsSet = 0;
    for (int sectionIndex = 0; sectionIndex < _numSections; sectionIndex++) {
      // Determine source grid data for this section
      final List<List<int?>> sectionGridData = sectionIndex == _currentSectionIndex
          ? _soundGridSamples.map((g) => List<int?>.from(g)).toList()
          : (_sectionGridData[sectionIndex]?.map((g) => List<int?>.from(g)).toList() ??
              List.generate(_soundGridSamples.length, (i) => List.filled(_gridColumns * _gridRows, null)));
      
      for (int gridIndex = 0; gridIndex < sectionGridData.length; gridIndex++) {
        final gridSamples = sectionGridData[gridIndex];
        int gridCellsSet = 0;
        for (int row = 0; row < _gridRows; row++) {
          for (int col = 0; col < _gridColumns; col++) {
            final cellIndex = row * _gridColumns + col;
            final sampleSlot = gridSamples[cellIndex];
            if (sampleSlot != null) {
              final absoluteStep = sectionIndex * _gridRows + row;
              final absoluteColumn = gridIndex * _gridColumns + col;
              _sequencerLibrary.setGridCell(absoluteStep, absoluteColumn, sampleSlot);
              gridCellsSet++;
              totalCellsSet++;
              print('🎹 [SYNC] Section $sectionIndex Grid $gridIndex: Set [row:$row, col:$col] → native [absoluteStep:$absoluteStep, absoluteCol:$absoluteColumn] = sample $sampleSlot');
            }
          }
        }
        print('📊 [SYNC] Section $sectionIndex Grid $gridIndex: Set $gridCellsSet cells');
      }
    }
    print('✅ [SYNC] Total: Set $totalCellsSet cells across $_numSections sections × ${_soundGridSamples.length} grids');
  }
  
  void _startUIUpdateTimer() {
    // 🎯 PERFORMANCE: Optimized UI polling with ValueNotifier
    const uiUpdateIntervalMs = 100; // 10 FPS UI updates
    
    _sequencerTimer = Timer.periodic(Duration(milliseconds: uiUpdateIntervalMs), (timer) {
      if (!_sequencerLibrary.isSequencerPlaying) {
        timer.cancel();
        _sequencerTimer = null;
        return;
      }
      
      final absoluteStep = _sequencerLibrary.currentStep;
      
      if (_sectionPlaybackMode == SectionPlaybackMode.song) {
        // In song mode: compute current section from absolute step
        final currentSectionFromAbsoluteStep = absoluteStep ~/ _gridRows;
        final relativeStep = absoluteStep % _gridRows;
        
        // Check if we've reached the last step of the last section
        final songEndStep = _numSections * _gridRows;
        if (absoluteStep >= songEndStep - 1) {
          // We're at or past the last step - stop playback to let sounds decay
          stopSequencer();
          return;
        }
        
        // Update UI section if it changed
        if (currentSectionFromAbsoluteStep != _currentSectionIndex) {
          _currentSectionIndex = currentSectionFromAbsoluteStep;
          notifyListeners(); // Update UI to show new section
        }
        
        _currentStep = relativeStep;
        _currentStepNotifier.value = relativeStep;
      } else {
        // Loop mode: stay within current section
        final sectionStart = _currentSectionIndex * _gridRows;
        final relativeStep = absoluteStep - sectionStart;
        
        if (relativeStep != _currentStep) {
          _currentStep = relativeStep;
          _currentStepNotifier.value = relativeStep;
        }
      }
        
      // 🎯 PERFORMANCE: No notifyListeners() call - only ValueNotifier updates!
      // This eliminates unnecessary widget rebuilds during playback
    });
  }
  
  // Alternative: Disable UI polling entirely for performance testing
  void _startUIUpdateTimerMinimal() {
    // NO UI polling - for testing if FFI calls are causing audio stuttering
    print('🧪 [PERF TEST] UI polling disabled - step indicator will not update');
  }
  
  // Update grid cell and sync to sequencer
  void placeSampleInGrid(int sampleSlot, int cellIndex) {
    // Flush any pending debounced actions before grid changes
    _flushPendingUndoAction();
    
    // Capture state before making changes
    final beforeState = _captureCurrentState();
    
    if (_selectedGridCells.isNotEmpty) {
      // Place sample in all selected cells
      final cellCount = _selectedGridCells.length;
      for (int selectedIndex in _selectedGridCells) {
        _setCurrentGridSample(selectedIndex, sampleSlot);
      }
      _selectedGridCells.clear();
      
      // Record undo action for multiple cells
      _recordUndoAction(
        type: UndoRedoActionType.multipleCellChange,
        description: 'Place Sample ${String.fromCharCode(65 + sampleSlot)} in $cellCount cells',
        beforeState: beforeState,
      );
    } else {
      // Place sample in just this cell
      _setCurrentGridSample(cellIndex, sampleSlot);
      
      // Record undo action for single cell
      final cellPosition = _getCellPositionString(cellIndex);
      _recordUndoAction(
        type: UndoRedoActionType.gridCellChange,
        description: 'Place Sample ${String.fromCharCode(65 + sampleSlot)} at $cellPosition',
        beforeState: beforeState,
      );
    }
    notifyListeners();
  }

  void stopSequencerOld() {
    _isSequencerPlaying = false;
    _currentStep = -1;
    notifyListeners();
    
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    
    // Stop all currently playing sounds
    stopAll();
    
    // Reset column tracking
    for (int i = 0; i < _gridColumns; i++) {
      _columnPlayingSample[i] = null;
    }
  }

  void _scheduleNextStep() {
    if (!_isSequencerPlaying) return;
    
    // Calculate step duration based on BPM
    // 1/16 note at 120 BPM = 60/120/4 = 0.125 seconds = 125ms
    final stepDurationMs = (60 * 1000) ~/ (_bpm * 4);
    
    _sequencerTimer = Timer(Duration(milliseconds: stepDurationMs), () {
      if (_isSequencerPlaying) {
        _playCurrentStep();
        
        _currentStep = (_currentStep + 1) % _gridRows; // Loop back to 0 after last row
        notifyListeners();
        
        _scheduleNextStep();
      }
    });
  }

  void _playCurrentStep() {
    // Play all sounds on the current line simultaneously
    // Only stop sounds where there's a new sound in the same column
    final currentGrid = _getCurrentGridSamples();
    for (int col = 0; col < _gridColumns; col++) {
      final cellIndex = _currentStep * _gridColumns + col;
      final cellSample = currentGrid[cellIndex];
      
      // Check if there's a sample in this cell on the current line
      if (cellSample != null && _slotLoaded[cellSample]) {
        // Stop previous sound in this column only if there was one playing
        if (_columnPlayingSample[col] != null) {
          // Stop only the specific sample that was playing in this column
          stopSlot(_columnPlayingSample[col]!);
        }
        
        // Play the new sound (all sounds on this line will play simultaneously)
        playSlot(cellSample);
        _columnPlayingSample[col] = cellSample; // Store the sample slot, not the cell index
      }
      // If there's no sample in this cell, do nothing - let previous sound continue
      // This allows sounds from previous steps to continue until replaced
    }
  }

  // Recording functionality
  Future<void> startRecording() async {
    if (_isRecording) return;
    
    try {
      // Generate unique filename with timestamp
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final filename = 'niyya_recording_$timestamp.wav';
      
      // Use direct path to avoid path_provider pigeon channel issues on Android
      String directoryPath;
      if (Platform.isAndroid) {
        // Use Android's public Downloads directory - always accessible
        directoryPath = '/storage/emulated/0/Download';
        print('📁 Using Android Downloads directory: $directoryPath');
      } else {
        // For other platforms, keep using path_provider
        final directory = await getApplicationDocumentsDirectory();
        directoryPath = directory.path;
        print('📁 Using documents directory: $directoryPath');
      }
      
      _currentRecordingPath = path.join(directoryPath, filename);
      print('🎙️ Recording to: $_currentRecordingPath');
      
      bool success = _sequencerLibrary.startOutputRecording(_currentRecordingPath!);
      if (success) {
        _isRecording = true;
        notifyListeners();
        print('🎙️ Recording started: $_currentRecordingPath');
      } else {
        print('❌ Failed to start recording');
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
    }
  }
  
  void stopRecording() {
    if (!_isRecording) return;
    
    bool success = _sequencerLibrary.stopOutputRecording();
    if (success) {
      _isRecording = false;
      // Store the completed recording info
      _lastRecordingPath = _currentRecordingPath;
      _lastRecordingTime = DateTime.now();
      
      // Add to local recordings list
      if (_currentRecordingPath != null) {
        _addLocalRecording(_currentRecordingPath!);
      }
      
      _currentRecordingPath = null;
      notifyListeners();
      
      // Could show a success message or share the recording
      print('🎙️ Recording saved to: $_lastRecordingPath');
    }
  }

  // Utility methods
  int? getCellIndexFromPosition(Offset localPosition, BuildContext context, {double scrollOffset = 0.0}) {
    // Calculate grid cell dimensions
    const crossAxisCount = 4;
    const crossAxisSpacing = 4.0;
    const mainAxisSpacing = 4.0;
    const childAspectRatio = 2.5;
    const containerPadding = 16.0; // Account for Container padding in SampleGridWidget
    
    // Get the available space (subtract outer padding: 32px each side + inner container padding: 16px each side)
    final availableWidth = MediaQuery.of(context).size.width - 64 - (containerPadding * 2);
    
    // Calculate cell dimensions
    final cellWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;
    final cellHeight = cellWidth / childAspectRatio;
    
    // Adjust local position to account for container padding and scroll offset
    final adjustedX = localPosition.dx - containerPadding;
    final adjustedY = localPosition.dy - containerPadding + scrollOffset;
    
    // Calculate which cell was touched with generous boundary detection
    // Add 2px margin to make edge selection more forgiving
    const edgeMargin = 2.0;
    
    final columnFloat = (adjustedX + edgeMargin) / (cellWidth + crossAxisSpacing);
    final rowFloat = (adjustedY + edgeMargin) / (cellHeight + mainAxisSpacing);
    
    final column = columnFloat.floor();
    final row = rowFloat.floor();
    
    // More forgiving bounds check - allow slight overshoot
    final isInColumnBounds = column >= 0 && column < _gridColumns;
    final isInRowBounds = row >= 0 && row < _gridRows;
    
    // Additional check: if we're close to a cell boundary, include it
    final isNearRightEdge = column == _gridColumns && adjustedX <= availableWidth + edgeMargin;
    final isNearBottomEdge = row == _gridRows && adjustedY <= (_gridRows * (cellHeight + mainAxisSpacing)) + edgeMargin;
    
    if ((isInColumnBounds || (column == _gridColumns && isNearRightEdge)) && 
        (isInRowBounds || (row == _gridRows && isNearBottomEdge))) {
      // Clamp to valid indices if we're at the edge
      final validColumn = column >= _gridColumns ? _gridColumns - 1 : column;
      final validRow = row >= _gridRows ? _gridRows - 1 : row;
      
      return validRow * _gridColumns + validColumn;
    }
    
    return null;
  }

  String formatMemorySize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  // Generate shareable data for the current pattern
  Future<Map<String, dynamic>> generateShareData(dynamic pattern) async {
    final now = DateTime.now();
    final patternName = 'NIYYA Pattern';
    
    // Build sample information
    List<Map<String, dynamic>> sampleInfo = [];
    int loadedSamples = 0;
    
    for (int i = 0; i < _slotCount; i++) {
      if (_fileNames[i] != null) {
        sampleInfo.add({
          'slot': String.fromCharCode(65 + i), // A, B, C, etc.
          'name': _fileNames[i],
          'loaded': _slotLoaded[i],
        });
        if (_slotLoaded[i]) loadedSamples++;
      }
    }
    
    // Build grid pattern visualization
    final currentGrid = _getCurrentGridSamples();
    List<String> gridVisualization = [];
    for (int row = 0; row < _gridRows; row++) {
      String rowString = '';
      for (int col = 0; col < _gridColumns; col++) {
        final cellIndex = row * _gridColumns + col;
        final sampleSlot = currentGrid[cellIndex];
        if (sampleSlot != null) {
          rowString += String.fromCharCode(65 + sampleSlot); // A, B, C, etc.
        } else {
          rowString += '-';
        }
        if (col < _gridColumns - 1) rowString += ' ';
      }
      gridVisualization.add('${(row + 1).toString().padLeft(2, '0')}: $rowString');
    }
    
    // Count placed samples
    int placedSamples = currentGrid.where((sample) => sample != null).length;
    
    // Build human-readable text
    String shareText = '''🎵 NIYYA SEQUENCER PATTERN 🎵

Pattern: $patternName
BPM: $_bpm
Grid: ${_gridColumns}x${_gridRows}
Samples: $loadedSamples loaded, $placedSamples placed
Created: ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}

🎼 SAMPLES:
${sampleInfo.isEmpty ? 'No samples loaded' : sampleInfo.map((s) => '${s['slot']}: ${s['name']} ${s['loaded'] ? '✓' : '⏳'}').join('\n')}

🎹 PATTERN:
${gridVisualization.join('\n')}

Made with Demo Sequencer 🚀
''';

    // Build structured data for future API integrations
    Map<String, dynamic> structuredData = {
      'version': '1.0',
      'timestamp': now.toIso8601String(),
      'pattern': {
        'id': now.millisecondsSinceEpoch.toString(),
        'name': patternName,
        'bpm': _bpm,
        'grid': {
          'columns': _gridColumns,
          'rows': _gridRows,
          'samples': currentGrid,
        },
        'samples': sampleInfo,
        'metadata': {
          'loadedSamples': loadedSamples,
          'placedSamples': placedSamples,
          'isPlaying': _isSequencerPlaying,
          'currentStep': _currentStep,
        }
      },
      'app': {
        'name': 'NIYYA Sequencer',
        'version': '1.0.0',
      }
    };
    
    return {
      'text': shareText,
              'subject': 'NIYYA Sequencer Pattern: $patternName',
      'data': structuredData,
              'hashtags': ['#NiyyaSequencer', '#MusicProduction', '#Beats', '#Pattern'],
    };
  }

  // Share the recorded audio file
  Future<void> shareRecordedAudio() async {
    if (_lastRecordingPath == null) {
      print('❌ No recording to share');
      return;
    }

    try {
      final file = File(_lastRecordingPath!);
      if (await file.exists()) {
        final fileName = path.basename(_lastRecordingPath!);
        await Share.shareXFiles(
          [XFile(_lastRecordingPath!)],
                  text: 'Check out this beat I made with N! 🎵\n\n#NiyyaSequencer #BeatMaking #MusicProduction',
        subject: 'NIYYA Sequencer Recording - $fileName',
        );
        print('🎵 Shared recording: $fileName');
      } else {
        print('❌ Recording file not found: $_lastRecordingPath');
      }
    } catch (e) {
      print('❌ Error sharing recording: $e');
    }
  }

  // Clear the last recording
  void clearLastRecording() {
    _lastRecordingPath = null;
    _lastRecordingTime = null;
    _lastMp3Path = null;
    _conversionError = null;
    notifyListeners();
  }

  // Convert the last recorded WAV to MP3 320kbps
  Future<void> convertLastRecordingToMp3() async {
    if (_lastRecordingPath == null) {
      print('❌ No recording to convert');
      return;
    }

    if (_isConverting) {
      print('❌ Already converting audio');
      return;
    }

    try {
      _isConverting = true;
      _conversionProgress = 0.0;
      _conversionError = null;
      notifyListeners();

      print('🎵 Starting MP3 conversion...');
      
      final mp3Path = await AudioConversionService.convertWavToMp3WithProgress(
        inputWavPath: _lastRecordingPath!,
        onProgress: (progress) {
          _conversionProgress = progress;
          notifyListeners();
        },
        onError: (error) {
          _conversionError = error;
          print('❌ Conversion error: $error');
        },
      );

      if (mp3Path != null) {
        _lastMp3Path = mp3Path;
        _conversionProgress = 1.0;
        print('✅ MP3 conversion completed: $mp3Path');
        
        // Get file sizes for comparison
        final wavFile = File(_lastRecordingPath!);
        final mp3File = File(mp3Path);
        if (await wavFile.exists() && await mp3File.exists()) {
          final wavSize = await wavFile.length();
          final mp3Size = await mp3File.length();
          final compressionRatio = (1 - (mp3Size / wavSize)) * 100;
          print('📊 WAV: ${_formatFileSize(wavSize)} → MP3: ${_formatFileSize(mp3Size)} (${compressionRatio.toStringAsFixed(1)}% smaller)');
        }
      } else {
        print('❌ MP3 conversion failed');
        _conversionError ??= 'Conversion failed for unknown reason';
      }
    } catch (e) {
      print('❌ Error during MP3 conversion: $e');
      _conversionError = 'Conversion error: $e';
    } finally {
      _isConverting = false;
      notifyListeners();
    }
  }

  // Share the MP3 version if available, otherwise share WAV
  Future<void> shareRecordedAudioAsMp3() async {
    String? shareFilePath;
    String fileType;
    
    if (_lastMp3Path != null) {
      shareFilePath = _lastMp3Path;
      fileType = 'MP3';
    } else if (_lastRecordingPath != null) {
      shareFilePath = _lastRecordingPath;
      fileType = 'WAV';
    } else {
      print('❌ No recording to share');
      return;
    }

    try {
      final file = File(shareFilePath!);
      if (await file.exists()) {
        final fileName = path.basename(shareFilePath);
        final fileSize = await file.length();
        
        await Share.shareXFiles(
          [XFile(shareFilePath)],
                  text: 'Check out this beat I made with NIYYA! 🎵\n\nFormat: $fileType (${_formatFileSize(fileSize)})\n\n',
        subject: 'NIYYA Sequencer Recording - $fileName',
        );
        print('🎵 Shared $fileType recording: $fileName');
      } else {
        print('❌ Recording file not found: $shareFilePath');
      }
    } catch (e) {
      print('❌ Error sharing recording: $e');
    }
  }

  // Check if conversion is available
  Future<bool> isConversionAvailable() async {
    return await AudioConversionService.checkConversionAvailability();
  }

  // Format file size helper
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  
  // Update BPM and sync with native sequencer
  void setBpm(int newBpm) {
    if (newBpm < minBpm || newBpm > maxBpm) return;
    
    _bpm = newBpm;
    
    // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
    _bpmNotifier.value = newBpm;
    
    // Update sequencer BPM if it's running
    if (_sequencerLibrary.isSequencerPlaying) {
      _sequencerLibrary.setSequencerBpm(newBpm);
    }
    
    // Trigger autosave when BPM changes
    _triggerAutosave();
    
    notifyListeners();
  }

  // Update number of sections in the chain
  void setNumSections(int newNumSections) {
    if (newNumSections < 1 || newNumSections > 10) return; // Limit to reasonable range
    
    _numSections = newNumSections;
    
    // Trigger autosave when section count changes
    _triggerAutosave();
    
    notifyListeners();
  }

  // New method: Toggle selection mode on/off
  void toggleSelectionMode() {
    _isInSelectionMode = !_isInSelectionMode;
    
    // If exiting selection mode, clear all selections
    if (!_isInSelectionMode) {
      _selectedGridCells.clear();
      _selectionStartCell = null;
      _currentSelectionCell = null;
      _isSelecting = false;
    }
    
    notifyListeners();
  }

  // New method: Handle end of drag selection
  void handlePanEnd() {
    if (_isInSelectionMode) {
      _isSelecting = false;
      _isDragging = false;
      notifyListeners();
    }
  }

  // Sound Grid stack methods
  void initializeSoundGrids(int numGrids) {
    // Initialize with L1 at front (closest to user)
    // Stack widget: index 0=back, index (n-1)=front  
    // Inversion: invertedIndex = numGrids - 1 - stackIndex
    // Want: stackIndex 2 (front) → invertedIndex 0 → soundGridOrder[0] should be L1 (gridId=0)
    // Want: stackIndex 1 (middle) → invertedIndex 1 → soundGridOrder[1] should be L2 (gridId=1)  
    // Want: stackIndex 0 (back) → invertedIndex 2 → soundGridOrder[2] should be L3 (gridId=2)
    // So soundGridOrder = [0, 1, 2] = [L1, L2, L3]
    _soundGridOrder = List.generate(numGrids, (index) => index);
    _currentSoundGridIndex = 0; // L1 is front initially
    
    // Initialize grid samples for each sound grid
    _soundGridSamples = List.generate(numGrids, (index) => 
        List.filled(_gridColumns * _gridRows, null));
    
    // Initialize grid labels - simplified to just track count
    _soundGridLabels = List.generate(numGrids, (index) => 'L${index + 1}');
    
    // Configure native sequencer columns (native calculates: numGrids × columnsPerGrid)
    final nativeTableColumns = numGrids * _gridColumns;
    _sequencerLibrary.configureColumns(nativeTableColumns);
    print('🎛️ Initialized $numGrids sound grids × $_gridColumns columns = $nativeTableColumns native table columns');
    
    notifyListeners();
  }

  void setCurrentSoundGridIndex(int index) {
    _currentSoundGridIndex = index;
    notifyListeners();
  }

  // Bring a specific grid to the front by reordering soundGridOrder
  void bringGridToFront(int gridId) {
    if (_soundGridOrder.contains(gridId)) {
      // Remove the grid from its current position
      _soundGridOrder.remove(gridId);
      // Add it to the BEGINNING (front position due to inversion)
      // Because invertedIndex = numGrids - 1 - stackIndex
      // Stack index 2 (front) → invertedIndex 0 → soundGridOrder[0]
      _soundGridOrder.insert(0, gridId);
      // Update current grid index
      _currentSoundGridIndex = gridId;
      notifyListeners();
      print('🎛️ Brought grid $gridId to front. New order: $_soundGridOrder');
    }
  }

  // Helper method to get current sound grid's samples
  List<int?> _getCurrentGridSamples() {
    if (_soundGridSamples.isEmpty || _currentSoundGridIndex >= _soundGridSamples.length) {
      return List.filled(_gridColumns * _gridRows, null);
    }
    return _soundGridSamples[_currentSoundGridIndex];
  }

  // Helper method to set sample in current sound grid - 🎯 PERFORMANCE OPTIMIZED
  void _setCurrentGridSample(int index, int? value) {
    if (_soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length) {
      // Check if sample is actually changing
      final oldSample = _soundGridSamples[_currentSoundGridIndex][index];
      final sampleChanged = oldSample != value;
      
      // 🎯 PERFORMANCE: Only update if value actually changed
      if (sampleChanged) {
        _soundGridSamples[_currentSoundGridIndex][index] = value;
        
        // Reset cell volume/pitch overrides when sample changes or when clearing cell with sample
        if (oldSample != null || value != null) {
          // Reset Flutter-side cell overrides when:
          // 1. Sample changes to different sample (oldSample != null && value != null)
          // 2. Cell with sample is cleared (oldSample != null && value == null)
          _cellVolumes.remove(index);
          _cellPitches.remove(index);
          
          // 🎯 PERFORMANCE: Update ValueNotifiers for cell controls
          _cellVolumeNotifiers[index]?.value = getCellVolume(index);
          _cellPitchNotifiers[index]?.value = getCellPitch(index);
          
          print('🔄 [FLUTTER] Reset cell $index volume/pitch overrides due to change ($oldSample → $value)');
        }
        
        // 🔧 FIX: Immediately sync this change to native sequencer if sequencer is running
        _syncSingleCellToNative(index, value);
        
        // Trigger autosave when grid changes
        _triggerAutosave();
        
        // 🎯 PERFORMANCE: Use batched notification for grid changes
        _scheduleNotification(SequencerChangeType.grid);
      }
    }
  }

  void _syncSingleCellToNative(int cellIndex, int? sampleSlot) {
    // Calculate step and column from cell index
    final relativeStep = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    
    // Calculate absolute step: section * stepsPerSection + relativeStep
    final absoluteStep = _currentSectionIndex * _gridRows + relativeStep;
    
    // Calculate absolute column: gridIndex * columnsPerGrid + localColumn
    final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
    
    if (sampleSlot != null) {
      _sequencerLibrary.setGridCell(absoluteStep, absoluteColumn, sampleSlot);
      print('🎹 [SYNC] Set cell [grid:$_currentSoundGridIndex, step:$relativeStep, col:$col] → native [absoluteStep:$absoluteStep, absoluteCol:$absoluteColumn] = sample $sampleSlot');
    } else {
      _sequencerLibrary.clearGridCell(absoluteStep, absoluteColumn);
      print('🗑️ [SYNC] Cleared cell [grid:$_currentSoundGridIndex, step:$relativeStep, col:$col] → native [absoluteStep:$absoluteStep, absoluteCol:$absoluteColumn]');
    }
  }

  void shuffleToNextSoundGrid() {
    // Move the front sound grid (last in array) to the back (first in array)
    // This simulates taking the top sound grid and putting it at the bottom
    if (_soundGridOrder.isNotEmpty) {
      final frontGrid = _soundGridOrder.removeLast(); // Remove front sound grid
      _soundGridOrder.insert(0, frontGrid); // Put it at the back
      
      // Update current sound grid index to represent the new front sound grid
      _currentSoundGridIndex = _soundGridOrder.last;
      notifyListeners();
    }
  }

  void addSoundGrid() {
    // Capture state before adding grid
    final beforeState = _captureCurrentState();
    final newGridIndex = _soundGridSamples.length;
    
    // Add new empty grid
    _soundGridSamples.add(List.filled(_gridColumns * _gridRows, null));
    _soundGridOrder.add(newGridIndex);
    
    // Reconfigure native columns
    final nativeTableColumns = numSoundGrids * _gridColumns;
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.gridAdd,
      description: 'Add Sound Grid ${newGridIndex + 1}',
      beforeState: beforeState,
    );
    
    print('➕ Added sound grid $newGridIndex (total: $numSoundGrids grids = $nativeTableColumns native columns)');
    notifyListeners();
  }

  void removeSoundGrid() {
    if (_soundGridSamples.length <= 1) {
      print('❌ Cannot remove grid - minimum 1 grid required');
      return;
    }
    
    // Capture state before removing grid
    final beforeState = _captureCurrentState();
    final removedGridIndex = _soundGridSamples.length - 1;
    
    // Remove the last grid
    _soundGridSamples.removeLast();
    _soundGridOrder.removeWhere((index) => index == removedGridIndex);
    
    // Adjust current grid index if necessary
    if (_currentSoundGridIndex >= _soundGridSamples.length) {
      _currentSoundGridIndex = _soundGridSamples.length - 1;
    }
    
    // Reconfigure native columns
    final nativeTableColumns = numSoundGrids * _gridColumns;
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.gridRemove,
      description: 'Remove Sound Grid ${removedGridIndex + 1}',
      beforeState: beforeState,
    );
    
    print('➖ Removed sound grid $removedGridIndex (total: $numSoundGrids grids = $nativeTableColumns native columns)');
    notifyListeners();
  }

  void clearAllCells() {
    final currentGrid = _getCurrentGridSamples();
    for (int i = 0; i < currentGrid.length; i++) {
      _setCurrentGridSample(i, null);
    }
    notifyListeners();
  }

  void setupDemo() {
    // Demo setup logic
    if (_slotCount >= 2) {
      // Only modify current sound grid
      final demoGridIndex = (_gridRows ~/ 2) * _gridColumns;
      _setCurrentGridSample(demoGridIndex, 0); // First loaded slot
      
      final secondDemoIndex = demoGridIndex + 2;
      if (secondDemoIndex < _getCurrentGridSamples().length) {
        _setCurrentGridSample(secondDemoIndex, 1); // Second loaded slot
      }
    }
  }

  // 🧪 DEBUG: Print comprehensive grid state for debugging
  void debugPrintGridState() {
    print('\n🔍 ===== GRID STATE DEBUG =====');
    print('📊 Current Sound Grid Index: $_currentSoundGridIndex');
    print('📊 Total Sound Grids: ${_soundGridSamples.length}');
    print('📊 Grid Dimensions: $_gridColumns × $_gridRows');
    print('📊 Native Columns: ${numSoundGrids * _gridColumns}');
    print('📊 Sequencer Playing: $_isSequencerPlaying');
    print('📊 Current Step: $_currentStep');
    
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      print('\n🎛️ --- Sound Grid $gridIndex ---');
      final gridSamples = _soundGridSamples[gridIndex];
      int cellsWithSamples = 0;
      
      for (int row = 0; row < _gridRows; row++) {
        String rowString = 'Row ${row.toString().padLeft(2, '0')}: ';
        for (int col = 0; col < _gridColumns; col++) {
          final cellIndex = row * _gridColumns + col;
          final sampleSlot = gridSamples[cellIndex];
          if (sampleSlot != null) {
            rowString += '[${sampleSlot.toString().padLeft(2, ' ')}] ';
            cellsWithSamples++;
          } else {
            rowString += '[ - ] ';
          }
        }
        // Only print rows with content
        if (rowString.contains('[') && !rowString.replaceAll('[ - ]', '').trim().endsWith(':')) {
          print(rowString);
        }
      }
      
      if (cellsWithSamples == 0) {
        print('   (empty grid)');
      } else {
        print('   Total cells with samples: $cellsWithSamples');
      }
    }
    
    print('\n📱 --- Native Mapping ---');
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final startCol = gridIndex * _gridColumns;
      final endCol = startCol + _gridColumns - 1;
      print('Grid $gridIndex → Native columns $startCol-$endCol');
    }
    
    print('🔍 ===== END DEBUG =====\n');
  }

  // Getters for grid labels
  List<String> get soundGridLabels => List.unmodifiable(_soundGridLabels);
  
  String getGridLabel(int gridIndex) {
    return 'L${gridIndex + 1}';
  }

  void setGridLabel(int gridIndex, String label) {
    if (gridIndex >= 0 && gridIndex < _soundGridLabels.length) {
      _soundGridLabels[gridIndex] = label.toUpperCase();
      notifyListeners();
    }
  }

  // =============================================================================
  // GRID ROW MANAGEMENT FUNCTIONALITY
  // =============================================================================
  
  static const int minGridRows = 4;
  int get maxGridRows => _maxSequencerSteps;
  
  /// Increase the number of grid rows by 1
  void increaseGridRows() {
    if (_gridRows >= maxGridRows) return;
    
    // Flush any pending debounced actions before grid changes
    _flushPendingUndoAction();
    
    // Capture state before making changes
    final beforeState = _captureCurrentState();
    
    final oldRows = _gridRows;
    _gridRows++;
    
    // Resize all sound grids to accommodate new rows
    _resizeAllSoundGrids(oldRows, _gridRows);
    
    // Reconfigure native sequencer columns (dimensions may have changed)
    final nativeTableColumns = numSoundGrids * _gridColumns;
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
    // Sync all grids to native sequencer
    syncFlutterSequencerGridToNativeSequencerGrid();
    
    // 🎯 REAL-TIME UPDATE: If sequencer is playing, update step count seamlessly  
    if (_isSequencerPlaying) {
      _sequencerLibrary.setSequencerSteps(_gridRows);
      debugPrint('🔄 Updated playing sequencer steps: ${oldRows} → $_gridRows (seamless)');
    }
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.gridResize,
      description: 'Increase grid rows: $oldRows → $_gridRows',
      beforeState: beforeState,
    );
    
    debugPrint('➕ Increased grid rows: $oldRows → $_gridRows');
    notifyListeners();
  }
  
  /// Decrease the number of grid rows by 1
  void decreaseGridRows() {
    if (_gridRows <= minGridRows) return;
    
    // Flush any pending debounced actions before grid changes
    _flushPendingUndoAction();
    
    // Capture state before making changes
    final beforeState = _captureCurrentState();
    
    final oldRows = _gridRows;
    _gridRows--;
    
    // Resize all sound grids to accommodate fewer rows (may lose data in bottom rows)
    _resizeAllSoundGrids(oldRows, _gridRows);
    
    // Clear any selections that are now out of bounds
    _clearOutOfBoundsSelections();
    
    // Reconfigure native sequencer columns (dimensions may have changed)
    final nativeTableColumns = numSoundGrids * _gridColumns;
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
    // Sync all grids to native sequencer
    syncFlutterSequencerGridToNativeSequencerGrid();
    
    // Record undo action
    _recordUndoAction(
      type: UndoRedoActionType.gridResize,
      description: 'Decrease grid rows: $oldRows → $_gridRows',
      beforeState: beforeState,
    );
    
    debugPrint('➖ Decreased grid rows: $oldRows → $_gridRows');
    notifyListeners();
  }
  
  /// Resize all sound grids when the number of rows changes
  /// Grows/shrinks from the BOTTOM so existing content stays in same visual position
  void _resizeAllSoundGrids(int oldRows, int newRows) {
    final oldSize = oldRows * _gridColumns;
    final newSize = newRows * _gridColumns;
    final rowDifference = newRows - oldRows;
    final cellDifference = rowDifference * _gridColumns;
    
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final oldGrid = _soundGridSamples[gridIndex];
      final newGrid = <int?>[];
      
      if (newSize > oldSize) {
        // Increasing size - ADD NEW EMPTY ROWS AT THE BOTTOM
        // First add all existing data (which stays at the top)
        newGrid.addAll(oldGrid);
        // Then add empty cells at the end for new rows
        newGrid.addAll(List.filled(cellDifference, null));
        
        debugPrint('➕ Grid $gridIndex: Added ${rowDifference} empty rows at bottom');
      } else {
        // Decreasing size - REMOVE ROWS FROM THE BOTTOM
        final cellsToKeep = newSize; // Only keep the first N cells
        
        // Take only the top rows that fit in the new size
        final dataToKeep = oldGrid.take(cellsToKeep).toList();
        newGrid.addAll(dataToKeep);
        
        // Log any lost samples from removed bottom rows
        final lostCells = oldGrid.skip(cellsToKeep).where((sample) => sample != null).length;
        if (lostCells > 0) {
          debugPrint('⚠️ Grid $gridIndex: Lost $lostCells samples in bottom rows');
        } else {
          debugPrint('➖ Grid $gridIndex: Removed ${-rowDifference} empty rows from bottom');
        }
      }
      
      _soundGridSamples[gridIndex] = newGrid;
    }
  }
  
  /// Clear any selections that are now out of bounds after grid resize
  void _clearOutOfBoundsSelections() {
    final maxValidIndex = _gridRows * _gridColumns - 1;
    final originalSelectionSize = _selectedGridCells.length;
    
    _selectedGridCells.removeWhere((cellIndex) => cellIndex > maxValidIndex);
    
    if (_selectedGridCells.length != originalSelectionSize) {
      debugPrint('🧹 Cleared ${originalSelectionSize - _selectedGridCells.length} out-of-bounds selections');
    }
    
    // Reset selection tracking if selections were cleared
    if (_selectedGridCells.isEmpty) {
      _selectionStartCell = null;
      _currentSelectionCell = null;
    }
  }

  // =============================================================================
  // AUTOSAVE FUNCTIONALITY
  // =============================================================================

  void _startAutosave() {
    if (!_autosaveEnabled) return;
    
    _autosaveTimer = Timer.periodic(_autosaveInterval, (timer) {
      _saveStateToPreferences();
    });
  }

  /// Trigger debounced autosave (called when state changes)
  void _triggerAutosave() {
    if (!_autosaveEnabled) return;
    
    // Mark that we have unsaved changes
    _hasUnsavedChanges = true;
    notifyListeners();
    
    // Cancel any existing debounce timer
    _debounceTimer?.cancel();
    
    // Start new debounce timer - only save after user stops making changes
    _debounceTimer = Timer(_debounceDelay, () async {
      // Additional throttling: don't save more than once per 5 seconds
      final now = DateTime.now();
      if (_lastSaveTime != null && 
          now.difference(_lastSaveTime!) < const Duration(seconds: 5)) {
        return;
      }
      
      _isCurrentlySaving = true;
      notifyListeners();
      
      await _saveStateToPreferences();
      
      _lastSaveTime = now;
      _hasUnsavedChanges = false;
      _isCurrentlySaving = false;
      notifyListeners();
    });
  }

  /// Save current sequencer state to SharedPreferences for autosave
  Future<void> _saveStateToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = _serializeCurrentState();
      await prefs.setString(_autosaveKey, stateJson);
      debugPrint('🔄 Autosaved sequencer state to local storage (${stateJson.length} chars)');
    } catch (e) {
      debugPrint('❌ Error autosaving state: $e');
    }
  }

  /// Load autosaved state from SharedPreferences
  Future<void> _loadAutosavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString(_autosaveKey);
      
      if (stateJson != null) {
        await _deserializeAndApplyState(stateJson);
        debugPrint('✅ Loaded autosaved sequencer state from local storage');
      }
    } catch (e) {
      debugPrint('❌ Error loading autosaved state: $e');
    }
  }

  /// Serialize current sequencer state to JSON
  String _serializeCurrentState() {
    final state = {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'bpm': _bpm,
      'gridColumns': _gridColumns,
      'gridRows': _gridRows,
      'currentSoundGridIndex': _currentSoundGridIndex,
      'activeBank': _activeBank,
      'selectedLayout': _selectedLayout.name, // Save layout as string
      'filePaths': _filePaths,
      'fileNames': _fileNames,
      'slotLoaded': _slotLoaded,
      'soundGridSamples': _soundGridSamples,
      'soundGridOrder': _soundGridOrder,
      'soundGridLabels': _soundGridLabels,
    };
    return jsonEncode(state);
  }

  /// Deserialize and apply state from JSON
  Future<void> _deserializeAndApplyState(String stateJson) async {
    try {
      final state = jsonDecode(stateJson) as Map<String, dynamic>;
      
      // Apply simple properties
      _bpm = state['bpm'] ?? defaultBpm;
      _bpmNotifier.value = _bpm; // Sync ValueNotifier with restored BPM
      _gridColumns = state['gridColumns'] ?? 4;
      _gridRows = (state['gridRows'] ?? 16).clamp(minGridRows, maxGridRows);
      _currentSoundGridIndex = state['currentSoundGridIndex'] ?? 0;
      _activeBank = state['activeBank'] ?? 0;
      
      // Apply layout selection
      final layoutName = state['selectedLayout'] as String?;
      if (layoutName != null) {
        try {
          _selectedLayout = SequencerLayoutVersion.values.firstWhere(
            (layout) => layout.name == layoutName,
            orElse: () => SequencerLayoutVersion.v1,
          );
        } catch (e) {
          _selectedLayout = SequencerLayoutVersion.v1; // Default fallback
        }
      }
      
      // Apply file paths and names
      final filePaths = List<String?>.from(state['filePaths'] ?? []);
      final fileNames = List<String?>.from(state['fileNames'] ?? []);
      final slotLoaded = List<bool>.from(state['slotLoaded'] ?? []);
      
      for (int i = 0; i < _slotCount && i < filePaths.length; i++) {
        _filePaths[i] = filePaths[i];
        _fileNames[i] = fileNames[i];
        _slotLoaded[i] = slotLoaded.length > i ? slotLoaded[i] : false;
      }
      
      // Apply sound grid samples
      final soundGridSamples = state['soundGridSamples'] as List?;
      if (soundGridSamples != null) {
        _soundGridSamples.clear();
        for (final gridData in soundGridSamples) {
          final gridSamples = List<int?>.from(gridData);
          _soundGridSamples.add(gridSamples);
        }
      }
      
      // Apply sound grid order
      final soundGridOrder = state['soundGridOrder'] as List?;
      if (soundGridOrder != null) {
        _soundGridOrder = List<int>.from(soundGridOrder);
      }
      
      // Apply sound grid labels
      final soundGridLabels = state['soundGridLabels'] as List?;
      if (soundGridLabels != null) {
        _soundGridLabels = List<String>.from(soundGridLabels);
      }
      
      // Reload samples that were previously loaded
      for (int i = 0; i < _slotLoaded.length; i++) {
        if (_slotLoaded[i] && _filePaths[i] != null) {
          // Note: We can't actually reload files from paths that might not exist anymore
          // So we just mark them as not loaded for now
          _slotLoaded[i] = false;
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error deserializing state: $e');
    }
  }

  /// Manually save current state (can be called explicitly)
  Future<void> saveCurrentState() async {
    await _saveStateToPreferences();
  }

  /// Clear autosaved state from SharedPreferences
  Future<void> clearAutosavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_autosaveKey);
      debugPrint('🗑️ Cleared autosaved sequencer state');
    } catch (e) {
      debugPrint('❌ Error clearing autosaved state: $e');
    }
  }

  /// Toggle autosave on/off
  void setAutosaveEnabled(bool enabled) {
    _autosaveEnabled = enabled;
    if (enabled) {
      _startAutosave();
    } else {
      _autosaveTimer?.cancel();
      _debounceTimer?.cancel();
    }
    notifyListeners();
  }

  /// Reset sequencer to fresh state (for testing)
  Future<void> resetToFreshState() async {
    debugPrint('🧪 Resetting sequencer to fresh state...');
    
    // Stop everything and fully clear native grid/state
    _sequencerLibrary.stopAllSounds();
    _sequencerLibrary.stopSequencer();
    _sequencerLibrary.clearAllGridCells();
    
    // Clear all current state
    _clearAllSampleSlots();
    clearAllCells();
    
    // Reset to defaults
    _bpm = defaultBpm;
    _currentStep = -1;
    _isSequencerPlaying = false;
    _activeBank = 0;
    _currentSoundGridIndex = 0;
    _selectedGridCells.clear();
    _isSelecting = false;
    _isInSelectionMode = false;
    _isDragging = false;
    
    // Sections: reset to a single blank section
    _numSections = 1;
    _currentSectionIndex = 0;
    _sectionLoopCounts = [1];
    _sectionGridData.clear();
    _sequencerLibrary.setTotalSections(_numSections);
    _sequencerLibrary.setCurrentSection(_currentSectionIndex);
    
    // Clear sound grids
    _soundGridSamples.clear();
    _soundGridOrder.clear();
    _soundGridLabels.clear();
    
    // Add default sound grid
    addSoundGrid();
    
    // Clear autosaved data
    await clearAutosavedState();
    
    debugPrint('✅ Sequencer reset to fresh state');
    notifyListeners();
  }



  /// Set selected cell for settings
  void setSelectedCellForSettings(int? cellIndex) {
    _selectedCellForSettings = cellIndex;
    if (cellIndex != null) {
      setShowCellSettings(true);
    }
    notifyListeners();
  }

  /// Get sample volume (0.0 to 1.0)
  double getSampleVolume(int sampleIndex) {
    if (sampleIndex >= 0 && sampleIndex < _sampleVolumes.length) {
      return _sampleVolumes[sampleIndex];
    }
    return 1.0; // Default volume
  }

  /// Set sample volume (0.0 to 1.0) - 🎯 PERFORMANCE ENHANCED
  void setSampleVolume(int sampleIndex, double volume) {
    if (sampleIndex >= 0 && sampleIndex < _sampleVolumes.length) {
      final clampedVolume = volume.clamp(0.0, 1.0);
      
      // 🎯 PERFORMANCE: Only update if value actually changed
      if (_sampleVolumes[sampleIndex] != clampedVolume) {
        // Capture state before change (only if this is the first change in sequence)
        final beforeState = _pendingUndoBeforeState ?? _captureCurrentState();
        
        _sampleVolumes[sampleIndex] = clampedVolume;
        
        // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
        _sampleVolumeNotifiers[sampleIndex]?.value = clampedVolume;
        
        // Apply volume to native audio engine with debouncing for performance
        _debouncedNativeVolumeCall('sample_$sampleIndex', clampedVolume, () {
          _sequencerLibrary.setSampleBankVolume(sampleIndex, clampedVolume);
          
          // Preview the sample with new volume for immediate feedback
          _previewSampleWithNewVolume(sampleIndex, clampedVolume);
        });
        
        // Record debounced undo action (will only record after user stops adjusting)
        _recordDebouncedUndoAction(
          type: UndoRedoActionType.volumeChange,
          description: 'Set Sample ${String.fromCharCode(65 + sampleIndex)} Volume: ${(clampedVolume * 100).round()}%',
          beforeState: beforeState,
        );
        
        // 🎯 PERFORMANCE: Use batched notification for non-critical UI updates
        _scheduleNotification(SequencerChangeType.volume);
      }
    }
  }

  /// Get cell volume (returns cell override or sample bank volume)
  double getCellVolume(int cellIndex) {
    // Check if cell has a volume override
    if (_cellVolumes.containsKey(cellIndex)) {
      return _cellVolumes[cellIndex]!;
    }
    
    // No override, use sample bank volume
    final gridSamples = _soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length
        ? _soundGridSamples[_currentSoundGridIndex]
        : <int?>[];
    final sampleSlot = cellIndex < gridSamples.length ? gridSamples[cellIndex] : null;
    if (sampleSlot != null && sampleSlot >= 0 && sampleSlot < _sampleVolumes.length) {
      return _sampleVolumes[sampleSlot];
    }
    
    return 1.0; // Default volume
  }

  /// Set cell volume (0.0 to 1.0) - 🎯 PERFORMANCE OPTIMIZED
  void setCellVolume(int cellIndex, double volume) {
    final clampedVolume = volume.clamp(0.0, 1.0);
    
    // 🎯 PERFORMANCE: Only update if value actually changed
    final currentVolume = _cellVolumes[cellIndex] ?? getCellVolume(cellIndex);
    if (currentVolume != clampedVolume) {
      // Capture state before change (only if this is the first change in sequence)
      final beforeState = _pendingUndoBeforeState ?? _captureCurrentState();
      
      // Store cell volume override
      _cellVolumes[cellIndex] = clampedVolume;
      
      // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
      _cellVolumeNotifiers[cellIndex]?.value = clampedVolume;
      
      // Convert cellIndex to step and column for native call
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      
      // Store volume in native grid with debouncing for performance
      _debouncedNativeVolumeCall('cell_$cellIndex', clampedVolume, () {
        _sequencerLibrary.setCellVolume(row, absoluteColumn, clampedVolume);
        
        // Preview the cell with new volume for immediate feedback
        final cellPitch = getCellPitch(cellIndex);
        _previewCellWithAutoStop(row, absoluteColumn, cellPitch, clampedVolume);
      });
      
      // Record debounced undo action (will only record after user stops adjusting)
      final cellPosition = _getCellPositionString(cellIndex);
      _recordDebouncedUndoAction(
        type: UndoRedoActionType.volumeChange,
        description: 'Set Cell $cellPosition Volume: ${(clampedVolume * 100).round()}%',
        beforeState: beforeState,
      );
      
      // 🎯 PERFORMANCE: Use batched notification for non-critical UI updates
      _scheduleNotification(SequencerChangeType.volume);
    }
  }

  /// Get sample pitch (0.03125 to 32.0, where 1.0 = normal, covers C0 to C10)
  double getSamplePitch(int sampleIndex) {
    if (sampleIndex >= 0 && sampleIndex < _samplePitches.length) {
      return _samplePitches[sampleIndex];
    }
    return 1.0; // Default pitch
  }

  /// Set sample pitch (0.03125 to 32.0, where 1.0 = normal, covers C0 to C10) - 🎯 PERFORMANCE OPTIMIZED
  void setSamplePitch(int sampleIndex, double pitch) {
    if (sampleIndex >= 0 && sampleIndex < _samplePitches.length) {
      final clampedPitch = pitch.clamp(0.03125, 32.0); // C0 to C10 range
      
      // 🎯 PERFORMANCE: Only update if value actually changed
      if (_samplePitches[sampleIndex] != clampedPitch) {
        // Capture state before change (only if this is the first change in sequence)
        final beforeState = _pendingUndoBeforeState ?? _captureCurrentState();
        
        _samplePitches[sampleIndex] = clampedPitch;
        
        // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
        _samplePitchNotifiers[sampleIndex]?.value = clampedPitch;
        
        // Apply pitch to native audio engine with debouncing for performance
        _debouncedNativePitchCall('sample_$sampleIndex', clampedPitch, () {
          _sequencerLibrary.setSampleBankPitch(sampleIndex, clampedPitch);
          
          // Preview the sample with new pitch for immediate feedback
          _previewSampleWithNewPitch(sampleIndex, clampedPitch);
        });
        
        // Record debounced undo action (will only record after user stops adjusting)
        _recordDebouncedUndoAction(
          type: UndoRedoActionType.pitchChange,
          description: 'Set Sample ${String.fromCharCode(65 + sampleIndex)} Pitch: ${clampedPitch.toStringAsFixed(2)}x',
          beforeState: beforeState,
        );
        
        // 🎯 PERFORMANCE: Use batched notification for non-critical UI updates
        _scheduleNotification(SequencerChangeType.pitch);
      }
    }
  }

  /// Debounced native pitch calls for performance
  void _debouncedNativePitchCall(String key, double pitch, VoidCallback actualCall) {
    // Store the pending value
    _pendingNativePitchCalls[key] = pitch;
    
    // Cancel existing timer
    _nativePitchDebounceTimer?.cancel();
    
    // Set new timer
    _nativePitchDebounceTimer = Timer(_nativeCallDebounceDelay, () {
      // Execute all pending pitch calls
      final pendingCalls = Map<String, double>.from(_pendingNativePitchCalls);
      _pendingNativePitchCalls.clear();
      
      for (final entry in pendingCalls.entries) {
        if (entry.key == key) {
          actualCall(); // Call the actual native function
          break;
        }
      }
    });
  }
  
  /// Debounced native volume calls for performance
  void _debouncedNativeVolumeCall(String key, double volume, VoidCallback actualCall) {
    // Store the pending value
    _pendingNativeVolumeCalls[key] = volume;
    
    // Cancel existing timer
    _nativeVolumeDebounceTimer?.cancel();
    
    // Set new timer
    _nativeVolumeDebounceTimer = Timer(_nativeCallDebounceDelay, () {
      // Execute all pending volume calls
      final pendingCalls = Map<String, double>.from(_pendingNativeVolumeCalls);
      _pendingNativeVolumeCalls.clear();
      
      for (final entry in pendingCalls.entries) {
        if (entry.key == key) {
          actualCall(); // Call the actual native function
          break;
        }
      }
    });
  }
  
  /// Force flush all pending native calls immediately (for critical updates)
  void _flushPendingNativeCalls() {
    _nativePitchDebounceTimer?.cancel();
    _nativeVolumeDebounceTimer?.cancel();
    
    // Execute any pending calls immediately
    if (_pendingNativePitchCalls.isNotEmpty) {
      print('🚀 [PERFORMANCE] Flushing ${_pendingNativePitchCalls.length} pending pitch calls');
      _pendingNativePitchCalls.clear();
    }
    
    if (_pendingNativeVolumeCalls.isNotEmpty) {
      print('🚀 [PERFORMANCE] Flushing ${_pendingNativeVolumeCalls.length} pending volume calls');
      _pendingNativeVolumeCalls.clear();
    }
  }

  /// Preview a cell with auto-stop timer for immediate feedback
  void _previewCellWithAutoStop(int step, int column, double pitch, double volume) {
    // Cancel any existing preview timer and stop any active previews
    _previewTimer?.cancel();
    _sequencerLibrary.stopSamplePreview();
    _sequencerLibrary.stopCellPreview();
    
    // Start preview
    _sequencerLibrary.previewCell(step, column, pitch, volume);
    
    // Set timer to auto-stop preview
    _previewTimer = Timer(_previewAutoStopDelay, () {
      _sequencerLibrary.stopCellPreview();
    });
  }
  
  /// Preview a cell when tapped in the UI (when sequencer is not playing)
  void _previewCellFromPadPress(int cellIndex) {
    // Convert cellIndex to step and column for native call
    final row = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
    
    // Get current cell pitch and volume
    final cellPitch = getCellPitch(cellIndex);
    final cellVolume = getCellVolume(cellIndex);
    
    // Preview with auto-stop
    _previewCellWithAutoStop(row, absoluteColumn, cellPitch, cellVolume);
  }
  
  /// Preview a sample with new pitch when sample bank pitch is changed
  void _previewSampleWithNewPitch(int sampleIndex, double pitch) {
    // Check if sample is loaded and has a file path
    if (sampleIndex >= 0 && sampleIndex < _filePaths.length && _filePaths[sampleIndex] != null) {
      final filePath = _filePaths[sampleIndex]!;
      final volume = getSampleVolume(sampleIndex);
      
      // Cancel any existing preview timer and stop any active previews
      _previewTimer?.cancel();
      _sequencerLibrary.stopSamplePreview();
      _sequencerLibrary.stopCellPreview();
      
      // Start sample preview with new pitch
      final success = _sequencerLibrary.previewSample(filePath, pitch, volume);
      
      if (success) {
        // Set timer to auto-stop preview
        _previewTimer = Timer(_previewAutoStopDelay, () {
          _sequencerLibrary.stopSamplePreview();
        });
      }
    }
  }
  
  /// Preview a sample with new volume when sample bank volume is changed
  void _previewSampleWithNewVolume(int sampleIndex, double volume) {
    // Check if sample is loaded and has a file path
    if (sampleIndex >= 0 && sampleIndex < _filePaths.length && _filePaths[sampleIndex] != null) {
      final filePath = _filePaths[sampleIndex]!;
      final pitch = getSamplePitch(sampleIndex);
      
      // Cancel any existing preview timer and stop any active previews
      _previewTimer?.cancel();
      _sequencerLibrary.stopSamplePreview();
      _sequencerLibrary.stopCellPreview();
      
      // Start sample preview with new volume
      final success = _sequencerLibrary.previewSample(filePath, pitch, volume);
      
      if (success) {
        // Set timer to auto-stop preview
        _previewTimer = Timer(_previewAutoStopDelay, () {
          _sequencerLibrary.stopSamplePreview();
        });
      }
    }
  }

  /// Get cell pitch (returns cell override or sample bank pitch)
  double getCellPitch(int cellIndex) {
    // Check if cell has a pitch override
    if (_cellPitches.containsKey(cellIndex)) {
      return _cellPitches[cellIndex]!;
    }
    
    // No override, use sample bank pitch
    final gridSamples = _soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length
        ? _soundGridSamples[_currentSoundGridIndex]
        : <int?>[];
    final sampleSlot = cellIndex < gridSamples.length ? gridSamples[cellIndex] : null;
    if (sampleSlot != null && sampleSlot >= 0 && sampleSlot < _samplePitches.length) {
      return _samplePitches[sampleSlot];
    }
    
    return 1.0; // Default pitch
  }

  /// Set cell pitch (0.03125 to 32.0, where 1.0 = normal, covers C0 to C10) - 🎯 PERFORMANCE OPTIMIZED
  void setCellPitch(int cellIndex, double pitch) {
    final clampedPitch = pitch.clamp(0.03125, 32.0); // C0 to C10 range
    
    // 🎯 PERFORMANCE: Only update if value actually changed
    final currentPitch = _cellPitches[cellIndex] ?? getCellPitch(cellIndex);
    if (currentPitch != clampedPitch) {
      // Capture state before change (only if this is the first change in sequence)
      final beforeState = _pendingUndoBeforeState ?? _captureCurrentState();
      
      // Store cell pitch override
      _cellPitches[cellIndex] = clampedPitch;
      
      // 🎯 PERFORMANCE: Update ValueNotifier for instant UI feedback
      _cellPitchNotifiers[cellIndex]?.value = clampedPitch;
      
      // Convert cellIndex to step and column for native call
      final relativeStep = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteStep = _currentSectionIndex * _gridRows + relativeStep;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      
      // Store pitch in native grid with debouncing for performance
      _debouncedNativePitchCall('cell_$cellIndex', clampedPitch, () {
        _sequencerLibrary.setCellPitch(absoluteStep, absoluteColumn, clampedPitch);
        
        // Preview the cell with new pitch for immediate feedback
        final cellVolume = getCellVolume(cellIndex);
        _previewCellWithAutoStop(absoluteStep, absoluteColumn, clampedPitch, cellVolume);
      });
      
      // Record debounced undo action (will only record after user stops adjusting)
      final cellPosition = _getCellPositionString(cellIndex);
      _recordDebouncedUndoAction(
        type: UndoRedoActionType.pitchChange,
        description: 'Set Cell $cellPosition Pitch: ${clampedPitch.toStringAsFixed(2)}x',
        beforeState: beforeState,
      );
      
      // 🎯 PERFORMANCE: Use batched notification for non-critical UI updates
      _scheduleNotification(SequencerChangeType.pitch);
    }
  }

  /// Reset cell pitch to use sample bank pitch
  void resetCellPitch(int cellIndex) {
    _cellPitches.remove(cellIndex);
    
    // Convert cellIndex to step and column for native call
    final row = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
    
    // Reset to use sample bank default in native grid
    _sequencerLibrary.resetCellPitch(row, absoluteColumn);
    
    notifyListeners();
  }

  /// Reset cell volume to use sample bank volume
  void resetCellVolume(int cellIndex) {
    _cellVolumes.remove(cellIndex);
    
    // Convert cellIndex to step and column for native call
    final row = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
    
    // Reset to use sample bank default in native grid
    _sequencerLibrary.resetCellVolume(row, absoluteColumn);
    
    notifyListeners();
  }

  /// Add a recording to local storage
  void _addLocalRecording(String filePath) {
    _localRecordings.add(filePath);
    _saveRecordingsList();
    notifyListeners();
  }

  /// Save recordings list to ReliableStorage
  Future<void> _saveRecordingsList() async {
    try {
      await ReliableStorage.setStringList('local_recordings', _localRecordings);
    } catch (e) {
      debugPrint('❌ Error saving recordings list: $e');
    }
  }

  /// Load recordings list from ReliableStorage
  Future<void> _loadSavedRecordings() async {
    try {
      final savedRecordings = await ReliableStorage.getStringList('local_recordings');
      
      // Filter out recordings that no longer exist on disk
      _localRecordings.clear();
      for (final recordingPath in savedRecordings) {
        final file = File(recordingPath);
        if (await file.exists()) {
          _localRecordings.add(recordingPath);
        }
      }
      
      // Update saved list to remove non-existent files (but don't await to avoid blocking)
      if (_localRecordings.length != savedRecordings.length) {
        _saveRecordingsList(); // Remove await to prevent blocking initialization
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading saved recordings: $e');
      // Initialize empty list on error to prevent further issues
      _localRecordings.clear();
    }
  }

  // =============================================================================
  // REMOTE DATABASE PUBLISHING
  // =============================================================================

  /// Generate a random 6-character ID for project titles
  String generateProjectId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
      6, (_) => chars.codeUnitAt(random.nextInt(chars.length))
    ));
  }

  /// Update an existing thread to make it public (used when publishing solo threads)
  Future<bool> _updateExistingThread({
    required String threadId,
    required String title,
    String? description,
    List<String>? tags,
    bool isPublic = true,
  }) async {
    try {
      debugPrint('🔄 _updateExistingThread started for thread: $threadId');
      debugPrint('🔄 Making thread public: $isPublic');
      
      // Create a snapshot of current state
      final snapshot = createSnapshot(name: title, comment: description);
      debugPrint('📸 Created snapshot: ${snapshot.id}');
      
      // Create new checkpoint for the existing thread
      final checkpoint = ProjectCheckpoint(
        id: 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
        userId: _threadsState?.currentUserId ?? 'unknown_user',
        userName: _threadsState?.currentUserName ?? 'Unknown User',
        timestamp: DateTime.now(),
        comment: description ?? 'Published from mobile app',
        snapshot: snapshot,
      );
      
      // Prepare update data
      final updateData = <String, dynamic>{
        'metadata': {
          'is_public': isPublic,
          'tags': tags ?? ['mobile', 'sequencer'],
          'description': description ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        'checkpoint': checkpoint.toJson(),
      };

      // Send update to server
      debugPrint('🌐 Updating thread at URL: /threads/$threadId');
      debugPrint('📝 Making thread public: $isPublic');
      debugPrint('🆔 Thread ID: $threadId');
      
      final response = await ApiHttpClient.put('/threads/$threadId', body: updateData);

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Successfully updated thread to public (status: ${response.statusCode})');
        
        // Update local ThreadsState with the new checkpoint
        if (_threadsState != null) {
          try {
            debugPrint('📝 Adding checkpoint to local ThreadsState...');
            // Add the checkpoint to the local thread state
            await _threadsState!.addCheckpoint(
              threadId: threadId,
              userId: checkpoint.userId,
              userName: checkpoint.userName,
              comment: checkpoint.comment,
              snapshot: snapshot,
            );
            
            debugPrint('✅ Updated local ThreadsState with new checkpoint');
          } catch (e) {
            debugPrint('⚠️ Failed to update local ThreadsState: $e');
            // Continue anyway - the server update was successful
          }
        }
        
        // Clear autosaved state since it's now published
        await clearAutosavedState();
        
        return true;
      } else {
        debugPrint('❌ Failed to update thread: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error updating thread: $e');
      return false;
    }
  }

  /// Publish current sequencer state to remote database
  Future<bool> publishToDatabase({
    String? title,
    String? description,
    List<String>? tags,
    bool isPublic = true,
  }) async {
    try {
      // Generate title if not provided
      final projectTitle = title ?? generateProjectId();
      
      debugPrint('🚀 publishToDatabase started - creating new public thread');
      debugPrint('🏷️ Project title: $projectTitle');
      debugPrint('👤 currentUserId: ${_threadsState?.currentUserId}');
      
      // Validate user information
      final currentUserId = _threadsState?.currentUserId;
      final currentUserName = _threadsState?.currentUserName;
      
      if (currentUserId == null || currentUserId == 'unknown_user') {
        debugPrint('❌ Cannot publish: No valid user ID');
        return false;
      }
      
      debugPrint('👤 Publishing with user ID: $currentUserId');
      debugPrint('👤 Publishing with user name: $currentUserName');
      
      // Step 1: Create thread WITHOUT initial checkpoint
      final threadData = {
        'title': projectTitle,
        'users': [
          {
            'id': currentUserId,
            'name': currentUserName ?? 'Unknown User',
            'joined_at': DateTime.now().toIso8601String(),
          }
        ],
        'status': 'active',
        'metadata': {
          'original_project_id': null,
          'project_type': 'solo',
          'genre': 'Electronic',
          'tags': tags ?? ['mobile', 'sequencer'],
          'description': description ?? '',
          'is_public': isPublic,
          'plays_num': 0,
          'likes_num': 0,
          'forks_num': 0,
        },
      };

      // Send thread creation request
      debugPrint('🌐 Creating thread at URL: /threads');
      
      final threadResponse = await ApiHttpClient.post('/threads', body: threadData);

      if (threadResponse.statusCode != 200 && threadResponse.statusCode != 201) {
        debugPrint('❌ Failed to create thread: ${threadResponse.statusCode} - ${threadResponse.body}');
        return false;
      }
      
      // Parse thread creation response
      final threadResponseData = jsonDecode(threadResponse.body);
      final newThreadId = threadResponseData['thread_id'] as String?;
      
      if (newThreadId == null) {
        debugPrint('❌ No thread_id in response');
        return false;
      }
      
      debugPrint('✅ Successfully created thread: $newThreadId');
      
      // Step 2: Create checkpoint using the proper checkpoint API
      final snapshot = createSnapshot(name: projectTitle, comment: description);
      
      // Create a proper ProjectCheckpoint object
      final checkpoint = ProjectCheckpoint(
        id: 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
        userId: currentUserId,
        userName: currentUserName ?? 'Unknown User',
        timestamp: DateTime.now(),
        comment: description ?? 'Published from mobile app',
        snapshot: snapshot,
      );
      
      // Add checkpoint to the thread using ThreadsService
      debugPrint('🌐 Adding checkpoint at URL: /threads/$newThreadId/checkpoints');
      
      try {
        await ThreadsService.addCheckpoint(newThreadId, checkpoint);
        debugPrint('✅ Successfully added checkpoint to thread');
      } catch (e) {
        debugPrint('❌ Failed to add checkpoint: $e');
        // Thread was created but checkpoint failed - still consider it a partial success
        // The user can add checkpoints later
      }
      
      // Step 3: Update local ThreadsState with the new thread from server
      if (_threadsState != null) {
        try {
          // Load the newly created thread from server
          final newThread = await ThreadsService.getThread(newThreadId);
          if (newThread != null) {
            // Set as active thread (this will update the UI)
            _threadsState!.setActiveThread(newThread);
            debugPrint('✅ Set new published thread as active: $newThreadId');
            
            // Refresh threads list to include the new thread
            await _threadsState!.loadThreads();
            debugPrint('✅ Refreshed threads list after publish');
          } else {
            // Fallback: refresh all threads
            await _threadsState!.loadThreads();
            debugPrint('✅ Refreshed all threads after publish (fallback)');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to update local ThreadsState: $e');
          // Continue anyway - the server creation was successful
        }
      }
      
      // Clear autosaved state since it's now published
      await clearAutosavedState();
      
      debugPrint('✅ Successfully published project to database');
      return true;
      
    } catch (e) {
      debugPrint('❌ Error publishing to database: $e');
      return false;
    }
  }

  // =============================================================================
  // COLLABORATION METHODS
  // =============================================================================

  /// Load a project from a Thread ID (for collaboration/sourcing)
  Future<bool> loadFromThread(String threadId) async {
    try {
      debugPrint('🤝 Loading project from thread ID: $threadId');
      
      // Fetch the thread data from server
      final thread = await ThreadsService.getThread(threadId);
      if (thread == null) {
        debugPrint('❌ Thread not found: $threadId');
        return false;
      }
      
      debugPrint('📥 Fetched thread: ${thread.title}');
      
      // For sourcing projects, we want to load the "published" checkpoint, not the latest one
      // The published checkpoint is the one created by the original author when they published
      ProjectCheckpoint? checkpointToLoad;
      
      if (thread.checkpoints.isEmpty) {
        debugPrint('❌ No checkpoints found in thread');
        return false;
      }
      
      // Look for the published checkpoint (created by original author with publish comment)
      final originalAuthor = thread.author;
      for (final checkpoint in thread.checkpoints) {
        if (checkpoint.userId == originalAuthor.id && 
            (checkpoint.comment.contains('Published from mobile app') || 
             checkpoint.comment.contains('Published'))) {
          checkpointToLoad = checkpoint;
          debugPrint('📍 Found published checkpoint: ${checkpoint.comment}');
          break;
        }
      }
      
      // If no published checkpoint found, use the first checkpoint by the original author
      if (checkpointToLoad == null) {
        for (final checkpoint in thread.checkpoints) {
          if (checkpoint.userId == originalAuthor.id) {
            checkpointToLoad = checkpoint;
            debugPrint('📍 Using first checkpoint by author: ${checkpoint.comment}');
            break;
          }
        }
      }
      
      // If still no checkpoint found, fall back to latest (shouldn't happen in normal flow)
      if (checkpointToLoad == null) {
        checkpointToLoad = thread.latestCheckpoint;
        debugPrint('⚠️ Falling back to latest checkpoint: ${checkpointToLoad?.comment}');
      }
      
      if (checkpointToLoad == null) {
        debugPrint('❌ No valid checkpoint found in thread');
        return false;
      }

      debugPrint('📸 Loading checkpoint: ${checkpointToLoad.comment}');

      // Load the sequencer snapshot
      await loadFromSnapshot(checkpointToLoad.snapshot);
      
      // Set collaboration mode
      _isCollaborating = true;
      _sourceThread = thread;
      
      debugPrint('✅ Successfully loaded project from thread: ${thread.title}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error loading project from thread: $e');
      return false;
    }
  }

  /// Load a project from a Thread object (for collaboration/sourcing)
  Future<bool> loadFromThreadObject(Thread thread) async {
    try {
      debugPrint('🤝 Loading project from thread object: ${thread.title}');
      
      // For sourcing projects, we want to load the "published" checkpoint, not the latest one
      // The published checkpoint is the one created by the original author when they published
      ProjectCheckpoint? checkpointToLoad;
      
      if (thread.checkpoints.isEmpty) {
        debugPrint('❌ No checkpoints found in thread');
        return false;
      }
      
      // Look for the published checkpoint (created by original author with publish comment)
      final originalAuthor = thread.author;
      for (final checkpoint in thread.checkpoints) {
        if (checkpoint.userId == originalAuthor.id && 
            (checkpoint.comment.contains('Published from mobile app') || 
             checkpoint.comment.contains('Published'))) {
          checkpointToLoad = checkpoint;
          debugPrint('📍 Found published checkpoint: ${checkpoint.comment}');
          break;
        }
      }
      
      // If no published checkpoint found, use the first checkpoint by the original author
      if (checkpointToLoad == null) {
        for (final checkpoint in thread.checkpoints) {
          if (checkpoint.userId == originalAuthor.id) {
            checkpointToLoad = checkpoint;
            debugPrint('📍 Using first checkpoint by author: ${checkpoint.comment}');
            break;
          }
        }
      }
      
      // If still no checkpoint found, fall back to latest (shouldn't happen in normal flow)
      if (checkpointToLoad == null) {
        checkpointToLoad = thread.latestCheckpoint;
        debugPrint('⚠️ Falling back to latest checkpoint: ${checkpointToLoad?.comment}');
      }
      
      if (checkpointToLoad == null) {
        debugPrint('❌ No valid checkpoint found in thread');
        return false;
      }

      debugPrint('📸 Loading checkpoint: ${checkpointToLoad.comment}');

      // Load the sequencer snapshot
      await loadFromSnapshot(checkpointToLoad.snapshot);
      
      // Set collaboration mode
      _isCollaborating = true;
      _sourceThread = thread;
      
      debugPrint('✅ Successfully loaded project from thread');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error loading project from thread: $e');
      return false;
    }
  }

  /// Load sequencer state from a snapshot
  Future<void> loadFromSnapshot(SequencerSnapshot snapshot) async {
    try {
      debugPrint('📸 Loading sequencer from snapshot: ${snapshot.name}');
      debugPrint('🔍 Snapshot has ${snapshot.audio.sources.length} sources');
      
      // Clear current state first
      _clearAllSampleSlots();
      clearAllCells();
      
      // Load basic metadata
      if (snapshot.audio.sources.isNotEmpty) {
        final source = snapshot.audio.sources.first;
        debugPrint('🔍 Source has ${source.samples.length} samples and ${source.sections.length} sections');
        
        // Load samples first
        final sampleMap = <String, int>{}; // Map sample ID to slot index
        for (int i = 0; i < source.samples.length && i < _slotCount; i++) {
          final sample = source.samples[i];
          sampleMap[sample.id] = i;
          
          // Set the sample metadata
          _fileNames[i] = sample.name;
          _filePaths[i] = sample.url; // Set the URL as file path
          _slotLoaded[i] = true; // Mark as loaded
          
          debugPrint('🎵 Loaded sample ${i + 1}: ${sample.name} (ID: ${sample.id})');
        }
        
        debugPrint('🗺️ Sample map: $sampleMap');
        
        // Load grid data if available
        if (source.sections.isNotEmpty) {
          final section = source.sections.first;
          debugPrint('🔍 Section has ${section.layers.length} layers');
          
          // Update BPM if available
          if (section.metadata.bpm > 0) {
            _bpm = section.metadata.bpm;
            debugPrint('🎵 Set BPM to ${_bpm}');
          }
          
          // Load grid patterns
          if (section.layers.isNotEmpty) {
            // Clear existing sound grids and create new ones for each layer
            _soundGridSamples.clear();
            _soundGridOrder.clear();
            _soundGridLabels.clear();
            
            for (int layerIndex = 0; layerIndex < section.layers.length; layerIndex++) {
              final layer = section.layers[layerIndex];
              debugPrint('🔍 Loading layer ${layerIndex}: ${layer.id} with ${layer.rows.length} rows');
              
              // Add a new sound grid for this layer
              addSoundGrid();
              final gridIndex = _soundGridSamples.length - 1;
              
              // Load grid cells for this layer
              int cellsSet = 0;
              for (int rowIndex = 0; rowIndex < layer.rows.length && rowIndex < _gridRows; rowIndex++) {
                final row = layer.rows[rowIndex];
                for (int cellIndex = 0; cellIndex < row.cells.length && cellIndex < _gridColumns; cellIndex++) {
                  final cell = row.cells[cellIndex];
                  
                  if (cell.sample?.hasSample == true) {
                    // Find the slot index for this sample
                    final sampleSlot = sampleMap[cell.sample!.sampleId];
                    if (sampleSlot != null) {
                      final gridCellIndex = rowIndex * _gridColumns + cellIndex;
                      if (gridCellIndex < _soundGridSamples[gridIndex].length) {
                        _soundGridSamples[gridIndex][gridCellIndex] = sampleSlot;
                        cellsSet++;
                        debugPrint('🎯 Set grid[$gridIndex][$gridCellIndex] = slot $sampleSlot (${_fileNames[sampleSlot]})');
                      }
                    } else {
                      debugPrint('⚠️ Sample ID ${cell.sample!.sampleId} not found in sample map');
                    }
                  }
                }
              }
              debugPrint('✅ Layer $layerIndex: Set $cellsSet cells');
            }
            
            // Set current grid to the first loaded grid
            _currentSoundGridIndex = 0;
            debugPrint('🎛️ Set current sound grid to index 0');
          }
        }
        
        debugPrint('📊 Final state: ${_soundGridSamples.length} grids, ${source.samples.length} samples loaded');
      } else {
        debugPrint('⚠️ No audio sources in snapshot');
      }
      
      debugPrint('✅ Successfully loaded snapshot');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading from snapshot: $e');
      rethrow;
    }
  }

  /// Exit collaboration mode
  void exitCollaboration() {
    _isCollaborating = false;
    _sourceThread = null;
    notifyListeners();
  }

  /// Create a fork of the source thread with current modifications
  Future<bool> createProjectFork({
    required String comment,
    String? currentUserId,
    String? currentUserName,
    dynamic threadsService, // Add ThreadsService parameter
  }) async {
    if (!_isCollaborating || _sourceThread == null) {
      debugPrint('❌ Not in collaboration mode');
      return false;
    }

    try {
      // Use provided user info or fallback
      final userId = currentUserId ?? _threadsState?.currentUserId ?? 'current_user_123';
      final userName = currentUserName ?? _threadsState?.currentUserName ?? 'Collaborator';

      // Get original author info
      final originalAuthor = _sourceThread!.users.first; // Assume first user is the author
      
      // Create a new thread (fork) with both users
      final forkTitle = '${_sourceThread!.title} (Fork)';
      
      if (_threadsState != null) {
        try {
          // Find the original checkpoint that we forked from
          ProjectCheckpoint? originalCheckpoint;
          if (_sourceThread!.checkpoints.isNotEmpty) {
            // Look for the published checkpoint (created by original author with publish comment)
            for (final checkpoint in _sourceThread!.checkpoints) {
              if (checkpoint.userId == originalAuthor.id && 
                  (checkpoint.comment.contains('Published from mobile app') || 
                   checkpoint.comment.contains('Published'))) {
                originalCheckpoint = checkpoint;
                debugPrint('📍 Found original published checkpoint: ${checkpoint.comment}');
                break;
              }
            }
            
            // If no published checkpoint found, use the first checkpoint by the original author
            if (originalCheckpoint == null) {
              for (final checkpoint in _sourceThread!.checkpoints) {
                if (checkpoint.userId == originalAuthor.id) {
                  originalCheckpoint = checkpoint;
                  debugPrint('📍 Using first checkpoint by author: ${checkpoint.comment}');
                  break;
                }
              }
            }
          }
          
          // Create new thread with both users, WITHOUT initial checkpoint (we'll add it manually)
          final forkThreadId = await _threadsState!.createThread(
            title: forkTitle,
            authorId: userId, // Current user is the author of the fork
            authorName: userName,
            collaboratorIds: [originalAuthor.id], // Add original author as collaborator
            collaboratorNames: [originalAuthor.name],
            initialSnapshot: null, // Don't create automatic initial checkpoint
            metadata: {
              'project_type': 'fork',
              'is_public': true,
              'original_thread_id': _sourceThread!.id,
              'fork_comment': comment,
            },
            createInitialCheckpoint: false, // We'll manually add checkpoints
          );
          
          debugPrint('✅ Created fork thread: $forkThreadId');
          
          // First, add the original author's checkpoint (if we found one)
          if (originalCheckpoint != null) {
            await _threadsState!.addCheckpoint(
              threadId: forkThreadId,
              userId: originalCheckpoint.userId, // Use ORIGINAL author's ID
              userName: originalCheckpoint.userName, // Use ORIGINAL author's name
              comment: originalCheckpoint.comment, // Use ORIGINAL comment
              snapshot: originalCheckpoint.snapshot, // Use ORIGINAL snapshot
            );
            debugPrint('✅ Added original author checkpoint to fork: ${originalCheckpoint.userName}');
          }
          
          // Then add the collaborator's modified version as a second checkpoint
          final modifiedSnapshot = createSnapshot(
            name: _sourceThread!.title,
            comment: comment,
          );
          
          await _threadsState!.addCheckpoint(
            threadId: forkThreadId,
            userId: userId,
            userName: userName,
            comment: comment,
            snapshot: modifiedSnapshot,
          );
          
          debugPrint('✅ Added collaborator checkpoint to fork: $userName');
          
          // Load the newly created fork thread from server to get the complete data
          try {
            final newForkThread = await ThreadsService.getThread(forkThreadId);
            if (newForkThread != null) {
              // Exit collaboration mode first
              _isCollaborating = false;
              _sourceThread = null;
              debugPrint('✅ Exited collaboration mode');
              
              // Set the fork thread as the active thread for the collaborator
              _threadsState!.setActiveThread(newForkThread);
              debugPrint('✅ Set fork thread as active thread for collaborator: $forkThreadId');
              
              // Update the local threads list to include the new fork
              await _threadsState!.loadThreads();
              debugPrint('✅ Refreshed threads list after fork creation');
              
              // Notify listeners to update the UI
              notifyListeners();
              debugPrint('✅ Updated UI after fork creation');
            } else {
              debugPrint('⚠️ Could not load fork thread from server');
            }
          } catch (e) {
            debugPrint('⚠️ Failed to load fork thread: $e');
            // Continue anyway - the fork was created successfully
          }
          
          // Send thread message to original author via WebSocket
          try {
                      if (threadsService != null) {
            debugPrint('📡 Sending WebSocket notification to ${originalAuthor.name} (${originalAuthor.id})');
            final success = await threadsService.sendThreadMessage(
                originalAuthor.id,
                forkThreadId,
                forkTitle,
              );
              if (success) {
                debugPrint('📡 ✅ Sent WebSocket notification to ${originalAuthor.name} about fork: $forkTitle');
              } else {
                debugPrint('📡 ❌ Failed to send WebSocket notification to ${originalAuthor.name}');
                debugPrint('📡 ⚠️ Fork was created successfully, but notification failed');
              }
            } else {
              debugPrint('📡 ⚠️ No ThreadsService provided - cannot send notification');
              debugPrint('📡 ℹ️ Fork was created successfully without notification');
            }
          } catch (e) {
            debugPrint('📡 ❌ Exception while sending WebSocket notification: $e');
            debugPrint('📡 ⚠️ Fork was created successfully, but notification failed due to exception');
            // Continue anyway - the fork was created successfully
          }
          
          // Always return true if we got this far - the fork creation was successful
          debugPrint('✅ Fork creation completed successfully, notification status logged above');
          return true;
        } catch (e) {
          debugPrint('❌ Failed to create fork thread: $e');
          return false;
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error creating project fork: $e');
      return false;
    }
  }

  /// Helper method to build API URLs with proper protocol and port
  String _buildApiUrl(String endpoint) {
    final serverIp = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverIp$port/api/v1/$endpoint';
  }

  /// Clear all loaded sample slots
  void _clearAllSampleSlots() {
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        _sequencerLibrary.unloadSlot(i);
        _slotLoaded[i] = false;
        _slotPlaying[i] = false;
        _filePaths[i] = null;
        _fileNames[i] = null;
      }
    }
  }

  // Step Insert Feature Methods
  
  /// Toggle step insert mode on/off and show settings when turning on
  void toggleStepInsertMode() {
    _isStepInsertMode = !_isStepInsertMode;
    if (_isStepInsertMode) {
      // Show settings when turning on
      _currentPanelMode = MultitaskPanelMode.stepInsertSettings;
    }
    // Don't close settings when turning off - let user close manually
    notifyListeners();
  }
  
  /// Set step insert size (1-maxGridRows)
  void setStepInsertSize(int size) {
    if (size >= 1 && size <= _gridRows) {
      _stepInsertSize = size;
      notifyListeners();
    }
  }
  
  /// Perform step insert: place sample in selected cells and move based on step size
  void performStepInsert(int sampleSlot) {
    if (_selectedGridCells.isEmpty) {
      return;
    }
    
    // Flush any pending debounced actions before grid changes
    _flushPendingUndoAction();
    
    // Capture state before making changes
    final beforeState = _captureCurrentState();
    
    final newSelectedCells = <int>{};
    
    // For each selected cell
    for (int cellIndex in _selectedGridCells) {
      // Place the sample in the current cell
      _setCurrentGridSample(cellIndex, sampleSlot);
      
      // Sync to sequencer using absolute column calculation
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      _sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
      
      // Calculate next cell position (jump by step size in same column)
      final nextRow = row + _stepInsertSize;
      if (nextRow < _gridRows) {
        final nextCellIndex = nextRow * _gridColumns + col;
        newSelectedCells.add(nextCellIndex);
      }
    }
    
    // Update selection to the new cells
    _selectedGridCells.clear();
    _selectedGridCells.addAll(newSelectedCells);
    
    // Update selection tracking
    if (newSelectedCells.isNotEmpty) {
      _selectionStartCell = newSelectedCells.first;
      _currentSelectionCell = newSelectedCells.first;
    } else {
      _selectionStartCell = null;
      _currentSelectionCell = null;
    }
    
    // Record undo action
    final cellCount = _selectedGridCells.length + newSelectedCells.length;
    _recordUndoAction(
      type: UndoRedoActionType.multipleCellChange,
      description: 'Step Insert Sample ${String.fromCharCode(65 + sampleSlot)} in $cellCount cells (+${_stepInsertSize} steps)',
      beforeState: beforeState,
    );
    
    notifyListeners();
  }

  @override
  void dispose() {
    // 🎯 PERFORMANCE: Dispose of all ValueNotifiers
    for (final notifier in _sampleVolumeNotifiers.values) {
      notifier.dispose();
    }
    for (final notifier in _samplePitchNotifiers.values) {
      notifier.dispose();
    }
    for (final notifier in _cellVolumeNotifiers.values) {
      notifier.dispose();
    }
    for (final notifier in _cellPitchNotifiers.values) {
      notifier.dispose();
    }
    _currentStepNotifier.dispose();
    _isSequencerPlayingNotifier.dispose();
    
    // Cancel all timers
    _autosaveTimer?.cancel();
    _debounceTimer?.cancel();
    _sequencerTimer?.cancel();
    _notificationBatchTimer?.cancel(); // 🎯 PERFORMANCE: Cancel batch timer
    _previewTimer?.cancel();
    _undoDebounceTimer?.cancel();
    _nativePitchDebounceTimer?.cancel();
    _nativeVolumeDebounceTimer?.cancel();
    
    if (_isRecording) {
      stopRecording();
    }
    _sequencerLibrary.cleanup();
    super.dispose();
  }

  int get currentSectionIndex => _currentSectionIndex;
  bool get isSectionControlOverlayOpen => _isSectionControlOverlayOpen;
  bool get isSectionCreationOverlayOpen => _isSectionCreationOverlayOpen;
  SectionPlaybackMode get sectionPlaybackMode => _sectionPlaybackMode;

  // Section management methods
  int getSectionLoopCount(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sectionLoopCounts.length) {
      return 1; // Default loop count
    }
    return _sectionLoopCounts[sectionIndex];
  }

  // Get grid samples for a specific section and sound grid
  List<int?> getSectionGridSamples(int sectionIndex, {int gridIndex = 0}) {
    // For current section, return live data
    if (sectionIndex == _currentSectionIndex) {
      if (gridIndex < _soundGridSamples.length) {
        return List<int?>.from(_soundGridSamples[gridIndex]);
      }
      return List.filled(_gridRows * _gridColumns, null);
    }
    
    // For other sections, return stored data
    if (_sectionGridData.containsKey(sectionIndex)) {
      final sectionData = _sectionGridData[sectionIndex]!;
      if (gridIndex < sectionData.length) {
        return List<int?>.from(sectionData[gridIndex]);
      }
    }
    
    // Return empty grid if section doesn't exist
    return List.filled(_gridRows * _gridColumns, null);
  }

  void setSectionLoopCount(int sectionIndex, int loopCount) {
    if (sectionIndex < 0 || loopCount < 1 || loopCount > 16) return;
    
    // Extend list if necessary
    while (_sectionLoopCounts.length <= sectionIndex) {
      _sectionLoopCounts.add(1);
    }
    
    _sectionLoopCounts[sectionIndex] = loopCount;
    _triggerAutosave();
    notifyListeners();
  }

  void toggleSectionControlOverlay() {
    if (_isSectionCreationOverlayOpen) {
      return;
    }
    _isSectionControlOverlayOpen = !_isSectionControlOverlayOpen;
    notifyListeners();
  }

  void closeSectionControlOverlay() {
    _isSectionControlOverlayOpen = false;
    notifyListeners();
  }

  void openSectionCreationOverlay() {
    _isSectionCreationOverlayOpen = true;
    notifyListeners();
  }

  void closeSectionCreationOverlay() {
    _isSectionCreationOverlayOpen = false;
    notifyListeners();
  }

  void toggleSectionPlaybackMode() {
    _sectionPlaybackMode = _sectionPlaybackMode == SectionPlaybackMode.loop 
        ? SectionPlaybackMode.song 
        : SectionPlaybackMode.loop;
    notifyListeners();
  }

  void switchToPreviousSection() {
    if (_currentSectionIndex > 0) {
      _switchToSection(_currentSectionIndex - 1);
    }
  }

  void switchToNextSection() {
    if (_currentSectionIndex < _numSections - 1) {
      _switchToSection(_currentSectionIndex + 1);
    }
  }

  // Core section switching logic as per documentation
  void _switchToSection(int newSectionIndex) {
    if (newSectionIndex < 0 || newSectionIndex >= _numSections) return;
    
    // 1. Save: Current grid data saved to _sectionGridData[current]
    _sectionGridData[_currentSectionIndex] = _soundGridSamples.map((grid) => List<int?>.from(grid)).toList();
    
    // 2. Update: _currentSectionIndex changed
    _currentSectionIndex = newSectionIndex;
    
    // 3. Load: New section's data loaded into _soundGridSamples
    if (_sectionGridData.containsKey(_currentSectionIndex)) {
      _soundGridSamples = _sectionGridData[_currentSectionIndex]!.map((grid) => List<int?>.from(grid)).toList();
    } else {
      // Initialize empty grid for new section
      final numGrids = _soundGridSamples.length;
      _soundGridSamples = List.generate(numGrids, (index) => 
          List.filled(_gridColumns * _gridRows, null));
      _sectionGridData[_currentSectionIndex] = _soundGridSamples.map((grid) => List<int?>.from(grid)).toList();
    }
    
    // 4. UI switch only: do not change native playback window during playback
    final bool isPlaying = _sequencerLibrary.isSequencerPlaying;
    if (!isPlaying) {
      _sequencerLibrary.setCurrentSection(_currentSectionIndex);
    }
    
    // Reset UI step indicator to section start
    _currentStep = 0;
    _currentStepNotifier.value = 0;
    
    // Reset legacy song mode counters (can be removed later)
    _currentSectionLoopCounter = 0;
    _lastAbsoluteStepForSongMode = -1;
    
    // Only sync when not playing (editing/view changes)
    if (!isPlaying) {
      _syncCurrentSectionToNative();
    }
    
         // 5. UI: Interface refreshes to show new section's content
    notifyListeners();
    print('🎵 [SECTION] Switched to section: ${_currentSectionIndex + 1}');
  }

  // Section creation methods as per documentation
  void createEmptySection() {
    // Save current section data
    _sectionGridData[_currentSectionIndex] = _soundGridSamples.map((grid) => List<int?>.from(grid)).toList();
    
    // Create new section with empty grids
    _numSections++;
    final newSectionIndex = _numSections - 1;
    
    // Extend loop counts list
    while (_sectionLoopCounts.length <= newSectionIndex) {
      _sectionLoopCounts.add(1); // Default 1 loop for new sections
    }
    
    // Update native section count
    _sequencerLibrary.setTotalSections(_numSections);
    
    // Auto-switch to newly created section
    _switchToSection(newSectionIndex);
    
    // Close creation overlay
    closeSectionCreationOverlay();
    
    print('🎵 [SECTION] Created empty section ${newSectionIndex + 1}');
  }

  void createSectionCopyFrom(int sourceSectionIndex) {
    if (sourceSectionIndex < 0 || sourceSectionIndex >= _numSections) return;
    
    // Save current section data
    _sectionGridData[_currentSectionIndex] = _soundGridSamples.map((grid) => List<int?>.from(grid)).toList();
    
    // Get source section data
    List<List<int?>> sourceData;
    if (sourceSectionIndex == _currentSectionIndex) {
      // Copy current visible data
      sourceData = _soundGridSamples.map((grid) => List<int?>.from(grid)).toList();
    } else {
      // Copy from stored data
      sourceData = _sectionGridData[sourceSectionIndex]?.map((grid) => List<int?>.from(grid)).toList() 
          ?? List.generate(_soundGridSamples.length, (index) => List.filled(_gridColumns * _gridRows, null));
    }
    
    // Create new section
    _numSections++;
    final newSectionIndex = _numSections - 1;
    
    // Extend loop counts list, inherit from source
    while (_sectionLoopCounts.length <= newSectionIndex) {
      _sectionLoopCounts.add(getSectionLoopCount(sourceSectionIndex)); // Inherit loop count
    }
    
    // Store copied data for new section
    _sectionGridData[newSectionIndex] = sourceData;
    
    // Update native section count
    _sequencerLibrary.setTotalSections(_numSections);
    
    // Auto-switch to newly created section
    _switchToSection(newSectionIndex);
    
    // Close creation overlay
    closeSectionCreationOverlay();
    
    print('🎵 [SECTION] Created section ${newSectionIndex + 1} copied from section ${sourceSectionIndex + 1}');
  }

  void _syncCurrentSectionToNative() {
    // Writes only the currently active section's data to native grid
    final sectionIndex = _currentSectionIndex;
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final gridSamples = _soundGridSamples[gridIndex];
      for (int row = 0; row < _gridRows; row++) {
        for (int col = 0; col < _gridColumns; col++) {
          final cellIndex = row * _gridColumns + col;
          final sampleSlot = gridSamples[cellIndex];
          final absoluteStep = sectionIndex * _gridRows + row;
          final absoluteColumn = gridIndex * _gridColumns + col;
          if (sampleSlot != null) {
            _sequencerLibrary.setGridCell(absoluteStep, absoluteColumn, sampleSlot);
          }
          // Do NOT clear null cells here; native holds the full table across sections.
          // Any deletions are applied at edit time; section switching should not trigger clears.
        }
      }
    }
    print('🔄 [SYNC] Synced current section ${sectionIndex + 1} to native');
  }

  // Song mode tracking
  int _currentSectionLoopCounter = 0; // How many loops completed in current section
  int _lastAbsoluteStepForSongMode = -1; // Track absolute step to detect wrap-around

  // Section loop getter for UI
  int get currentSectionLoopCounter => _currentSectionLoopCounter;
} 