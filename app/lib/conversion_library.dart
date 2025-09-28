import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'conversion_bindings_generated.dart';

/// Dart wrapper for the audio conversion library
class ConversionLibrary {
  static final ConversionLibrary _instance = ConversionLibrary._internal();
  factory ConversionLibrary() => _instance;
  ConversionLibrary._internal();

  late final ConversionBindings _bindings;
  bool _isLoaded = false;
  String? _loadError;

  /// Initialize the conversion library and load the native library
  void initialize() {
    if (_isLoaded) return;

    try {
      final ffi.DynamicLibrary library;
      
      if (Platform.isAndroid) {
        library = ffi.DynamicLibrary.open('libsequencer.so');
      } else if (Platform.isMacOS) {
        library = ffi.DynamicLibrary.open('libsequencer.dylib');
      } else if (Platform.isWindows) {
        library = ffi.DynamicLibrary.open('sequencer.dll');
      } else if (Platform.isLinux) {
        library = ffi.DynamicLibrary.open('libsequencer.so');
      } else if (Platform.isIOS) {
        // On iOS, the library is statically linked
        library = ffi.DynamicLibrary.executable();
      } else {
        throw UnsupportedError('Unsupported platform');
      }

      _bindings = ConversionBindings(library);
      _isLoaded = true;
      print('✅ Conversion library loaded successfully');
    } catch (e) {
      _loadError = e.toString();
      print('❌ Failed to load conversion library: $e');
      print('❌ Conversion functionality will be disabled');
      _isLoaded = false;
    }
  }

  bool get isLoaded => _isLoaded;
  String? get loadError => _loadError;

  /// Initialize the conversion engine
  /// 
  /// Returns true if initialization was successful
  bool init() {
    if (!_isLoaded) {
      throw StateError('ConversionLibrary not initialized. Call initialize() first.');
    }
    
    int result = _bindings.conversion_init();
    
    if (result == 0) {
      print('✅ Conversion library initialized successfully');
      return true;
    } else {
      print('🔴 Failed to initialize conversion library');
      return false;
    }
  }

  /// Convert a WAV file to MP3 format
  /// 
  /// [wavPath] - Path to the input WAV file
  /// [mp3Path] - Path where the MP3 file will be saved
  /// [bitrateKbps] - MP3 bitrate in kbps (e.g., 128, 192, 320)
  /// 
  /// Returns true if conversion was successful
  bool convertWavToMp3(String wavPath, String mp3Path, int bitrateKbps) {
    if (!_isLoaded) {
      throw StateError('ConversionLibrary not initialized. Call initialize() first.');
    }
    
    final wavPathPtr = wavPath.toNativeUtf8();
    final mp3PathPtr = mp3Path.toNativeUtf8();
    
    try {
      int result = _bindings.conversion_convert_wav_to_mp3(
        wavPathPtr.cast(),
        mp3PathPtr.cast(),
        bitrateKbps,
      );
      
      if (result == 0) {
        print('✅ Successfully converted $wavPath to $mp3Path at ${bitrateKbps}kbps');
        return true;
      } else {
        print('🔴 Failed to convert $wavPath to MP3 (error code: $result)');
        return false;
      }
    } finally {
      // Clean up allocated memory
      malloc.free(wavPathPtr);
      malloc.free(mp3PathPtr);
    }
  }

  /// Get the size of a file in bytes
  /// 
  /// [filePath] - Path to the file
  /// 
  /// Returns file size in bytes, or -1 if file doesn't exist or error occurred
  int getFileSize(String filePath) {
    if (!_isLoaded) {
      throw StateError('ConversionLibrary not initialized. Call initialize() first.');
    }
    
    final filePathPtr = filePath.toNativeUtf8();
    
    try {
      int result = _bindings.conversion_get_file_size(filePathPtr.cast());
      return result;
    } finally {
      malloc.free(filePathPtr);
    }
  }

  /// Check if the conversion library is available and ready to use
  bool get isAvailable {
    if (!_isLoaded) return false;
    return _bindings.conversion_is_available() == 1;
  }

  /// Get the version string of the underlying LAME encoder
  String get version {
    if (!_isLoaded) {
      throw StateError('ConversionLibrary not initialized. Call initialize() first.');
    }
    
    final versionPtr = _bindings.conversion_get_version();
    if (versionPtr == ffi.nullptr) {
      return 'Unknown';
    }
    
    return versionPtr.cast<Utf8>().toDartString();
  }

  /// Clean up conversion resources
  void cleanup() {
    if (!_isLoaded) return;
    
    _bindings.conversion_cleanup();
    print('✅ Conversion library cleanup completed');
  }

  // Run conversion in a background isolate to avoid blocking the UI isolate
  static Future<bool> convertInBackground(
    String wavPath,
    String mp3Path,
    int bitrateKbps,
  ) async {
    return compute(_convertWorker, <String, dynamic>{
      'wavPath': wavPath,
      'mp3Path': mp3Path,
      'bitrate': bitrateKbps,
    });
  }
}

// Top-level worker function for the background isolate
bool _convertWorker(Map<String, dynamic> args) {
  final String wavPath = args['wavPath'] as String;
  final String mp3Path = args['mp3Path'] as String;
  final int bitrate = args['bitrate'] as int;

  final lib = ConversionLibrary();
  lib.initialize();
  if (!lib.init()) {
    return false;
  }
  return lib.convertWavToMp3(wavPath, mp3Path, bitrate);
}

 