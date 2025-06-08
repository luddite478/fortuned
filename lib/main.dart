import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'miniaudio_library.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final MiniaudioLibrary _miniaudioLibrary;
  late final int _slotCount;

  // Per-slot state
  late List<String?> _filePaths;
  late List<String?> _fileNames;
  late List<bool> _slotUseMemory;
  late List<bool> _slotLoaded;
  late List<bool> _slotPlaying;

  @override
  void initState() {
    super.initState();
    _miniaudioLibrary = MiniaudioLibrary.instance;
    _initializeAudio();

    _slotCount = _miniaudioLibrary.slotCount;
    _filePaths     = List.filled(_slotCount, null);
    _fileNames     = List.filled(_slotCount, null);
    _slotUseMemory = List.filled(_slotCount, false);
    _slotLoaded    = List.filled(_slotCount, false);
    _slotPlaying   = List.filled(_slotCount, false);
  }

  Future<void> _initializeAudio() async {
    bool success = _miniaudioLibrary.initialize();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to initialize audio engine'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
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
          SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _loadSlot(int slot) {
    final path = _filePaths[slot];
    if (path == null) return;
    bool success = _miniaudioLibrary.loadSoundToSlot(slot, path, loadToMemory: _slotUseMemory[slot]);
    setState(() {
      _slotLoaded[slot] = success;
    });
  }

  void _playSlot(int slot) {
    final bool loaded = _slotLoaded[slot];
    if (!loaded) {
      _loadSlot(slot);
    }
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

  Widget _buildSlotCard(int slot) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slot ${slot+1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Memory:'),
                Switch(
                  value: _slotUseMemory[slot],
                  onChanged: (val) {
                    setState(() {
                      _slotUseMemory[slot] = val;
                      _slotLoaded[slot] = false; // re-load required
                    });
                  },
                ),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pick'),
                  onPressed: () => _pickFileForSlot(slot),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: Icon(_slotPlaying[slot] ? Icons.music_note : Icons.play_arrow),
                  label: Text(_slotPlaying[slot] ? 'Playing' : 'Play'),
                  style: ElevatedButton.styleFrom(backgroundColor: _slotPlaying[slot] ? Colors.green : null),
                  onPressed: _filePaths[slot] != null ? () => _playSlot(slot) : null,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: _slotPlaying[slot] ? () => _stopSlot(slot) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _fileNames[slot] != null
                ? Text('File: ${_fileNames[slot]}')
                : const Text('No file selected', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            if (_slotUseMemory[slot])
              Text('Status: ${_slotLoaded[slot] ? 'Loaded' : 'Not Loaded'}',
                  style: TextStyle(color: _slotLoaded[slot] ? Colors.green : Colors.orange)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(
          icon: const Icon(Icons.play_circle_fill), 
          tooltip: 'Play All', 
          onPressed: _playAll,
          color: Colors.green,
        ),
        IconButton(icon: const Icon(Icons.stop_circle), tooltip: 'Stop All', onPressed: _stopAll),
      ]),
      body: ListView.builder(
        itemCount: _slotCount + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Miniaudio Multi-Slot Player', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Pick up to 8 samples, toggle memory load, and mix them together.', style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            );
          }
          return _buildSlotCard(index - 1);
        },
      ),
    );
  }
}
