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
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../sequencer_library.dart';
import '../services/audio_conversion_service.dart';
import 'threads_state.dart';
import '../services/threads_service.dart';
// import 'patterns_state.dart';

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

// Sequencer state management - Complete sequencer functionality
class SequencerState extends ChangeNotifier {
  static const int maxSlots = 8;
  
  SequencerLibrary? _sequencerLibrary;
  late final int _slotCount;

  // Lazy getter for sequencer library - initializes on first access
  SequencerLibrary get sequencerLibrary {
    if (_sequencerLibrary == null) {
      try {
        _sequencerLibrary = SequencerLibrary.instance;
        print('✅ SequencerLibrary loaded successfully');
        
        // Initialize the audio engine immediately after loading
        bool initSuccess = _sequencerLibrary!.initialize();
        if (initSuccess) {
          print('✅ Audio engine initialized successfully');
        } else {
          print('❌ Failed to initialize audio engine');
        }
      } catch (e) {
        print('❌ Failed to load SequencerLibrary: $e');
        // Return a mock instance that won't crash the app
        rethrow;
      }
    }
    return _sequencerLibrary!;
  }

  // Audio state
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  // UI state
  int _activeBank = 0;
  int? _activePad;
  int? _selectedSampleSlot; // Track which sample is selected for placement
  
