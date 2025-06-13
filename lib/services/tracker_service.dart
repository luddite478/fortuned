import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../miniaudio_library.dart';
import '../models/app_state.dart';

class TrackerService {
  final MiniaudioLibrary _miniaudioLibrary;
  final TrackerState _trackerState;
  
  TrackerService({
    required TrackerState trackerState,
  }) : _trackerState = trackerState,
       _miniaudioLibrary = MiniaudioLibrary.instance {
    print('🎵 TrackerService constructor called');
    print('🎵 MiniaudioLibrary instance in constructor: $_miniaudioLibrary');
    _setupSequencerCallback();
  }

  // Initialize tracker system
  Future<bool> initialize() async {
    print('🎵 TrackerService.initialize() called - MiniaudioLibrary should already be initialized');
    print('🎵 MiniaudioLibrary instance: $_miniaudioLibrary');
    bool isInitialized = _miniaudioLibrary.isInitialized();
    print('🎵 MiniaudioLibrary.isInitialized() returned: $isInitialized');
    return isInitialized;
  }

  // Cleanup tracker system
  void dispose() {
    _miniaudioLibrary.cleanup();
  }

  // Audio session management
  void reconfigureAudioSession() {
    _miniaudioLibrary.reconfigureAudioSession();
  }

  // Sample loading operations
  Future<String> copyAssetToTemp(String assetPath, String fileName) async {
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

  Future<void> loadSample(int slotIndex, String filePath, String fileName) async {
    try {
      String finalPath = filePath;
      
      // Check if this is a bundled asset path (starts with "samples/")
      if (filePath.startsWith('samples/')) {
        print('🎵 Loading bundled asset: $filePath');
        finalPath = await copyAssetToTemp(filePath, fileName);
        print('📁 Copied to temp file: $finalPath');
      }
      
      // Update TrackerState with file info
      _trackerState.loadSample(slotIndex, finalPath, fileName);
      
      // Load to miniaudio
      bool success = _miniaudioLibrary.loadSoundToSlot(
        slotIndex,
        finalPath,
        loadToMemory: true,
      );
      
      // Update load status
      _trackerState.updateSlotLoadStatus(slotIndex, success);
      
      if (success) {
        // Update memory usage
        final memoryUsage = _miniaudioLibrary.getSlotMemoryUsage(slotIndex);
        _trackerState.updateSlotLoadStatus(slotIndex, true, memoryUsage: memoryUsage);
      }
      
    } catch (e) {
      print('❌ Error loading sample: $e');
      _trackerState.updateSlotLoadStatus(slotIndex, false);
      rethrow;
    }
  }

  // Playback operations
  void playSlot(int slotIndex) {
    // Check if audio device is initialized
    if (!_miniaudioLibrary.isInitialized()) {
      print('⚠️ Audio device not initialized, cannot play slot $slotIndex');
      return;
    }
    
    final slot = _trackerState.getSlot(slotIndex);
    
    // Sample should already be loaded in memory
    if (!slot.isLoaded) {
      print('⚠️ Slot $slotIndex not loaded, cannot play');
      return;
    }
    
    // Ensure Bluetooth audio routing is active before playback
    reconfigureAudioSession();
    
    bool success = _miniaudioLibrary.playSlot(slotIndex);
    if (success) {
      _trackerState.updateSlotPlayStatus(slotIndex, true);
    }
  }

  void stopSlot(int slotIndex) {
    _miniaudioLibrary.stopSlot(slotIndex);
    _trackerState.updateSlotPlayStatus(slotIndex, false);
  }

  void stopAllSlots() {
    _miniaudioLibrary.stopAllSounds();
    _trackerState.stopAllSlots();
  }

  void playAllLoadedSlots() {
    // Check if audio device is initialized
    if (!_miniaudioLibrary.isInitialized()) {
      print('⚠️ Audio device not initialized, cannot play slots');
      return;
    }
    
    // Ensure Bluetooth audio routing is active before playback
    reconfigureAudioSession();
    
    _miniaudioLibrary.playAllLoadedSlots();
    
    // Update UI state for all loaded slots
    for (int i = 0; i < TrackerState.maxSlots; i++) {
      final slot = _trackerState.getSlot(i);
      if (slot.isLoaded) {
        _trackerState.updateSlotPlayStatus(i, true);
      }
    }
  }

  // Sequencer operations
  void _setupSequencerCallback() {
    _trackerState.setStepCallback(_playStepSamples);
  }

  void _playStepSamples(int step) {
    // Check if audio device is initialized before attempting playback
    if (!_miniaudioLibrary.isInitialized()) {
      print('⚠️ Audio device not initialized, skipping step playback');
      return;
    }
    
    // Stop any currently playing column samples
    for (int col = 0; col < _trackerState.gridColumns; col++) {
      final playingSample = _trackerState.columnPlayingSample[col];
      if (playingSample != null) {
        stopSlot(playingSample);
        _trackerState.setColumnPlayingSample(col, null);
      }
    }

    // Play samples for this step
    for (int col = 0; col < _trackerState.gridColumns; col++) {
      final cellIndex = _trackerState.getCellIndexFromRowCol(step, col);
      final sampleSlot = _trackerState.getGridSample(cellIndex);
      
      if (sampleSlot != null) {
        final slot = _trackerState.getSlot(sampleSlot);
        if (slot.isLoaded) {
          playSlot(sampleSlot);
          _trackerState.setColumnPlayingSample(col, sampleSlot);
        }
      }
    }
  }

  // Memory info
  int getTotalMemoryUsage() => _miniaudioLibrary.getTotalMemoryUsage();
  int getMemorySlotCount() => _miniaudioLibrary.getMemorySlotCount();
  int getSlotMemoryUsage(int slotIndex) => _miniaudioLibrary.getSlotMemoryUsage(slotIndex);
  
  String formatMemorySize(int bytes) => _trackerState.formatMemorySize(bytes);
} 