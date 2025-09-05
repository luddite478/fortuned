import 'dart:ffi' as ffi;
import 'dart:io';

/// Lazily provides a shared handle to the native dynamic library.
/// Ensures the library is opened only once per process.
class NativeLibrary {
  NativeLibrary._();

  static ffi.DynamicLibrary? _cached;

  static ffi.DynamicLibrary get instance {
    final existing = _cached;
    if (existing != null) return existing;

    final lib = _open();
    _cached = lib;
    return lib;
  }

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libsequencer.so');
    }
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError('Platform not supported');
  }
}


