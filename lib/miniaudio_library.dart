import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'miniaudio_bindings_generated.dart';

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
  int incrementCounter(int currentValue) {
    return _bindings.increment_counter(currentValue);
  }

  void initialize() {
    _bindings.miniaudio_init();
  }

  void cleanup() {
    _bindings.miniaudio_cleanup();
  }
} 