import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'miniaudio_bindings_generated.dart';

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

class MiniaudioLibrary {
  static MiniaudioLibrary? _instance;
  late final DynamicLibrary _dylib;
  late final MiniaudioBindings _bindings;

  MiniaudioLibrary._() {
    _dylib = _loadLibrary();
    _bindings = MiniaudioBindings(_dylib);
  }

  static MiniaudioLibrary get instance {
    _instance ??= MiniaudioLibrary._();
    return _instance!;
  }

  DynamicLibrary _loadLibrary() {
    try {
      if (Platform.isIOS) {
        // On iOS, the library is statically linked into the app bundle
        return DynamicLibrary.executable();
      } else if (Platform.isAndroid) {
        return DynamicLibrary.open('libminiaudio.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libminiaudio.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('miniaudio.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libminiaudio.so');
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
    int result = _bindings.miniaudio_init();
    return result == 1;
  }

  bool playSound(String filePath) {
    print('Attempting to play: $filePath');
    
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
      int result = _bindings.miniaudio_play_sound(cString.cast());
      print('🎵 FFI RESULT: $result (1=success, 0=failure)');
      bool success = result == 1;
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

  void stopAllSounds() {
    _bindings.miniaudio_stop_all_sounds();
  }

  bool isInitialized() {
    return _bindings.miniaudio_is_initialized() == 1;
  }

  void cleanup() {
    _bindings.miniaudio_cleanup();
  }
} 