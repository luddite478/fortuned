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

  // Per-slot state for sample banks
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotUseMemory;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  // UI state
  int _activeBank = 0;
  int? _activePad;

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
    _slotUseMemory = List.filled(_slotCount, false);
    _slotLoaded = List.filled(_slotCount, false);
    _slotPlaying = List.filled(_slotCount, false);
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
      loadToMemory: _slotUseMemory[slot],
    );
    setState(() {
      _slotLoaded[slot] = success;
    });
  }

  void _playSlot(int slot) {
    final bool loaded = _slotLoaded[slot];
    if (!loaded) {
      _loadSlot(slot);
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
    setState(() {
      _activeBank = bankIndex;
    });
  }

  void _handlePadPress(int padIndex) {
    setState(() {
      _activePad = padIndex;
    });
    
    // Play the active bank's sample when pad is pressed
    if (_filePaths[_activeBank] != null) {
      _playSlot(_activeBank);
    }
    
    // Reset active pad after animation
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _activePad = null;
        });
      }
    });
  }

  Widget _buildSampleBanks() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: List.generate(8, (bank) {
          final isActive = _activeBank == bank;
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
                  color: isActive
                      ? Colors.white
                      : hasFile
                          ? _bankColors[bank].withOpacity(0.8)
                          : const Color(0xFF404040),
                  borderRadius: BorderRadius.circular(6),
                  border: isPlaying
                      ? Border.all(color: Colors.greenAccent, width: 2)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      String.fromCharCode(65 + bank), // A, B, C, etc.
                      style: TextStyle(
                        color: isActive ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (hasFile) ...[
                      const SizedBox(height: 2),
                      Icon(
                        Icons.audiotrack,
                        size: 12,
                        color: isActive ? Colors.black : Colors.white70,
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
            final baseColor = _bankColors[_activeBank];
            
            return GestureDetector(
              onTap: () => _handlePadPress(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: isActivePad ? Colors.white : baseColor,
                  borderRadius: BorderRadius.circular(4),
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
                        '${index + 1}',
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
          if (hasFile) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'MEMORY: ${_slotUseMemory[_activeBank] ? 'ON' : 'OFF'}',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _slotUseMemory[_activeBank],
                  onChanged: (val) {
                    setState(() {
                      _slotUseMemory[_activeBank] = val;
                      _slotLoaded[_activeBank] = false;
                    });
                  },
                  activeColor: Colors.cyanAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSequencerBottom() {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: List.generate(8, (col) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                children: List.generate(4, (row) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF404040),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
          );
        }),
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
              _buildSequencerBottom(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
