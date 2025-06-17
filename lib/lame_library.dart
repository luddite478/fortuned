import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:convert';
import 'lame_bindings_generated.dart';

class LameLibrary {
  static LameLibrary? _instance;
  static LameLibrary get instance => _instance ??= LameLibrary._();
  
  late final LameBindings _bindings;
  late final DynamicLibrary _library;
  
  LameLibrary._() {
    // Load the native library
    if (Platform.isIOS) {
      _library = DynamicLibrary.process(); // iOS bundles everything in main app
    } else if (Platform.isAndroid) {
      _library = DynamicLibrary.open('libnative.so');
    } else if (Platform.isMacOS) {
      _library = DynamicLibrary.open('libnative.dylib');
    } else {
      throw UnsupportedError('Platform not supported');
    }
    
    _bindings = LameBindings(_library);
  }
  
  /// Initialize LAME library
  bool initialize() {
    int result = _bindings.lame_wrapper_init();
    bool success = result == 0;
    
    if (success) {
      print('✅ LAME initialized successfully');
      print('📦 LAME version: ${version}');
    } else {
      print('❌ Failed to initialize LAME');
    }
    
    return success;
  }
  
  /// Convert WAV file to MP3 with specified bitrate
  bool convertWavToMp3({
    required String wavPath,
    required String mp3Path,
    int bitrateKbps = 320,
  }) {
    print('🎵 Converting WAV to MP3: $wavPath -> $mp3Path');
    print('🔧 Bitrate: ${bitrateKbps}kbps');
    
    final wavPathBytes = utf8.encode(wavPath);
    final Pointer<Int8> wavCString = malloc<Int8>(wavPathBytes.length + 1);
    
    final mp3PathBytes = utf8.encode(mp3Path);
    final Pointer<Int8> mp3CString = malloc<Int8>(mp3PathBytes.length + 1);
    
    try {
      // Copy WAV path string
      for (int i = 0; i < wavPathBytes.length; i++) {
        wavCString[i] = wavPathBytes[i];
      }
      wavCString[wavPathBytes.length] = 0;
      
      // Copy MP3 path string
      for (int i = 0; i < mp3PathBytes.length; i++) {
        mp3CString[i] = mp3PathBytes[i];
      }
      mp3CString[mp3PathBytes.length] = 0;
      
      int result = _bindings.lame_wrapper_convert_wav_to_mp3(
        wavCString.cast(),
        mp3CString.cast(),
        bitrateKbps,
      );
      
      bool success = result == 0;
      
      if (success) {
        print('✅ MP3 conversion completed successfully');
        
        // Log file sizes
        final wavSize = getFileSize(wavPath);
        final mp3Size = getFileSize(mp3Path);
        if (wavSize > 0 && mp3Size > 0) {
          final compressionRatio = (1 - (mp3Size / wavSize)) * 100;
          print('📊 WAV: ${_formatFileSize(wavSize)} → MP3: ${_formatFileSize(mp3Size)} (${compressionRatio.toStringAsFixed(1)}% smaller)');
        }
      } else {
        print('❌ MP3 conversion failed');
      }
      
      return success;
    } finally {
      malloc.free(wavCString);
      malloc.free(mp3CString);
    }
  }
  
  /// Get file size in bytes
  int getFileSize(String filePath) {
    final pathBytes = utf8.encode(filePath);
    final Pointer<Int8> cString = malloc<Int8>(pathBytes.length + 1);
    
    try {
      for (int i = 0; i < pathBytes.length; i++) {
        cString[i] = pathBytes[i];
      }
      cString[pathBytes.length] = 0;
      
      int result = _bindings.lame_wrapper_get_file_size(cString.cast());
      return result > 0 ? result : 0;
    } finally {
      malloc.free(cString);
    }
  }
  
  /// Check if LAME is available and initialized
  bool get isAvailable => _bindings.lame_wrapper_is_available() == 1;
  
  /// Get LAME version string
  String get version {
    try {
      final versionPtr = _bindings.lame_wrapper_get_version();
      if (versionPtr != nullptr) {
        return versionPtr.cast<Utf8>().toDartString();
      }
      return 'Unknown';
    } catch (e) {
      return 'Error getting version';
    }
  }
  
  /// Cleanup LAME resources
  void cleanup() {
    _bindings.lame_wrapper_cleanup();
    print('🧹 LAME cleanup completed');
  }
  
  /// Format file size in human-readable format
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
} 