import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../lame_library.dart';

class AudioConversionService {
  static const int mp3BitrateKbps = 320;
  
  /// Initialize LAME library
  static Future<bool> initialize() async {
    try {
      return LameLibrary.instance.initialize();
    } catch (e) {
      print('❌ Failed to initialize LAME: $e');
      return false;
    }
  }
  
  /// Converts WAV file to MP3 320kbps using native LAME encoder
  /// Returns the path to the converted MP3 file if successful, null if failed
  static Future<String?> convertWavToMp3({
    required String inputWavPath,
    String? outputMp3Path,
    Function(String)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      // Ensure LAME is initialized
      if (!LameLibrary.instance.isAvailable) {
        final initialized = await initialize();
        if (!initialized) {
          onError?.call('LAME library is not available');
          return null;
        }
      }
      
      // Generate output path if not provided
      if (outputMp3Path == null) {
        final directory = await getApplicationDocumentsDirectory();
        final inputFileName = path.basenameWithoutExtension(inputWavPath);
        outputMp3Path = path.join(directory.path, '${inputFileName}_320.mp3');
      }
      
      // Verify input file exists
      final inputFile = File(inputWavPath);
      if (!await inputFile.exists()) {
        onError?.call('Input WAV file not found: $inputWavPath');
        return null;
      }
      
      final inputSize = await inputFile.length();
      print('🎵 Converting WAV to MP3 320kbps using LAME...');
      print('📁 Input: $inputWavPath (${_formatFileSize(inputSize)})');
      print('📁 Output: $outputMp3Path');
      print('📦 LAME version: ${LameLibrary.instance.version}');
      
      // Delete output file if it already exists
      final outputFile = File(outputMp3Path);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      
      onProgress?.call('Starting MP3 conversion...');
      
      // Perform native LAME conversion
      final success = LameLibrary.instance.convertWavToMp3(
        wavPath: inputWavPath,
        mp3Path: outputMp3Path,
        bitrateKbps: mp3BitrateKbps,
      );
      
      if (success) {
        // Verify output file was created
        if (await outputFile.exists()) {
          final outputSize = await outputFile.length();
          final compressionRatio = (1 - (outputSize / inputSize)) * 100;
          
          print('✅ MP3 conversion successful!');
          print('📊 Size reduction: ${compressionRatio.toStringAsFixed(1)}%');
          onProgress?.call('Conversion completed successfully!');
          return outputMp3Path;
        } else {
          onError?.call('MP3 file was not created');
          return null;
        }
      } else {
        onError?.call('LAME conversion failed');
        return null;
      }
    } catch (e) {
      print('❌ Error during MP3 conversion: $e');
      onError?.call('Conversion error: $e');
      return null;
    }
  }
  
  /// Converts WAV file to MP3 with progress tracking (using isolate for heavy processing)
  static Future<String?> convertWavToMp3WithProgress({
    required String inputWavPath,
    String? outputMp3Path,
    Function(double progress)? onProgress,
    Function(String)? onError,
  }) async {
    try {
      // Ensure LAME is initialized
      if (!LameLibrary.instance.isAvailable) {
        final initialized = await initialize();
        if (!initialized) {
          onError?.call('LAME library is not available');
          return null;
        }
      }
      
      // Generate output path if not provided
      if (outputMp3Path == null) {
        final directory = await getApplicationDocumentsDirectory();
        final inputFileName = path.basenameWithoutExtension(inputWavPath);
        outputMp3Path = path.join(directory.path, '${inputFileName}_320.mp3');
      }
      
      // Verify input file exists
      final inputFile = File(inputWavPath);
      if (!await inputFile.exists()) {
        onError?.call('Input WAV file not found: $inputWavPath');
        return null;
      }
      
      print('🎵 Converting WAV to MP3 320kbps with progress tracking...');
      
      // Delete output file if it already exists
      final outputFile = File(outputMp3Path);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      
      // Progress simulation (since LAME conversion is typically very fast)
      onProgress?.call(0.1); // Starting
      
      // Run conversion in isolate to prevent UI blocking
      final result = await _runConversionInIsolate(
        inputWavPath,
        outputMp3Path,
        mp3BitrateKbps,
        onProgress,
      );
      
      if (result == true) {
        if (await outputFile.exists()) {
          onProgress?.call(1.0); // 100% complete
          print('✅ MP3 conversion with progress completed!');
          return outputMp3Path;
        } else {
          onError?.call('MP3 file was not created');
          return null;
        }
      } else {
        onError?.call('Conversion failed in isolate');
        return null;
      }
    } catch (e) {
      print('❌ Error during MP3 conversion: $e');
      onError?.call('Conversion error: $e');
      return null;
    }
  }
  
