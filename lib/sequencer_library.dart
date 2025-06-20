import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'sequencer_bindings_generated.dart';

// Import malloc from dart:ffi
final DynamicLibrary stdlib = Platform.isWindows 
    ? DynamicLibrary.open('kernel32.dll')
    : DynamicLibrary.process();

final malloc = stdlib.lookupFunction<
    Pointer<Void> Function(IntPtr),
    Pointer<Void> Function(int)>('malloc');

final free = stdlib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('free');

class SequencerLibrary {
  static SequencerLibrary? _instance;
  late final DynamicLibrary _dylib;
  late final SequencerBindings _bindings;

  SequencerLibrary._() {
    _dylib = _loadLibrary();
    _bindings = SequencerBindings(_dylib);
  }

  static SequencerLibrary get instance {
    _instance ??= SequencerLibrary._();
    return _instance!;
  }

  DynamicLibrary _loadLibrary() {
    try {
      if (Platform.isIOS) {
        // On iOS, the library is statically linked into the app bundle
        return DynamicLibrary.executable();
      } else if (Platform.isAndroid) {
        return DynamicLibrary.open('libsequencer.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libsequencer.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('sequencer.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libsequencer.so');
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      throw Exception('Failed to load native library: $e. '
          'Make sure the C files are properly added to your iOS project.');
    }
  }

  // Wrapper methods for easier access
  bool initialize() {
    int result = _bindings.init();
    return result == 0;  // 0 means success in C code
  }

  // Direct file playback (streaming from disk)
  bool playSoundFromFile(String filePath) {
    print('Attempting to play from file: $filePath');
    
    // Convert Dart string to C string using manual allocation
    final utf8Bytes = utf8.encode(filePath);
    final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
    
    try {
      // Copy the UTF-8 bytes to native memory
      for (int i = 0; i < utf8Bytes.length; i++) {
        cString[i] = utf8Bytes[i];
      }
      cString[utf8Bytes.length] = 0; // null terminator
      
      // Call the native function
      int result = _bindings.play_sound(cString.cast());
      print('🎵 FFI RESULT: $result (0=success, -1=failure)');
      bool success = result == 0;  // 0 means success in C code
      if (success) {
        print('✅ DART: Audio command sent successfully via FFI!');
      } else {
        print('❌ DART: Audio command failed!');
      }
      return success;
    } finally {
      // Always free the allocated memory
      free(cString.cast());
    }
  }

  // Load sound into memory for faster playback
  bool loadSoundIntoMemory(String filePath) {
    print('Loading sound into memory: $filePath');
    
    final utf8Bytes = utf8.encode(filePath);
    final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
    
    try {
      for (int i = 0; i < utf8Bytes.length; i++) {
        cString[i] = utf8Bytes[i];
      }
      cString[utf8Bytes.length] = 0;
      
      int result = _bindings.load_sound(cString.cast());
      print('📥 FFI RESULT: $result (0=success, -1=failure)');
      bool success = result == 0;
      if (success) {
        print('✅ DART: Sound loaded into memory successfully!');
      } else {
        print('❌ DART: Failed to load sound into memory!');
      }
      return success;
    } finally {
      free(cString.cast());
    }
  }

  // Play the previously loaded sound
  bool playLoadedSound() {
    print('Playing loaded sound from memory');
    
    int result = _bindings.play_loaded_sound();
    print('▶️ FFI RESULT: $result (0=success, -1=failure)');
    bool success = result == 0;
    if (success) {
      print('✅ DART: Loaded sound started successfully!');
    } else {
      print('❌ DART: Failed to play loaded sound!');
    }
    return success;
  }

  void stopAllSounds() {
    _bindings.stop_all_sounds();
  }

  bool isInitialized() {
    return _bindings.is_initialized() == 1;
  }

  void cleanup() {
    _bindings.cleanup();
  }

  // Re-activate Bluetooth audio session (call when Bluetooth routing stops working)
  bool reconfigureAudioSession() {
    int result = _bindings.reconfigure_audio_session();
    return result == 0;
  }

  // Memory tracking methods
  int getTotalMemoryUsage() {
    return _bindings.get_total_memory_usage();
  }

  int getSlotMemoryUsage(int slot) {
    return _bindings.get_slot_memory_usage(slot);
  }

  int getMemorySlotCount() {
    return _bindings.get_memory_slot_count();
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

  // -------------- MULTI SLOT --------------
  int get slotCount => _bindings.get_slot_count();

  bool loadSoundToSlot(int slot, String filePath, {bool loadToMemory = false}) {
    final utf8Bytes = utf8.encode(filePath);
    final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
    try {
      for (int i = 0; i < utf8Bytes.length; i++) {
        cString[i] = utf8Bytes[i];
      }
      cString[utf8Bytes.length] = 0;
      int result = _bindings.load_sound_to_slot(slot, cString.cast(), loadToMemory ? 1 : 0);
      return result == 0;
    } finally {
      free(cString.cast());
    }
  }

  bool playSlot(int slot) {
    int result = _bindings.play_slot(slot);
    return result == 0;
  }

  void stopSlot(int slot) {
    _bindings.stop_slot(slot);
  }

  void unloadSlot(int slot) {
    _bindings.unload_slot(slot);
  }

  bool isSlotLoaded(int slot) {
    return _bindings.is_slot_loaded(slot) == 1;
  }

  // Helper to play all loaded slots at once
  void playAllLoadedSlots() {
    for (int i = 0; i < slotCount; i++) {
      if (isSlotLoaded(i)) {
        playSlot(i);
      }
    }
  }

  // -------------- OUTPUT RECORDING FUNCTIONS (Based on miniaudio simple_capture example) --------------
  
  /// Start recording mixed grid output to a WAV file
  /// Records the combined audio of all playing samples in real-time
  bool startOutputRecording(String outputFilePath) {
    print('🎙️ Starting output recording to: $outputFilePath');
    
    final utf8Bytes = utf8.encode(outputFilePath);
    final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
    
    try {
      for (int i = 0; i < utf8Bytes.length; i++) {
        cString[i] = utf8Bytes[i];
      }
      cString[utf8Bytes.length] = 0;
      
      int result = _bindings.start_recording(cString.cast());
      bool success = result == 0;
      
      if (success) {
        print('✅ Output recording started successfully');
      } else {
        print('❌ Failed to start output recording');
      }
      
      return success;
    } finally {
      free(cString.cast());
    }
  }
  
  /// Stop the current output recording
  bool stopOutputRecording() {
    print('⏹️ Stopping output recording...');
    
    int result = _bindings.stop_recording();
    bool success = result == 0;
    
    if (success) {
      print('✅ Output recording stopped successfully');
    } else {
      print('❌ Failed to stop recording (maybe not recording?)');
    }
    
    return success;
  }
  
  /// Check if currently recording output
  bool get isOutputRecording => _bindings.is_recording() == 1;
  
  /// Get current recording duration in milliseconds
  int get outputRecordingDurationMs {
    return _bindings.get_recording_duration();
  }
  
  /// Get formatted recording duration as MM:SS
  String get formattedOutputRecordingDuration {
    final durationMs = outputRecordingDurationMs;
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Debug functions removed - Bluetooth audio working correctly

  // -------------- SEQUENCER FUNCTIONS (Sample-accurate timing) --------------
  
  /// Start the sequencer with sample-accurate timing
  /// This moves timing logic from Flutter Timer to the audio callback
  bool startSequencer(int bpm, int steps) {
    if (!isInitialized()) {
      print('❌ Audio not initialized');
      return false;
    }
    
    try {
      int result = _bindings.start(bpm, steps);
      bool success = result == 0;
      if (success) {
        print('🎵 Sequencer started: $bpm BPM, $steps steps');
      } else {
        print('❌ Failed to start sequencer');
      }
      return success;
    } catch (e) {
      print('❌ Error starting sequencer: $e');
      return false;
    }
  }
  
  /// Stop the sequencer
  void stopSequencer() {
    try {
      _bindings.stop();
      print('⏹️ Sequencer stopped');
    } catch (e) {
      print('❌ Error stopping sequencer: $e');
    }
  }
  
  /// Check if sequencer is playing
  bool get isSequencerPlaying {
    try {
      return _bindings.is_playing() == 1;
    } catch (e) {
      return false;
    }
  }
  
  /// Get current sequencer step (0-based)
  int get currentStep {
    try {
      return _bindings.get_current_step();
    } catch (e) {
      return -1;
    }
  }
  
  /// Set sequencer BPM (updates timing instantly)
  void setSequencerBpm(int bpm) {
    try {
      _bindings.set_bpm(bpm);
    } catch (e) {
      print('❌ Error setting sequencer BPM: $e');
    }
  }
  
  /// Set a grid cell to play a specific sample slot
  /// step: 0-31, column: 0-7, sampleSlot: 0-1023 (or -1 to clear)
  void setGridCell(int step, int column, int sampleSlot) {
    try {
      _bindings.set_cell(step, column, sampleSlot);
    } catch (e) {
      print('❌ Error setting grid cell: $e');
    }
  }
  
  /// Clear a specific grid cell
  void clearGridCell(int step, int column) {
    try {
      _bindings.clear_cell(step, column);
    } catch (e) {
      print('❌ Error clearing grid cell: $e');
    }
  }
  
  /// Clear all grid cells
  void clearAllGridCells() {
    try {
      _bindings.clear_all_cells();
      print('🗑️ All grid cells cleared');
    } catch (e) {
      print('❌ Error clearing all grid cells: $e');
    }
  }
  
  // -------------- MULTI-GRID SEQUENCER FUNCTIONS --------------
  
  /// Set a cell using grid coordinates (automatically calculates absolute column)
  void setCellAt(int gridIndex, int step, int column, int sampleSlot, {int columnsPerGrid = 4}) {
    final absoluteColumn = gridIndex * columnsPerGrid + column;
    setGridCell(step, absoluteColumn, sampleSlot);
  }
  
  /// Clear a cell using grid coordinates
  void clearCellAt(int gridIndex, int step, int column, {int columnsPerGrid = 4}) {
    final absoluteColumn = gridIndex * columnsPerGrid + column;
    clearGridCell(step, absoluteColumn);
  }
  
  /// Configure columns for multi-grid support  
  /// Directly sets the columns in native sequencer
  void configureColumns(int columns) {
    try {
      _bindings.set_columns(columns);
      print('🎛️ Set sequencer columns to $columns');
    } catch (e) {
      print('❌ Error setting columns: $e');
    }
  }
} 