import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'miniaudio_library.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'screens/contacts_screen.dart';
import 'screens/sample_browser_screen.dart';
import 'models/app_state.dart';
import 'services/app_state_service.dart';
import 'services/chat_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
    print('✅ Environment loaded: ${dotenv.env['ENVIRONMENT'] ?? 'development'}');
  } catch (e) {
    print('⚠️ Could not load .env file, using defaults: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Separate domain-specific providers
        ChangeNotifierProvider(create: (context) => EditorState()),
        ChangeNotifierProvider(create: (context) => ChatsState()),
        // AppStateService now depends on both states
        ProxyProvider2<EditorState, ChatsState, AppStateService>(
          update: (context, editorState, chatsState, previous) {
            // Dispose previous service if it exists
            previous?.dispose();
            return AppStateService(
              editorState: editorState,
              chatsState: chatsState,
              chatClient: ChatClient(),
            );
          },
          dispose: (context, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'Niyya Audio Tracker',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        home: const TrackerPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> with WidgetsBindingObserver {
  late final MiniaudioLibrary _miniaudioLibrary;
  late final int _slotCount;

  // Audio state (keeping original structure for now)
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  // UI state
  int _activeBank = 0;
  int? _activePad;
  int? _selectedSampleSlot; // Track which sample is selected for placement
  
  // Grid state - tracks which sample slot is assigned to each grid cell
  // 4 columns (sample slots) × 16 rows (steps) = 64 cells
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
  
  // Track which samples are currently playing in each column
  late List<int?> _columnPlayingSample; // Track which specific sample slot is playing in each column

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _miniaudioLibrary = MiniaudioLibrary.instance;
    _initializeAudio();

    _slotCount = _miniaudioLibrary.slotCount;
    _filePaths = List.filled(_slotCount, null);
    _fileNames = List.filled(_slotCount, null);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
    _gridSamples = List.filled(64, null);
    _columnPlayingSample = List.filled(4, null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Re-configure Bluetooth audio session when app becomes active
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed - reconfiguring Bluetooth audio session');
      _miniaudioLibrary.reconfigureAudioSession();
    }
  }

  Future<void> _initializeAudio() async {
    bool success = _miniaudioLibrary.initialize();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to initialize audio engine'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sequencerTimer?.cancel();
    _miniaudioLibrary.cleanup();
    super.dispose();
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

  Future<void> _pickFileForSlot(int slot) async {
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
              
              setState(() {
                _filePaths[slot] = finalPath;
                _fileNames[slot] = name;
                _slotLoaded[slot] = false;
              });
              
              // Always load sample to memory immediately
              _loadSlot(slot);
              
            } catch (e) {
              print('❌ Error loading sample: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error loading sample: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  void _loadSlot(int slot) {
    final path = _filePaths[slot];
    if (path == null) return;
    bool success = _miniaudioLibrary.loadSoundToSlot(
      slot,
      path,
      loadToMemory: true,
    );
    setState(() {
      _slotLoaded[slot] = success;
    });
  }

  void _playSlot(int slot) {
    // Sample should already be loaded in memory
    if (!_slotLoaded[slot]) {
      // If not loaded for some reason, try loading first
      _loadSlot(slot);
      if (!_slotLoaded[slot]) return; // Give up if loading failed
    }
    
    // Ensure Bluetooth audio routing is active before playback
    _miniaudioLibrary.reconfigureAudioSession();
    
    bool success = _miniaudioLibrary.playSlot(slot);
    if (success) {
      setState(() => _slotPlaying[slot] = true);
    }
  }

  void _stopSlot(int slot) {
    _miniaudioLibrary.stopSlot(slot);
    setState(() => _slotPlaying[slot] = false);
  }

  void _stopAll() {
    _miniaudioLibrary.stopAllSounds();
    setState(() {
      for (int i = 0; i < _slotCount; ++i) {
        _slotPlaying[i] = false;
      }
    });
  }

  void _playAll() {
    // First, ensure any slots with files are loaded
    for (int i = 0; i < _slotCount; i++) {
      if (_filePaths[i] != null && !_slotLoaded[i]) {
        _loadSlot(i);
      }
    }

    // Ensure Bluetooth audio routing is active before playback
    _miniaudioLibrary.reconfigureAudioSession();

    // Then play all loaded slots
    _miniaudioLibrary.playAllLoadedSlots();

    // Update UI state for all loaded slots
    setState(() {
      for (int i = 0; i < _slotCount; i++) {
        if (_slotLoaded[i]) {
          _slotPlaying[i] = true;
        }
      }
    });
  }

  void _handleBankChange(int bankIndex) {
    final hasFile = _fileNames[bankIndex] != null;
    
    if (!hasFile) {
      // Empty slot - open sample browser (use existing method)
      _pickFileForSlot(bankIndex);
    } else {
      // Loaded slot - just update active bank for status display
      // The actual dragging is handled by the Draggable widget
      setState(() {
        _activeBank = bankIndex;
      });
    }
  }

  void _handlePadPress(int padIndex) {
    if (_selectedGridCells.isNotEmpty) {
      // Clear all selections when pressing with active selection
      setState(() {
        _selectedGridCells.clear();
        _selectionStartCell = null;
        _currentSelectionCell = null;
      });
      return;
    }

    // Single tap - select just this cell
    setState(() {
      _selectedGridCells = {padIndex};
      _selectionStartCell = padIndex;
      _currentSelectionCell = padIndex;
    });
  }

  void _handleGridCellSelection(int cellIndex, bool isInside) {
    if (!isInside) {
      setState(() {
        _isSelecting = false;
      });
      return;
    }

    if (!_isSelecting) {
      // Start selection
      setState(() {
        _isSelecting = true;
        _selectionStartCell = cellIndex;
        _currentSelectionCell = cellIndex;
        _selectedGridCells = {cellIndex};
      });
    } else {
      // Update selection rectangle
      if (_currentSelectionCell != cellIndex && _selectionStartCell != null) {
        setState(() {
          _currentSelectionCell = cellIndex;
          _updateRectangularSelection();
        });
      }
    }
  }

  void _updateRectangularSelection() {
    if (_selectionStartCell == null || _currentSelectionCell == null) return;

    // Convert cell indices to row,col coordinates
    final startRow = _selectionStartCell! ~/ 4;
    final startCol = _selectionStartCell! % 4;
    final currentRow = _currentSelectionCell! ~/ 4;
    final currentCol = _currentSelectionCell! % 4;

    // Calculate rectangle bounds
    final minRow = startRow < currentRow ? startRow : currentRow;
    final maxRow = startRow > currentRow ? startRow : currentRow;
    final minCol = startCol < currentCol ? startCol : currentCol;
    final maxCol = startCol > currentCol ? startCol : currentCol;

    // Select all cells in the rectangle
    Set<int> newSelection = {};
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        final cellIndex = row * 4 + col;
        newSelection.add(cellIndex);
      }
    }

    _selectedGridCells = newSelection;
  }

  // Sequencer control methods
  void _startSequencer() {
    if (_isSequencerPlaying) return;
    
    setState(() {
      _isSequencerPlaying = true;
      _currentStep = 0;
    });
    
    _scheduleNextStep();
  }

  void _stopSequencer() {
    setState(() {
      _isSequencerPlaying = false;
      _currentStep = -1;
    });
    
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    
    // Stop all currently playing sounds
    _stopAll();
    
    // Reset column tracking
    for (int i = 0; i < 4; i++) {
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
        
        setState(() {
          _currentStep = (_currentStep + 1) % 16; // Loop back to 0 after 15
        });
        
        _scheduleNextStep();
      }
    });
  }

  void _playCurrentStep() {
    // Play all sounds on the current line simultaneously
    // Only stop sounds where there's a new sound in the same column
    for (int col = 0; col < 4; col++) {
      final cellIndex = _currentStep * 4 + col;
      final cellSample = _gridSamples[cellIndex];
      
      // Check if there's a sample in this cell on the current line
      if (cellSample != null && _slotLoaded[cellSample]) {
        // Stop previous sound in this column only if there was one playing
        if (_columnPlayingSample[col] != null) {
          // Stop only the specific sample that was playing in this column
          _stopSlot(_columnPlayingSample[col]!);
        }
        
        // Play the new sound (all sounds on this line will play simultaneously)
        _playSlot(cellSample);
        _columnPlayingSample[col] = cellSample; // Store the sample slot, not the cell index
      }
      // If there's no sample in this cell, do nothing - let previous sound continue
      // This allows sounds from previous steps to continue until replaced
    }
  }

  Widget _buildSampleBanks() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: List.generate(8, (bank) {
          final isActive = _activeBank == bank;
          final isSelected = _selectedSampleSlot == bank;
          final hasFile = _fileNames[bank] != null;
          final isPlaying = _slotPlaying[bank];
          
          Widget sampleButton = Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.yellowAccent.withOpacity(0.8) // Selected for placement
                  : isActive
                      ? Colors.white
                      : hasFile
                          ? _bankColors[bank].withOpacity(0.8)
                          : const Color(0xFF404040),
              borderRadius: BorderRadius.circular(6),
              border: isPlaying
                  ? Border.all(color: Colors.greenAccent, width: 2)
                  : isSelected
                      ? Border.all(color: Colors.yellowAccent, width: 2)
                      : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  String.fromCharCode(65 + bank), // A, B, C, etc.
                  style: TextStyle(
                    color: isSelected || isActive ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (hasFile) ...[
                  const SizedBox(height: 2),
                  Icon(
                    Icons.audiotrack,
                    size: 12,
                    color: isSelected || isActive ? Colors.black54 : Colors.white70,
                  ),
                ],
              ],
            ),
          );

          return Expanded(
            child: hasFile 
                ? Draggable<int>(
                    data: bank,
                    feedback: Container(
                      width: 40,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _bankColors[bank].withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            String.fromCharCode(65 + bank),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Icon(
                            Icons.audiotrack,
                            size: 12,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    childWhenDragging: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _bankColors[bank].withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey, width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            String.fromCharCode(65 + bank),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Icon(
                            Icons.audiotrack,
                            size: 12,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () => _handleBankChange(bank),
                      onLongPress: () => _pickFileForSlot(bank),
                      child: sampleButton,
                    ),
                  )
                : GestureDetector(
                    onTap: () => _handleBankChange(bank),
                    onLongPress: () => _pickFileForSlot(bank),
                    child: sampleButton,
                  ),
          );
        }),
      ),
    );
  }

  Widget _buildSampleGrid() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(12),
        ),
        child: GestureDetector(
          onPanStart: (details) {
            // Find which cell we started in
            final localPosition = details.localPosition;
            final cellIndex = _getCellIndexFromPosition(localPosition);
            if (cellIndex != null) {
              _handleGridCellSelection(cellIndex, true);
            }
          },
          onPanUpdate: (details) {
            // Find which cell we're currently over
            final localPosition = details.localPosition;
            final cellIndex = _getCellIndexFromPosition(localPosition);
            if (cellIndex != null) {
              _handleGridCellSelection(cellIndex, true);
            }
          },
          onPanEnd: (details) {
            setState(() {
              _isSelecting = false;
            });
          },
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, // 4 columns
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 2.5,
            ),
            itemCount: 64, // 4 columns × 16 rows
            itemBuilder: (context, index) {
              return _buildGridCell(index);
            },
          ),
        ),
      ),
    );
  }

  int? _getCellIndexFromPosition(Offset localPosition) {
    // Calculate grid cell dimensions
    const crossAxisCount = 4;
    const crossAxisSpacing = 4.0;
    const mainAxisSpacing = 4.0;
    const childAspectRatio = 2.5;
    
    // Get the available space (subtract padding)
    final availableWidth = MediaQuery.of(context).size.width - 64; // 32 padding on each side
    final availableHeight = 400.0; // Approximate grid height
    
    // Calculate cell dimensions
    final cellWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;
    final cellHeight = cellWidth / childAspectRatio;
    
    // Calculate which cell was touched
    final column = (localPosition.dx / (cellWidth + crossAxisSpacing)).floor();
    final row = (localPosition.dy / (cellHeight + mainAxisSpacing)).floor();
    
    // Validate bounds
    if (column >= 0 && column < 4 && row >= 0 && row < 16) {
      return row * 4 + column;
    }
    
    return null;
  }

  Widget _buildGridCell(int index) {
    final row = index ~/ 4;
    final col = index % 4;
    final isActivePad = _activePad == index;
    final isCurrentStep = _currentStep == row && _isSequencerPlaying;
    final placedSample = _gridSamples[index];
    final hasPlacedSample = placedSample != null;
    final isSelected = _selectedGridCells.contains(index);
    
    // Keep original colors for cells, selection only affects border
    Color cellColor;
    if (isActivePad) {
      cellColor = Colors.white;
    } else if (isCurrentStep) {
      cellColor = hasPlacedSample 
          ? _bankColors[placedSample!].withOpacity(0.8)
          : Colors.grey.withOpacity(0.6); // Highlight current step
    } else if (hasPlacedSample) {
      cellColor = _bankColors[placedSample!];
    } else {
      cellColor = const Color(0xFF404040); // Default gray for empty cells
    }
    
    return DragTarget<int>(
      onAccept: (int sampleSlot) {
        if (_selectedGridCells.isNotEmpty) {
          // Place sample in all selected cells
          setState(() {
            for (int selectedIndex in _selectedGridCells) {
              _gridSamples[selectedIndex] = sampleSlot;
            }
            _selectedGridCells.clear();
          });
        } else {
          // Place sample in just this cell
          setState(() {
            _gridSamples[index] = sampleSlot;
          });
        }
      },
      builder: (context, candidateData, rejectedData) {
        final bool isDragHovering = candidateData.isNotEmpty;
        
        return GestureDetector(
          onTap: () {
            if (_selectedGridCells.isNotEmpty && !_selectedGridCells.contains(index)) {
              // Clear all selections if tapping on unselected cell
              setState(() {
                _selectedGridCells.clear();
              });
            } else {
              // Normal tap behavior - always prioritize selection
              _handlePadPress(index);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: isDragHovering 
                  ? Colors.greenAccent.withOpacity(0.6)
                  : cellColor,
              borderRadius: BorderRadius.circular(4),
              border: isSelected 
                  ? Border.all(color: Colors.yellowAccent, width: 2)
                  : isCurrentStep 
                      ? Border.all(color: Colors.yellowAccent, width: 2)
                      : isDragHovering
                          ? Border.all(color: Colors.greenAccent, width: 2)
                          : hasPlacedSample && !isActivePad
                              ? Border.all(color: Colors.white24, width: 1)
                              : Border.all(color: Colors.transparent, width: 1),
              boxShadow: isSelected 
                  ? [
                      BoxShadow(
                        color: Colors.yellowAccent.withOpacity(0.3),
                        blurRadius: 4,
                        spreadRadius: 0,
                      )
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    hasPlacedSample 
                        ? String.fromCharCode(65 + placedSample!)
                        : '${row + 1}',
                    style: TextStyle(
                      color: (isActivePad || isDragHovering) ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  if (isSelected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.yellowAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'C-4',
                      style: TextStyle(
                        color: (isActivePad || isDragHovering)
                            ? Colors.black54
                            : Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusDisplay() {
    final hasFile = _fileNames[_activeBank] != null;
    final isPlaying = _slotPlaying[_activeBank];
    final totalMemoryUsage = _miniaudioLibrary.getTotalMemoryUsage();
    final memorySlotCount = _miniaudioLibrary.getMemorySlotCount();
    final activeSlotMemory = _miniaudioLibrary.getSlotMemoryUsage(_activeBank);
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BANK: ${String.fromCharCode(65 + _activeBank)}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              Text(
                'BPM: $_bpm',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STATUS: ${_isSequencerPlaying ? 'PLAYING' : 'STOPPED'}',
                style: TextStyle(
                  color: _isSequencerPlaying ? Colors.greenAccent : Colors.redAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              if (_isSequencerPlaying) ...[
                Text(
                  'STEP: ${_currentStep + 1}/16',
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          
          // Grid selection status
          if (_selectedGridCells.isNotEmpty) ...[
            Text(
              'SELECTED: ${_selectedGridCells.length} cell${_selectedGridCells.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'DRAG SAMPLE TO SELECTED CELLS OR TAP TO CLEAR',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          Text(
            'SAMPLE: ${hasFile ? _fileNames[_activeBank]! : 'NO FILE'}',
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Memory usage display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MEMORY: $memorySlotCount/8 slots',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
              Text(
                'TOTAL: ${_miniaudioLibrary.formatMemorySize(totalMemoryUsage)}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (hasFile) ...[
            const SizedBox(height: 4),
            Text(
              'SLOT SIZE: ${_miniaudioLibrary.formatMemorySize(activeSlotMemory)}',
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
          
          // Selected sample slot status
          if (_selectedSampleSlot != null) ...[
            const SizedBox(height: 8),
            Text(
              'SELECTED: ${String.fromCharCode(65 + _selectedSampleSlot!)} - ${_fileNames[_selectedSampleSlot!] ?? 'NO FILE'}',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            const Text(
              'TAP GRID CELL TO PLACE SAMPLE',
              style: TextStyle(
                color: Colors.yellowAccent,
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'NIYYA TRACKER',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people, color: Colors.cyanAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ContactsScreen(),
                ),
              );
            },
            tooltip: 'Contacts',
          ),
          IconButton(
            icon: const Icon(Icons.play_circle, color: Colors.greenAccent),
            onPressed: _startSequencer,
            tooltip: 'Start Sequencer',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
            onPressed: _stopSequencer,
            tooltip: 'Stop Sequencer',
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildSampleBanks(),
              _buildStatusDisplay(),
              _buildSampleGrid(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),

    );
  }
}