  /// Run LAME conversion in isolate to prevent UI blocking
  static Future<bool> _runConversionInIsolate(
    String inputPath,
    String outputPath,
    int bitrate,
    Function(double)? onProgress,
  ) async {
    final receivePort = ReceivePort();
    
    try {
      await Isolate.spawn(
        _conversionIsolateEntry,
        {
          'sendPort': receivePort.sendPort,
          'inputPath': inputPath,
          'outputPath': outputPath,
          'bitrate': bitrate,
        },
      );
      
      final completer = Completer<bool>();
      
      receivePort.listen((message) {
        if (message is Map) {
          if (message['type'] == 'progress') {
            onProgress?.call(message['value']);
          } else if (message['type'] == 'result') {
            completer.complete(message['success']);
            receivePort.close();
          } else if (message['type'] == 'error') {
            completer.complete(false);
            receivePort.close();
          }
        }
      });
      
      return await completer.future;
    } catch (e) {
      receivePort.close();
      print('❌ Error in isolate: $e');
      return false;
    }
  }
  
  /// Isolate entry point for conversion
  static void _conversionIsolateEntry(Map<String, dynamic> params) {
    final sendPort = params['sendPort'] as SendPort;
    final inputPath = params['inputPath'] as String;
    final outputPath = params['outputPath'] as String;
    final bitrate = params['bitrate'] as int;
    
    try {
      // Initialize LAME in isolate
      final lame = LameLibrary.instance;
      if (!lame.initialize()) {
        sendPort.send({'type': 'error', 'message': 'Failed to initialize LAME'});
        return;
      }
      
      // Report progress
      sendPort.send({'type': 'progress', 'value': 0.3});
      
      // Perform conversion
      final success = lame.convertWavToMp3(
        wavPath: inputPath,
        mp3Path: outputPath,
        bitrateKbps: bitrate,
      );
      
      sendPort.send({'type': 'progress', 'value': 0.9});
      
      // Send result
      sendPort.send({'type': 'result', 'success': success});
    } catch (e) {
      sendPort.send({'type': 'error', 'message': e.toString()});
    }
  }
  
  /// Get audio file information (basic file stats)
  static Future<Map<String, dynamic>?> getAudioInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      
      final stats = await file.stat();
      final size = await file.length();
      
      // Use LAME to get file size for comparison
      final lameSize = LameLibrary.instance.getFileSize(filePath);
      
      return {
        'file_path': filePath,
        'file_size': size,
        'lame_size': lameSize,
        'modified': stats.modified.toIso8601String(),
        'format': path.extension(filePath).toLowerCase(),
        'readable': true,
      };
    } catch (e) {
      print('❌ Error getting audio info: $e');
      return null;
    }
  }
  
  /// Format file size in human-readable format
  static String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
  
  /// Check if LAME is available and working
  static Future<bool> checkLameAvailability() async {
    try {
      if (!LameLibrary.instance.isAvailable) {
        return await initialize();
      }
      return true;
    } catch (e) {
      print('❌ LAME not available: $e');
      return false;
    }
  }
  
  /// Get LAME version information
  static String getLameVersion() {
    try {
      return LameLibrary.instance.version;
    } catch (e) {
      return 'Error getting version';
    }
  }
  
  /// Cleanup LAME resources
  static void cleanup() {
    try {
      LameLibrary.instance.cleanup();
    } catch (e) {
      print('❌ Error during LAME cleanup: $e');
    }
  }
} 