  // Grid configuration
  int _gridColumns = 4;
  int _gridRows = 16;
  
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
  int _bpm = 120;
  int _currentStep = 0; // -1 means not playing, 0-15 for current step
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
  ];

  // Track double-tap timing
  DateTime? _lastTapTime;
  int? _lastTappedCell;
  static const Duration _doubleTapThreshold = Duration(milliseconds: 300);

  // Sound Grid stack state
  int _currentSoundGridIndex = 0;
  List<int> _soundGridOrder = []; // Order of sound grids from back to front (initialized dynamically)

  // Sample selection state
  bool _isSelectingSample = false;
  int? _sampleSelectionSlot;
  List<String> _currentSamplePath = [];
  List<SampleBrowserItem> _currentSampleItems = [];

  // Share widget state
  bool _isShowingShareWidget = false;
  List<String> _localRecordings = []; // List of local recording file paths

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

  // Initialize sequencer
  SequencerState() {
    // Don't initialize FFI library immediately to prevent startup hangs
    // sequencerLibrary will be initialized lazily when first accessed
    
    _slotCount = 1024; // Default slot count, will be updated when library loads
    _filePaths = List.filled(_slotCount, null);
    _fileNames = List.filled(_slotCount, null);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
    _soundGridSamples = []; // Will be initialized when sound grids are created
    _columnPlayingSample = List.filled(_gridColumns, null);
    
    // Start autosave timer
    _startAutosave();
    
    // Load saved state on initialization (unless disabled for testing)
    if (!_clearSavedDataOnInit) {
      _loadAutosavedState();
    } else {
      debugPrint('�� Skipping autosaved state loading (clearSavedDataOnInit = true)');
      // Optionally clear any existing saved data
      clearAutosavedState();
    }
    
    // Load saved recordings
    _loadSavedRecordings();
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
    
    // Create the scene with metadata
    final scene = SequencerScene(
      layers: layers,
      metadata: SceneMetadata(
        user: _threadsState?.currentUserId ?? 'unknown',
        createdAt: now,
        bpm: _bpm,
        key: 'C Major', // Default for now, could be enhanced
        timeSignature: '4/4', // Default for now
      ),
    );
    
    // Create the audio source
    final audioSource = AudioSource(
      scenes: [scene],
      samples: samples,
    );
    
        // Create the full audio structure
    final audio = ProjectAudio(
      format: 'mp3',
      duration: 0.0, // Could calculate based on BPM and pattern length
      sampleRate: 44100,
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
      if (source.scenes.isEmpty) return;
      
      final scene = source.scenes.first;
      
      // Apply BPM from metadata
      _bpm = scene.metadata.bpm;
      
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
      for (int layerIndex = 0; layerIndex < scene.layers.length; layerIndex++) {
        final layer = scene.layers[layerIndex];
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
  String get formattedRecordingDuration => sequencerLibrary.formattedOutputRecordingDuration;
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
  bool get isSelectingSample => _isSelectingSample;
  bool get isShowingShareWidget => _isShowingShareWidget;
  List<String> get localRecordings => List.unmodifiable(_localRecordings);
  int? get sampleSelectionSlot => _sampleSelectionSlot;
  List<String> get currentSamplePath => List.unmodifiable(_currentSamplePath);
  List<SampleBrowserItem> get currentSampleItems => List.unmodifiable(_currentSampleItems);
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
    bool success = sequencerLibrary.initialize();
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

  Future<void> pickFileForSlot(int slot, BuildContext context) async {
    _isSelectingSample = true;
    _sampleSelectionSlot = slot;
    _currentSamplePath.clear();
    await _loadSamples();
    notifyListeners();
  }

  void cancelSampleSelection() {
    _isSelectingSample = false;
    _sampleSelectionSlot = null;
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
    if (_sampleSelectionSlot == null) return;
    
    try {
      String finalPath = path;
      
      // Check if this is a bundled asset path (starts with "samples/")
      if (path.startsWith('samples/')) {
        print('🎵 Loading bundled asset: $path');
        finalPath = await _copyAssetToTemp(path, name);
        print('📁 Copied to temp file: $finalPath');
      }
      
      _filePaths[_sampleSelectionSlot!] = finalPath;
      _fileNames[_sampleSelectionSlot!] = name;
      _slotLoaded[_sampleSelectionSlot!] = false;
      
      // Always load sample to memory immediately
      loadSlot(_sampleSelectionSlot!);
      
      // Close sample selection
      cancelSampleSelection();
      
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
      // Stop any currently playing sounds first
      stopAll();
      
      // Copy asset to temp file for preview
      final fileName = path.basename(assetPath);
      final tempPath = await _copyAssetToTemp(assetPath, fileName);
      
      // Load and play the preview sample in slot 0 temporarily
      bool loadSuccess = sequencerLibrary.loadSoundToSlot(0, tempPath, loadToMemory: true);
      if (loadSuccess) {
        sequencerLibrary.reconfigureAudioSession();
        sequencerLibrary.playSlot(0);
      }
    } catch (e) {
      print('❌ Error previewing sample: $e');
    }
  }

  void loadSlot(int slot) {
    final path = _filePaths[slot];
    if (path == null) return;
    bool success = sequencerLibrary.loadSoundToSlot(
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
    sequencerLibrary.reconfigureAudioSession();
    
    bool success = sequencerLibrary.playSlot(slot);
    if (success) {
      _slotPlaying[slot] = true;
      notifyListeners();
    }
  }

  void stopSlot(int slot) {
    sequencerLibrary.stopSlot(slot);
    _slotPlaying[slot] = false;
    notifyListeners();
  }

  void stopAll() {
    sequencerLibrary.stopAllSounds();
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
    sequencerLibrary.reconfigureAudioSession();

    // Then play all loaded slots
    sequencerLibrary.playAllLoadedSlots();

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
    
    if (!hasFile) {
      // Empty slot - open sample browser
      pickFileForSlot(bankIndex, context);
    } else {
      // Loaded slot - just update active bank for status display
      _activeBank = bankIndex;
      notifyListeners();
    }
  }

  void handlePadPress(int padIndex) {
    // Ignore tap events if user is currently dragging
    if (_isDragging) {
      return;
    }
    
    final now = DateTime.now();
    
    // Check for double-tap
    if (_lastTapTime != null && 
        _lastTappedCell == padIndex &&
        now.difference(_lastTapTime!) <= _doubleTapThreshold) {
      // Double-tap detected - clear all selections and exit selection mode
      _clearAllSelections();
      _lastTapTime = null;
      _lastTappedCell = null;
      return;
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
      }
    } else {
      // In selection mode
      if (_selectedGridCells.isEmpty) {
        // No cells selected - select the tapped cell
        _selectedGridCells.add(padIndex);
        _selectionStartCell = padIndex;
        _currentSelectionCell = padIndex;
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
      }
    }
    notifyListeners();
  }

  void deleteSelectedCells() {
    if (_selectedGridCells.isEmpty) return;

    final currentGrid = _getCurrentGridSamples();
    for (int cellIndex in _selectedGridCells) {
      if (cellIndex >= 0 && cellIndex < currentGrid.length) {
        _setCurrentGridSample(cellIndex, null);
        // Sync deletion to native sequencer using absolute column calculation
        final row = cellIndex ~/ _gridColumns;
        final col = cellIndex % _gridColumns;
        final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
        sequencerLibrary.clearGridCell(row, absoluteColumn);
      }
    }
    // Clear selection after deletion
    _selectedGridCells.clear();
    _selectionStartCell = null;
    _currentSelectionCell = null;
    notifyListeners();
  }

  // Sequencer functionality with sample-accurate timing
  void startSequencer() {
    if (sequencerLibrary.isSequencerPlaying) return;
    
    // First, transfer current grid to sequencer
    _syncGridToSequencer();
    
    // Start sequencer with current BPM and grid size
    bool success = sequencerLibrary.startSequencer(_bpm, _gridRows);
    if (success) {
      _isSequencerPlaying = true;
      // Start a timer just for UI updates (not audio timing)
      _startUIUpdateTimer();
    }
    notifyListeners();
  }
  
  void stopSequencer() {
    sequencerLibrary.stopSequencer();
    _isSequencerPlaying = false;
    _currentStep = -1;
    
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    
    // Reset column tracking
    for (int i = 0; i < _gridColumns; i++) {
      _columnPlayingSample[i] = null;
    }
    notifyListeners();
  }
  
  void _syncGridToSequencer() {
    // Clear sequencer grid first
    sequencerLibrary.clearAllGridCells();
    print('🔄 [SYNC] Cleared all native sequencer cells');
    
    // Transfer ALL sound grids to sequencer as one horizontally concatenated table
    int totalCellsSet = 0;
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final gridSamples = _soundGridSamples[gridIndex];
      int gridCellsSet = 0;
      
      for (int row = 0; row < _gridRows; row++) {
        for (int col = 0; col < _gridColumns; col++) {
          final cellIndex = row * _gridColumns + col;
          final sampleSlot = gridSamples[cellIndex];
          if (sampleSlot != null) {
            // Calculate absolute column index: gridIndex * columnsPerGrid + column
            final absoluteColumn = gridIndex * _gridColumns + col;
            sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
            gridCellsSet++;
            totalCellsSet++;
            print('🎹 [SYNC] Grid $gridIndex: Set [row:$row, col:$col] → native [row:$row, absoluteCol:$absoluteColumn] = sample $sampleSlot');
          }
        }
      }
      print('📊 [SYNC] Grid $gridIndex: Set $gridCellsSet cells');
    }
    print('✅ [SYNC] Total: Set $totalCellsSet cells across ${_soundGridSamples.length} grids');
  }
  
  void _startUIUpdateTimer() {
    // This timer is ONLY for UI updates, not audio timing
    // Audio timing is handled by sequencer in audio callback
    const uiUpdateIntervalMs = 50; // 20 FPS UI updates
    
    _sequencerTimer = Timer.periodic(Duration(milliseconds: uiUpdateIntervalMs), (timer) {
      if (!sequencerLibrary.isSequencerPlaying) {
        timer.cancel();
        _sequencerTimer = null;
        return;
      }
      
      // Get current step from sequencer
      final currentStep = sequencerLibrary.currentStep;
      if (currentStep != _currentStep) {
        _currentStep = currentStep;
        notifyListeners(); // Only update UI when step actually changes
      }
    });
  }
  
  // Update grid cell and sync to sequencer
  void placeSampleInGrid(int sampleSlot, int cellIndex) {
    if (_selectedGridCells.isNotEmpty) {
      // Place sample in all selected cells
      for (int selectedIndex in _selectedGridCells) {
        _setCurrentGridSample(selectedIndex, sampleSlot);
        // Sync to sequencer using absolute column calculation
        final row = selectedIndex ~/ _gridColumns;
        final col = selectedIndex % _gridColumns;
        final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
        sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
      }
      _selectedGridCells.clear();
    } else {
      // Place sample in just this cell
      _setCurrentGridSample(cellIndex, sampleSlot);
      // Sync to sequencer using absolute column calculation
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
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
      
      // Try multiple directory options for better Android compatibility
      String? directoryPath;
      try {
        // First try: Application documents directory
        final directory = await getApplicationDocumentsDirectory();
        directoryPath = directory.path;
        print('📁 Using app documents directory: $directoryPath');
      } catch (e) {
        print('⚠️ App documents directory failed: $e');
        try {
          // Fallback: External storage directory (more reliable on Android)
          final directory = await getExternalStorageDirectory();
          if (directory != null) {
            directoryPath = directory.path;
            print('📁 Using external storage directory: $directoryPath');
          }
        } catch (e2) {
          print('⚠️ External storage directory failed: $e2');
          // Last fallback: Use temporary directory
          final directory = await getTemporaryDirectory();
          directoryPath = directory.path;
          print('📁 Using temporary directory: $directoryPath');
        }
      }
      
      if (directoryPath == null) {
        throw Exception('Could not find any suitable directory for recording');
      }
      
      _currentRecordingPath = path.join(directoryPath, filename);
      
      bool success = sequencerLibrary.startOutputRecording(_currentRecordingPath!);
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
    
    bool success = sequencerLibrary.stopOutputRecording();
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
                  text: 'Check out this beat I made with NIYYA! 🎵\n\nFormat: $fileType (${_formatFileSize(fileSize)})\n\n#NiyyaSequencer #BeatMaking #MusicProduction',
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

  // 🧪 TEST METHOD: Easy way to test native sequencer
  void testNativeSequencer() {
    print('🧪 Testing Native Sequencer...');
    
    // Stop any current sequencer
    if (_isSequencerPlaying) {
      stopSequencer();
    }
    
    // Make sure we have some loaded samples to test with
    bool hasLoadedSamples = false;
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        hasLoadedSamples = true;
        break;
      }
    }
    
    if (!hasLoadedSamples) {
      print('❌ No samples loaded - load some samples first to test sequencer');
      return;
    }
    
    // Create a simple test pattern
    print('🎵 Creating test pattern...');
    
    // Clear current grid
    final currentGrid = _getCurrentGridSamples();
    for (int i = 0; i < currentGrid.length; i++) {
      _setCurrentGridSample(i, null);
    }
    
    // Add a simple pattern using the first loaded sample
    int? firstLoadedSlot;
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        firstLoadedSlot = i;
        break;
      }
    }
    
    if (firstLoadedSlot != null) {
      // Create a simple kick pattern on steps 1, 5, 9, 13 (every 4 steps)
      for (int step = 0; step < 16; step += 4) {
        final cellIndex = step * _gridColumns + 0; // First column
        _setCurrentGridSample(cellIndex, firstLoadedSlot);
      }
      
      // If we have a second loaded sample, add it on off-beats
      int? secondLoadedSlot;
      for (int i = firstLoadedSlot + 1; i < _slotCount; i++) {
        if (_slotLoaded[i]) {
          secondLoadedSlot = i;
          break;
        }
      }
      
      if (secondLoadedSlot != null) {
        // Add second sample on steps 2, 6, 10, 14
        for (int step = 2; step < 16; step += 4) {
          final cellIndex = step * _gridColumns + 1; // Second column
          _setCurrentGridSample(cellIndex, secondLoadedSlot);
        }
      }
      
      print('🎹 Test pattern created with samples $firstLoadedSlot${secondLoadedSlot != null ? ' and $secondLoadedSlot' : ''}');
      
      // Now start the sequencer
      print('🚀 Starting sequencer at ${_bpm} BPM...');
      startSequencer();
      
      print('✅ Sequencer test started! You should hear the pattern playing.');
      print('   Call testStopSequencer() to stop it.');
    }
  }
  
  // 🧪 TEST METHOD: Stop the sequencer test
  void testStopSequencer() {
    print('⏹️ Stopping sequencer test...');
    stopSequencer();
    print('✅ Sequencer stopped.');
  }

  // Update BPM and sync with native sequencer
  void setBpm(int newBpm) {
    if (newBpm < 60 || newBpm > 300) return;
    
    _bpm = newBpm;
    
    // Update sequencer BPM if it's running
    if (sequencerLibrary.isSequencerPlaying) {
      sequencerLibrary.setSequencerBpm(newBpm);
    }
    
    // Trigger autosave when BPM changes
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
    sequencerLibrary.configureColumns(nativeTableColumns);
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

  // Helper method to set sample in current sound grid
  void _setCurrentGridSample(int index, int? value) {
    if (_soundGridSamples.isNotEmpty && _currentSoundGridIndex < _soundGridSamples.length) {
      _soundGridSamples[_currentSoundGridIndex][index] = value;
      
      // 🔧 FIX: Immediately sync this change to native sequencer if sequencer is running
      _syncSingleCellToNative(index, value);
      
      // Trigger autosave when grid changes
      _triggerAutosave();
    }
  }

  // 🔧 NEW: Sync a single cell change to native sequencer immediately
  void _syncSingleCellToNative(int cellIndex, int? sampleSlot) {
    // Calculate row and column from cell index
    final row = cellIndex ~/ _gridColumns;
    final col = cellIndex % _gridColumns;
    
    // Calculate absolute column: gridIndex * columnsPerGrid + localColumn
    final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
    
    if (sampleSlot != null) {
      sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
      print('🎹 [SYNC] Set cell [grid:$_currentSoundGridIndex, row:$row, col:$col] → native [row:$row, absoluteCol:$absoluteColumn] = sample $sampleSlot');
    } else {
      sequencerLibrary.clearGridCell(row, absoluteColumn);
      print('🗑️ [SYNC] Cleared cell [grid:$_currentSoundGridIndex, row:$row, col:$col] → native [row:$row, absoluteCol:$absoluteColumn]');
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
    final newGridIndex = _soundGridSamples.length;
    
    // Add new empty grid
    _soundGridSamples.add(List.filled(_gridColumns * _gridRows, null));
    _soundGridOrder.add(newGridIndex);
    
    // Reconfigure native columns
    final nativeTableColumns = numSoundGrids * _gridColumns;
    sequencerLibrary.configureColumns(nativeTableColumns);
    
    print('➕ Added sound grid $newGridIndex (total: $numSoundGrids grids = $nativeTableColumns native columns)');
    notifyListeners();
  }

  void removeSoundGrid() {
    if (_soundGridSamples.length <= 1) {
      print('❌ Cannot remove grid - minimum 1 grid required');
      return;
    }
    
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
    sequencerLibrary.configureColumns(nativeTableColumns);
    
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
      _bpm = state['bpm'] ?? 120;
      _gridColumns = state['gridColumns'] ?? 4;
      _gridRows = state['gridRows'] ?? 16;
      _currentSoundGridIndex = state['currentSoundGridIndex'] ?? 0;
      _activeBank = state['activeBank'] ?? 0;
      
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
    
    // Clear all current state
    _clearAllSampleSlots();
    clearAllCells();
    
    // Reset to defaults
    _bpm = 120;
    _currentStep = -1;
    _isSequencerPlaying = false;
    _activeBank = 0;
    _currentSoundGridIndex = 0;
    _selectedGridCells.clear();
    _isSelecting = false;
    _isInSelectionMode = false;
    _isDragging = false;
    
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

  /// Show/hide share widget
  void setShowShareWidget(bool show) {
    _isShowingShareWidget = show;
    notifyListeners();
  }

  /// Add a recording to local storage
  void _addLocalRecording(String filePath) {
    _localRecordings.add(filePath);
    _saveRecordingsList();
    notifyListeners();
  }

  /// Save recordings list to SharedPreferences
  Future<void> _saveRecordingsList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('local_recordings', _localRecordings);
    } catch (e) {
      debugPrint('❌ Error saving recordings list: $e');
    }
  }

  /// Load recordings list from SharedPreferences
  Future<void> _loadSavedRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRecordings = prefs.getStringList('local_recordings') ?? [];
      
      // Filter out recordings that no longer exist on disk
      _localRecordings.clear();
      for (final recordingPath in savedRecordings) {
        final file = File(recordingPath);
        if (await file.exists()) {
          _localRecordings.add(recordingPath);
        }
      }
      
      // Update saved list to remove non-existent files
      if (_localRecordings.length != savedRecordings.length) {
        await _saveRecordingsList();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading saved recordings: $e');
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
      final checkpoint = {
        'id': 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
        'user_id': _threadsState?.currentUserId ?? 'unknown_user',
        'user_name': _threadsState?.currentUserName ?? 'Unknown User',
        'timestamp': DateTime.now().toIso8601String(),
        'comment': description ?? 'Published from mobile app',
        'renders': [],
        'snapshot': {
          'id': snapshot.id,
          'name': snapshot.name,
          'createdAt': snapshot.createdAt.toIso8601String(),
          'version': snapshot.version,
          'audio': {
            'sources': snapshot.audio.sources.map((source) => {
              'scenes': source.scenes.map((scene) => {
                'layers': scene.layers.map((layer) => {
                  'id': layer.id,
                  'index': layer.index,
                  'rows': layer.rows.map((row) => {
                    'cells': row.cells.map((cell) => {
                      'sample': cell.sample?.hasSample == true ? {
                        'sample_id': cell.sample!.sampleId,
                        'sample_name': cell.sample!.sampleName,
                      } : null,
                    }).toList(),
                  }).toList(),
                }).toList(),
                'metadata': {
                  'user': scene.metadata.user,
                  'bpm': scene.metadata.bpm,
                  'key': scene.metadata.key,
                  'time_signature': scene.metadata.timeSignature,
                  'created_at': scene.metadata.createdAt.toIso8601String(),
                },
              }).toList(),
              'samples': source.samples.map((sample) => {
                'id': sample.id,
                'name': sample.name,
                'url': sample.url,
                'is_public': sample.isPublic,
              }).toList(),
            }).toList(),
          },
        },
      };
      
      // Prepare update data
      final updateData = <String, dynamic>{
        'metadata': {
          'is_public': isPublic,
          'tags': tags ?? ['mobile', 'sequencer'],
          'description': description ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        'checkpoint': checkpoint,
      };

      // Send update to server
      final serverIp = dotenv.env['SERVER_IP'] ?? 'localhost';
      final apiToken = dotenv.env['API_TOKEN'] ?? '';
      final url = 'http://$serverIp:8888/api/v1/threads/$threadId';
      
      debugPrint('🌐 Updating thread at URL: $url');
      debugPrint('📝 Making thread public: $isPublic');
      debugPrint('🆔 Thread ID: $threadId');
      
      // Add token to the data
      updateData['token'] = apiToken;
      
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updateData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Successfully updated thread to public (status: ${response.statusCode})');
        
        // Update local ThreadsState with the new checkpoint
        if (_threadsState != null) {
          try {
            debugPrint('📝 Adding checkpoint to local ThreadsState...');
            // Add the checkpoint to the local thread state
            await _threadsState!.addCheckpoint(
              threadId: threadId,
              userId: checkpoint['user_id'] as String,
              userName: checkpoint['user_name'] as String,
              comment: checkpoint['comment'] as String,
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
      
      // Always create a new public thread with current sequencer state
      // This ignores any local thread logic and just publishes what's currently in the sequencer
      
      // Create a snapshot of current state
      final snapshot = createSnapshot(name: projectTitle, comment: description);
      
      // Prepare data for database (matches init_collections.py structure)
      final threadData = {
        'id': 'thread_${DateTime.now().millisecondsSinceEpoch}',
        'title': projectTitle,
        'users': [
          {
            'id': _threadsState?.currentUserId ?? 'unknown_user',
            'name': _threadsState?.currentUserName ?? 'Unknown User',
            'joined_at': DateTime.now().toIso8601String(),
          }
        ],
        'initial_checkpoint': {
          'id': 'checkpoint_${DateTime.now().millisecondsSinceEpoch}',
          'user_id': _threadsState?.currentUserId ?? 'unknown_user',
          'user_name': _threadsState?.currentUserName ?? 'Unknown User',
          'timestamp': DateTime.now().toIso8601String(),
          'comment': description ?? 'Published from mobile app',
          'renders': [], // Will be populated after audio rendering
          'snapshot': {
            'id': snapshot.id,
            'name': snapshot.name,
            'createdAt': snapshot.createdAt.toIso8601String(),
            'version': snapshot.version,
            'audio': {
              'sources': snapshot.audio.sources.map((source) => {
                'scenes': source.scenes.map((scene) => {
                  'layers': scene.layers.map((layer) => {
                    'id': layer.id,
                    'index': layer.index,
                    'rows': layer.rows.map((row) => {
                      'cells': row.cells.map((cell) => {
                        'sample': cell.sample?.hasSample == true ? {
                          'sample_id': cell.sample!.sampleId,
                          'sample_name': cell.sample!.sampleName,
                        } : null,
                      }).toList(),
                    }).toList(),
                  }).toList(),
                  'metadata': {
                    'user': scene.metadata.user,
                    'bpm': scene.metadata.bpm,
                    'key': scene.metadata.key,
                    'time_signature': scene.metadata.timeSignature,
                    'created_at': scene.metadata.createdAt.toIso8601String(),
                  },
                }).toList(),
                'samples': source.samples.map((sample) => {
                  'id': sample.id,
                  'name': sample.name,
                  'url': sample.url,
                  'is_public': sample.isPublic,
                }).toList(),
              }).toList(),
            },
          },
        },
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'metadata': {
          'original_project_id': null,
          'project_type': 'solo',
          'genre': 'Electronic', // Could be enhanced to be user-selectable
          'tags': tags ?? ['mobile', 'sequencer'],
          'description': description ?? '',
          'is_public': isPublic,
          'plays_num': 0,
          'likes_num': 0,
          'forks_num': 0,
        },
      };

      // Send to database using environment variables
      final serverIp = dotenv.env['SERVER_IP'] ?? 'localhost';
      final apiToken = dotenv.env['API_TOKEN'] ?? '';
      final url = 'http://$serverIp:8888/api/v1/threads';
      
      debugPrint('🌐 Publishing to URL: $url');
      debugPrint('🔑 Using API token: $apiToken');
      debugPrint('🏠 SERVER_IP from env: $serverIp');
      debugPrint('🔍 ThreadsState reference: $_threadsState');
      debugPrint('🔍 ThreadsState currentUserId: ${_threadsState?.currentUserId}');
      debugPrint('🔍 ThreadsState currentUserName: ${_threadsState?.currentUserName}');
      debugPrint('👤 Publishing with user ID: ${_threadsState?.currentUserId ?? 'unknown_user'}');
      debugPrint('👤 Publishing with user name: ${_threadsState?.currentUserName ?? 'Unknown User'}');
      
      // Add token to the data
      threadData['token'] = apiToken;
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(threadData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Successfully published sequencer state to database');
        
        // Parse server response to get the new thread ID
        final responseData = jsonDecode(response.body);
        final newThreadId = responseData['thread_id'] as String?;
        
        // Update local ThreadsState with the new thread from server
        if (_threadsState != null && newThreadId != null) {
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
              debugPrint('✅ Refreshed all threads after publish');
            }
          } catch (e) {
            debugPrint('⚠️ Failed to update local ThreadsState: $e');
            // Continue anyway - the server creation was successful
          }
        }
        
        // Clear autosaved state since it's now published
        await clearAutosavedState();
        
        return true;
      } else {
        debugPrint('❌ Failed to publish to database: ${response.statusCode} - ${response.body}');
        return false;
      }
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
      ThreadCheckpoint? checkpointToLoad;
      
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
      ThreadCheckpoint? checkpointToLoad;
      
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
        debugPrint('🔍 Source has ${source.samples.length} samples and ${source.scenes.length} scenes');
        
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
        if (source.scenes.isNotEmpty) {
          final scene = source.scenes.first;
          debugPrint('🔍 Scene has ${scene.layers.length} layers');
          
          // Update BPM if available
          if (scene.metadata.bpm > 0) {
            _bpm = scene.metadata.bpm;
            debugPrint('🎵 Set BPM to ${_bpm}');
          }
          
          // Load grid patterns
          if (scene.layers.isNotEmpty) {
            // Clear existing sound grids and create new ones for each layer
            _soundGridSamples.clear();
            _soundGridOrder.clear();
            _soundGridLabels.clear();
            
            for (int layerIndex = 0; layerIndex < scene.layers.length; layerIndex++) {
              final layer = scene.layers[layerIndex];
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
    dynamic chatClient, // Add ChatClient parameter
  }) async {
    if (!_isCollaborating || _sourceThread == null) {
      debugPrint('❌ Not in collaboration mode');
      return false;
    }

    try {
      // Create snapshot of current state
      final snapshot = createSnapshot(
        name: _sourceThread!.title,
        comment: comment,
      );

      // Use provided user info or fallback
      final userId = currentUserId ?? _threadsState?.currentUserId ?? 'current_user_123';
      final userName = currentUserName ?? _threadsState?.currentUserName ?? 'Collaborator';

      // Get original author info
      final originalAuthor = _sourceThread!.users.first; // Assume first user is the author
      
      // Create a new thread (fork) with both users
      final forkTitle = '${_sourceThread!.title} (Fork)';
      
      if (_threadsState != null) {
        try {
          // Create new thread with both users
          final forkThreadId = await _threadsState!.createThread(
            title: forkTitle,
            authorId: userId, // Current user is the author of the fork
            authorName: userName,
            collaboratorIds: [originalAuthor.id], // Add original author as collaborator
            collaboratorNames: [originalAuthor.name],
            initialSnapshot: snapshot, // Use current state as initial checkpoint
            metadata: {
              'project_type': 'fork',
              'is_public': true,
              'original_thread_id': _sourceThread!.id,
              'fork_comment': comment,
            },
            createInitialCheckpoint: true,
          );
          
          debugPrint('✅ Created fork thread: $forkThreadId');
          
          // Send thread message to original author via WebSocket
          try {
            if (chatClient != null) {
              final success = await chatClient.sendThreadMessage(
                originalAuthor.id,
                forkThreadId,
                forkTitle,
              );
              if (success) {
                debugPrint('📡 ✅ Sent WebSocket notification to ${originalAuthor.name} about fork: $forkTitle');
              } else {
                debugPrint('📡 ❌ Failed to send WebSocket notification to ${originalAuthor.name}');
              }
            } else {
              debugPrint('📡 ⚠️ No ChatClient provided - cannot send notification');
            }
          } catch (e) {
            debugPrint('⚠️ Failed to send WebSocket notification: $e');
            // Continue anyway - the fork was created successfully
          }
          
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

  /// Clear all loaded sample slots
  void _clearAllSampleSlots() {
    for (int i = 0; i < _slotCount; i++) {
      if (_slotLoaded[i]) {
        sequencerLibrary.unloadSlot(i);
        _slotLoaded[i] = false;
        _slotPlaying[i] = false;
        _filePaths[i] = null;
        _fileNames[i] = null;
      }
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _debounceTimer?.cancel();
    _sequencerTimer?.cancel();
    if (_isRecording) {
      stopRecording();
    }
    sequencerLibrary.cleanup();
    super.dispose();
  }
} 