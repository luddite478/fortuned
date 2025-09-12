import 'dart:ffi' as ffi;

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

    // Optional sync API if needed in future:
    // _pitchPreprocessSampleSyncPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>>('pitch_preprocess_sample_sync');
    // pitchPreprocessSampleSync = _pitchPreprocessSampleSyncPtr.asFunction<int Function(int, double)>();
  }

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _pitchGetMethodPtr;
  late final int Function() pitchGetMethod;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>> _pitchStartAsyncPreprocessingPtr;
  late final int Function(int, double) pitchStartAsyncPreprocessing;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _pitchSetQualityPtr;
  late final int Function(int) pitchSetQuality;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _pitchGetQualityPtr;
  late final int Function() pitchGetQuality;

  // ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Float)>>? _pitchPreprocessSampleSyncPtr;
  // int Function(int, double)? pitchPreprocessSampleSync;
}


