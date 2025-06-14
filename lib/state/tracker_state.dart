import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../miniaudio_library.dart';
import '../screens/sample_browser_screen.dart';
import 'patterns_state.dart';

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

// Tracker state management - Complete tracker functionality
class TrackerState extends ChangeNotifier {
  static const int maxSlots = 8;
  
  late final MiniaudioLibrary _miniaudioLibrary;
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
  
  // Grid state - tracks which sample slot is assigned to each grid cell
  late List<int?> _gridSamples;
  
  // Grid selection state
  Set<int> _selectedGridCells = {};
  bool _isSelecting = false;
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

  // Initialize tracker
  TrackerState() {
    _miniaudioLibrary = MiniaudioLibrary.instance;
    _initializeAudio();

    _slotCount = _miniaudioLibrary.slotCount;
    _filePaths = List.filled(_slotCount, null);
    _fileNames = List.filled(_slotCount, null);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
    _gridSamples = List.filled(_gridColumns * _gridRows, null);
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
  List<int?> get gridSamples => List.unmodifiable(_gridSamples);
  Set<int> get selectedGridCells => Set.unmodifiable(_selectedGridCells);
  bool get isSelecting => _isSelecting;
  int get bpm => _bpm;
  int get currentStep => _currentStep;
  bool get isSequencerPlaying => _isSequencerPlaying;
  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  String? get lastRecordingPath => _lastRecordingPath;
  DateTime? get lastRecordingTime => _lastRecordingTime;
  String get formattedRecordingDuration => _miniaudioLibrary.formattedOutputRecordingDuration;
  List<Color> get bankColors => List.unmodifiable(_bankColors);
  bool get hasClipboardData => _hasClipboardData;
  int get slotCount => _slotCount;
  
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
    bool success = _miniaudioLibrary.initialize();
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SampleBrowserScreen(
          slotIndex: slot,
          onSampleSelected: (String path, String name) async {
            try {
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
              notifyListeners();
              
              // Always load sample to memory immediately
              loadSlot(slot);
              
            } catch (e) {
              print('❌ Error loading sample: $e');
            }
          },
        ),
      ),
    );
  }

  void loadSlot(int slot) {
    final path = _filePaths[slot];
    if (path == null) return;
    bool success = _miniaudioLibrary.loadSoundToSlot(
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
    _miniaudioLibrary.reconfigureAudioSession();
    
    bool success = _miniaudioLibrary.playSlot(slot);
    if (success) {
      _slotPlaying[slot] = true;
      notifyListeners();
    }
  }

  void stopSlot(int slot) {
    _miniaudioLibrary.stopSlot(slot);
    _slotPlaying[slot] = false;
    notifyListeners();
  }

  void stopAll() {
    _miniaudioLibrary.stopAllSounds();
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
    _miniaudioLibrary.reconfigureAudioSession();

    // Then play all loaded slots
    _miniaudioLibrary.playAllLoadedSlots();

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
    if (_selectedGridCells.isNotEmpty) {
      // Clear all selections when pressing with active selection
      _selectedGridCells.clear();
      _selectionStartCell = null;
      _currentSelectionCell = null;
      notifyListeners();
      return;
    }

    // Single tap - select just this cell
    _selectedGridCells = {padIndex};
    _selectionStartCell = padIndex;
    _currentSelectionCell = padIndex;
    notifyListeners();
  }

  void handleGridCellSelection(int cellIndex, bool isInside) {
    if (!isInside) {
      _isSelecting = false;
      notifyListeners();
      return;
    }

    if (!_isSelecting) {
      // Start selection
      _isSelecting = true;
      _selectionStartCell = cellIndex;
      _currentSelectionCell = cellIndex;
      _selectedGridCells = {cellIndex};
    } else {
      // Update selection rectangle
      if (_currentSelectionCell != cellIndex && _selectionStartCell != null) {
        _currentSelectionCell = cellIndex;
        _updateRectangularSelection();
      }
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

    // Calculate rectangle bounds
    final minRow = startRow < currentRow ? startRow : currentRow;
    final maxRow = startRow > currentRow ? startRow : currentRow;
    final minCol = startCol < currentCol ? startCol : currentCol;
    final maxCol = startCol > currentCol ? startCol : currentCol;

    // Select all cells in the rectangle
    Set<int> newSelection = {};
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        final cellIndex = row * _gridColumns + col;
        newSelection.add(cellIndex);
      }
    }

    _selectedGridCells = newSelection;
  }

  // Drag & drop sample placement
  void placeSampleInGrid(int sampleSlot, int cellIndex) {
    if (_selectedGridCells.isNotEmpty) {
      // Place sample in all selected cells
      for (int selectedIndex in _selectedGridCells) {
        _gridSamples[selectedIndex] = sampleSlot;
      }
      _selectedGridCells.clear();
    } else {
      // Place sample in just this cell
      _gridSamples[cellIndex] = sampleSlot;
    }
    notifyListeners();
  }

  // Copy/paste/delete operations
  void copySelectedCells() {
    if (_selectedGridCells.isEmpty) return;

    _clipboard.clear();
    
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
      
      _clipboard[relativeIndex] = _gridSamples[cellIndex];
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
        if (targetIndex >= 0 && targetIndex < _gridSamples.length) {
          _gridSamples[targetIndex] = sampleSlot;
        }
      }
    }
    notifyListeners();
  }

  void deleteSelectedCells() {
    if (_selectedGridCells.isEmpty) return;

    for (int cellIndex in _selectedGridCells) {
      if (cellIndex >= 0 && cellIndex < _gridSamples.length) {
        _gridSamples[cellIndex] = null;
      }
    }
    // Clear selection after deletion
    _selectedGridCells.clear();
    _selectionStartCell = null;
    _currentSelectionCell = null;
    notifyListeners();
  }

  // Sequencer functionality
  void startSequencer() {
    if (_isSequencerPlaying) return;
    
    _isSequencerPlaying = true;
    _currentStep = 0;
    notifyListeners();
    
    _scheduleNextStep();
  }

  void stopSequencer() {
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
    for (int col = 0; col < _gridColumns; col++) {
      final cellIndex = _currentStep * _gridColumns + col;
      final cellSample = _gridSamples[cellIndex];
      
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
      
      bool success = _miniaudioLibrary.startOutputRecording(_currentRecordingPath!);
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
    
    bool success = _miniaudioLibrary.stopOutputRecording();
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
  int? getCellIndexFromPosition(Offset localPosition, BuildContext context) {
    // Calculate grid cell dimensions
    const crossAxisCount = 4;
    const crossAxisSpacing = 4.0;
    const mainAxisSpacing = 4.0;
    const childAspectRatio = 2.5;
    
    // Get the available space (subtract padding)
    final availableWidth = MediaQuery.of(context).size.width - 64; // 32 padding on each side
    
    // Calculate cell dimensions
    final cellWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;
    final cellHeight = cellWidth / childAspectRatio;
    
    // Calculate which cell was touched
    final column = (localPosition.dx / (cellWidth + crossAxisSpacing)).floor();
    final row = (localPosition.dy / (cellHeight + mainAxisSpacing)).floor();
    
    // Validate bounds
    if (column >= 0 && column < _gridColumns && row >= 0 && row < _gridRows) {
      return row * _gridColumns + column;
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
    List<String> gridVisualization = [];
    for (int row = 0; row < _gridRows; row++) {
      String rowString = '';
      for (int col = 0; col < _gridColumns; col++) {
        final cellIndex = row * _gridColumns + col;
        final sampleSlot = _gridSamples[cellIndex];
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
    int placedSamples = _gridSamples.where((sample) => sample != null).length;
    
    // Build human-readable text
    String shareText = '''🎵 NIYYA TRACKER PATTERN 🎵

Pattern: $patternName
BPM: $_bpm
Grid: ${_gridColumns}x${_gridRows}
Samples: $loadedSamples loaded, $placedSamples placed
Created: ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}

🎼 SAMPLES:
${sampleInfo.isEmpty ? 'No samples loaded' : sampleInfo.map((s) => '${s['slot']}: ${s['name']} ${s['loaded'] ? '✓' : '⏳'}').join('\n')}

🎹 PATTERN:
${gridVisualization.join('\n')}

Made with NIYYA Tracker 🚀
#NiyyaTracker #MusicProduction #Beats''';

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
          'samples': _gridSamples,
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
        'name': 'NIYYA Tracker',
        'version': '1.0.0',
      }
    };
    
    return {
      'text': shareText,
      'subject': 'NIYYA Tracker Pattern: $patternName',
      'data': structuredData,
      'hashtags': ['#NiyyaTracker', '#MusicProduction', '#Beats', '#Pattern'],
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
          text: 'Check out this beat I made with NIYYA Tracker! 🎵\n\n#NiyyaTracker #BeatMaking #MusicProduction',
          subject: 'NIYYA Tracker Recording - $fileName',
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
    notifyListeners();
  }

  @override
  void dispose() {
    _sequencerTimer?.cancel();
    if (_isRecording) {
      stopRecording();
    }
    _miniaudioLibrary.cleanup();
    super.dispose();
  }
} 