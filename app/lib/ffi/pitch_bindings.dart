import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'native_library.dart';

/// FFI bindings for native pitch preprocessing utilities
class PitchBindings {
  PitchBindings() {
    final lib = NativeLibrary.instance;

    _pitchGetMethodPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('pitch_get_method');
    pitchGetMethod = _pitchGetMethodPtr.asFunction<int Function()>();

    _pitchStartAsyncPreprocessingPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>>('pitch_start_async_preprocessing');
    pitchStartAsyncPreprocessing = _pitchStartAsyncPreprocessingPtr.asFunction<int Function(int, double)>();

    _pitchSetQualityPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>>('pitch_set_quality');
    pitchSetQuality = _pitchSetQualityPtr.asFunction<int Function(int)>();

    _pitchGetQualityPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('pitch_get_quality');
    pitchGetQuality = _pitchGetQualityPtr.asFunction<int Function()>();

    // Disk-based pitched file management
    _pitchGetFilePathPtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function(ffi.Int32, ffi.Float)>>('pitch_get_file_path');
    pitchGetFilePath = _pitchGetFilePathPtr.asFunction<ffi.Pointer<ffi.Char> Function(int, double)>();

    _pitchGenerateFilePtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float, ffi.Pointer<ffi.Char>)>>('pitch_generate_file');
    pitchGenerateFile = _pitchGenerateFilePtr.asFunction<int Function(int, double, ffi.Pointer<ffi.Char>)>();
  }

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _pitchGetMethodPtr;
  late final int Function() pitchGetMethod;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>> _pitchStartAsyncPreprocessingPtr;
  late final int Function(int, double) pitchStartAsyncPreprocessing;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _pitchSetQualityPtr;
  late final int Function(int) pitchSetQuality;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _pitchGetQualityPtr;
  late final int Function() pitchGetQuality;

  // Disk-based pitched file management
  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function(ffi.Int32, ffi.Float)>> _pitchGetFilePathPtr;
  late final ffi.Pointer<ffi.Char> Function(int, double) pitchGetFilePath;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float, ffi.Pointer<ffi.Char>)>> _pitchGenerateFilePtr;
  late final int Function(int, double, ffi.Pointer<ffi.Char>) pitchGenerateFile;

  /// Helper method to get pitched file path as Dart String
  String? getPitchFilePath(int sampleSlot, double pitch) {
    final pathPtr = pitchGetFilePath(sampleSlot, pitch);
    if (pathPtr.address == 0) return null;
    return pathPtr.cast<Utf8>().toDartString();
  }

  /// Helper method to generate pitched file with Dart String path
  int generatePitchFile(int sampleSlot, double pitch, String outputPath) {
    final pathPtr = outputPath.toNativeUtf8();
    try {
      return pitchGenerateFile(sampleSlot, pitch, pathPtr.cast<ffi.Char>());
    } finally {
      malloc.free(pathPtr);
    }
  }

  // ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>>? _pitchPreprocessSampleSyncPtr;
  // int Function(int, double)? pitchPreprocessSampleSync;
}


