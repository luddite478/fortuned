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
import 'state/app_state.dart';
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
        ChangeNotifierProvider(create: (context) => AppState()),
        ProxyProvider<AppState, AppStateService>(
          update: (context, appState, previous) {
            // Dispose previous service if it exists
            previous?.dispose();
            return AppStateService(
              appState: appState,
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
    if (_selectedSampleSlot == null) {
      // No sample selected - play the sample in this cell if any
      final cellSample = _gridSamples[padIndex];
      if (cellSample != null && _slotLoaded[cellSample]) {
        _playSlot(cellSample);
        
        // Visual feedback
        setState(() {
          _activePad = padIndex;
        });
        
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _activePad = null;
            });
          }
        });
      }
    } else {
      // Place selected sample in this cell
      setState(() {
        _gridSamples[padIndex] = _selectedSampleSlot;
        _selectedSampleSlot = null; // Deselect after placing
      });
    }
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
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // 4 columns
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 2.5,
          ),
          itemCount: 64, // 4 columns × 16 rows
          itemBuilder: (context, index) {
            final row = index ~/ 4;
            final col = index % 4;
            final isActivePad = _activePad == index;
            final isCurrentStep = _currentStep == row && _isSequencerPlaying;
            final placedSample = _gridSamples[index];
            final hasPlacedSample = placedSample != null;
            
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
                setState(() {
                  _gridSamples[index] = sampleSlot;
                });
              },
              builder: (context, candidateData, rejectedData) {
                final bool isDragHovering = candidateData.isNotEmpty;
                
                return GestureDetector(
                  onTap: () => _handlePadPress(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    decoration: BoxDecoration(
                      color: isDragHovering 
                          ? Colors.greenAccent.withOpacity(0.6)
                          : cellColor,
                      borderRadius: BorderRadius.circular(4),
                      border: isDragHovering
                          ? Border.all(color: Colors.greenAccent, width: 3)
                          : isCurrentStep
                              ? Border.all(color: Colors.yellowAccent, width: 2)
                              : hasPlacedSample && !isActivePad
                                  ? Border.all(color: Colors.white38, width: 1)
                                  : null,
                      boxShadow: isActivePad
                          ? [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : isDragHovering
                              ? [
                                  BoxShadow(
                                    color: Colors.greenAccent.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  )
                                ]
                              : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            hasPlacedSample 
                                ? String.fromCharCode(65 + placedSample!)
                                : '${row + 1}',
                            style: TextStyle(
                              color: isActivePad || isDragHovering ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'C-4',
                            style: TextStyle(
                              color: isActivePad || isDragHovering
                                  ? Colors.black54
                                  : Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
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
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS: ${_slotLoaded[_activeBank] ? 'LOADED' : 'LOADING...'}',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                    if (_slotLoaded[_activeBank] && activeSlotMemory > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SIZE: ${_miniaudioLibrary.formatMemorySize(activeSlotMemory)}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontFamily: 'monospace',
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
          
          // Show sample selection status
          if (_selectedSampleSlot != null) ...[
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
            const SizedBox(height: 8),
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
