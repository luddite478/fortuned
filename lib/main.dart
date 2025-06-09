import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'miniaudio_library.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

  // Audio state
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  // UI state
  int _activeBank = 0;
  int? _activePad;
  int? _selectedSampleSlot; // Track which sample is selected for placement
  
  // Grid state - tracks which sample slot is assigned to each of the 64 grid cells
  late List<int?> _gridSamples;

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
    _miniaudioLibrary.cleanup();
    super.dispose();
  }

  Future<void> _pickFileForSlot(int slot) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _filePaths[slot] = result.files.single.path;
          _fileNames[slot] = result.files.single.name;
          _slotLoaded[slot] = false;
        });
        
        // Always load sample to memory immediately
        _loadSlot(slot);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      // Empty slot - immediately open file picker
      _pickFileForSlot(bankIndex);
    } else {
      // Loaded slot - select it for placement
      setState(() {
        _selectedSampleSlot = bankIndex;
        _activeBank = bankIndex; // Keep active bank in sync for status display
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

  Widget _buildSampleBanks() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: List.generate(8, (bank) {
          final isActive = _activeBank == bank;
          final isSelected = _selectedSampleSlot == bank;
          final hasFile = _fileNames[bank] != null;
          final isPlaying = _slotPlaying[bank];
          
          return Expanded(
            child: GestureDetector(
              onTap: () => _handleBankChange(bank),
              onLongPress: () => _pickFileForSlot(bank),
              child: Container(
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
              ),
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
            crossAxisCount: 4,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 2.5,
          ),
          itemCount: 64,
          itemBuilder: (context, index) {
            final isActivePad = _activePad == index;
            final placedSample = _gridSamples[index];
            final hasPlacedSample = placedSample != null;
            
            Color cellColor;
            if (isActivePad) {
              cellColor = Colors.white;
            } else if (hasPlacedSample) {
              cellColor = _bankColors[placedSample!];
            } else {
              cellColor = _bankColors[_activeBank];
            }
            
            return GestureDetector(
              onTap: () => _handlePadPress(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: cellColor,
                  borderRadius: BorderRadius.circular(4),
                  border: hasPlacedSample && !isActivePad
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
                            : '${index + 1}',
                        style: TextStyle(
                          color: isActivePad ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'C-4',
                        style: TextStyle(
                          color: isActivePad
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
                'STATUS: ${isPlaying ? 'PLAYING' : 'STOPPED'}',
                style: TextStyle(
                  color: isPlaying ? Colors.greenAccent : Colors.redAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
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
            icon: const Icon(Icons.play_circle, color: Colors.greenAccent),
            onPressed: _playAll,
            tooltip: 'Play All',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
            onPressed: _stopAll,
            tooltip: 'Stop All',
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
