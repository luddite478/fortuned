import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../sequencer_library.dart';
import '../services/audio_conversion_service.dart';
import 'patterns_state.dart';

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
  
  late final SequencerLibrary _sequencerLibrary;
  late final int _slotCount;

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
  int _currentStep = -1; // -1 means not playing, 0-15 for current step
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

  // Initialize sequencer
  SequencerState() {
    _sequencerLibrary = SequencerLibrary.instance;
    _initializeAudio();

    _slotCount = _sequencerLibrary.slotCount;
    _filePaths = List.filled(_slotCount, null);
    _fileNames = List.filled(_slotCount, null);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
    _soundGridSamples = []; // Will be initialized when sound grids are created
    _columnPlayingSample = List.filled(_gridColumns, null);
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
  String get formattedRecordingDuration => _sequencerLibrary.formattedOutputRecordingDuration;
  bool get isConverting => _isConverting;
  double get conversionProgress => _conversionProgress;
  String? get lastMp3Path => _lastMp3Path;
  String? get conversionError => _conversionError;
  List<Color> get bankColors => List.unmodifiable(_bankColors);
  bool get hasClipboardData => _hasClipboardData;
  int get slotCount => _slotCount;
  bool get isSelectingSample => _isSelectingSample;
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
      bool loadSuccess = _sequencerLibrary.loadSoundToSlot(0, tempPath, loadToMemory: true);
      if (loadSuccess) {
        _sequencerLibrary.reconfigureAudioSession();
        _sequencerLibrary.playSlot(0);
      }
    } catch (e) {
      print('❌ Error previewing sample: $e');
    }
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
        _sequencerLibrary.clearGridCell(row, absoluteColumn);
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
    if (_sequencerLibrary.isSequencerPlaying) return;
    
    // First, transfer current grid to sequencer
    _syncGridToSequencer();
    
    // Start sequencer with current BPM and grid size
    bool success = _sequencerLibrary.startSequencer(_bpm, _gridRows);
    if (success) {
      _isSequencerPlaying = true;
      // Start a timer just for UI updates (not audio timing)
      _startUIUpdateTimer();
    }
    notifyListeners();
  }
  
  void stopSequencer() {
    _sequencerLibrary.stopSequencer();
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
    _sequencerLibrary.clearAllGridCells();
    
    // Transfer ALL sound grids to sequencer as one horizontally concatenated table
    for (int gridIndex = 0; gridIndex < _soundGridSamples.length; gridIndex++) {
      final gridSamples = _soundGridSamples[gridIndex];
      for (int row = 0; row < _gridRows; row++) {
        for (int col = 0; col < _gridColumns; col++) {
          final cellIndex = row * _gridColumns + col;
          final sampleSlot = gridSamples[cellIndex];
          if (sampleSlot != null) {
            // Calculate absolute column index: gridIndex * columnsPerGrid + column
            final absoluteColumn = gridIndex * _gridColumns + col;
            _sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
          }
        }
      }
    }
  }
  
  void _startUIUpdateTimer() {
    // This timer is ONLY for UI updates, not audio timing
    // Audio timing is handled by sequencer in audio callback
    const uiUpdateIntervalMs = 50; // 20 FPS UI updates
    
    _sequencerTimer = Timer.periodic(Duration(milliseconds: uiUpdateIntervalMs), (timer) {
      if (!_sequencerLibrary.isSequencerPlaying) {
        timer.cancel();
        _sequencerTimer = null;
        return;
      }
      
      // Get current step from sequencer
      final currentStep = _sequencerLibrary.currentStep;
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
        _sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
      }
      _selectedGridCells.clear();
    } else {
      // Place sample in just this cell
      _setCurrentGridSample(cellIndex, sampleSlot);
      // Sync to sequencer using absolute column calculation
      final row = cellIndex ~/ _gridColumns;
      final col = cellIndex % _gridColumns;
      final absoluteColumn = _currentSoundGridIndex * _gridColumns + col;
      _sequencerLibrary.setGridCell(row, absoluteColumn, sampleSlot);
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
      
      // Get app's documents directory
      final directory = await getApplicationDocumentsDirectory();
      _currentRecordingPath = path.join(directory.path, filename);
      
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
  Future<Map<String, dynamic>> generateShareData(Pattern? pattern) async {
    final now = DateTime.now();
    final patternName = pattern?.name ?? 'Untitled Pattern';
    
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
        'id': pattern?.id,
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
    if (_sequencerLibrary.isSequencerPlaying) {
      _sequencerLibrary.setSequencerBpm(newBpm);
    }
    
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
    _soundGridOrder = List.generate(numGrids, (index) => index);
    _currentSoundGridIndex = _soundGridOrder.last; // Front sound grid
    
    // Initialize grid samples for each sound grid
    _soundGridSamples = List.generate(numGrids, (index) => 
        List.filled(_gridColumns * _gridRows, null));
    
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
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
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
    _sequencerLibrary.configureColumns(nativeTableColumns);
    
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

  @override
  void dispose() {
    _sequencerTimer?.cancel();
    if (_isRecording) {
      stopRecording();
    }
    _sequencerLibrary.cleanup();
    super.dispose();
  }
} 