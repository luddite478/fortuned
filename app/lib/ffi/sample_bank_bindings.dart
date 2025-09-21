import 'dart:ffi' as ffi;
// import 'package:ffi/ffi.dart';

import 'native_library.dart';

// Sizes must match native sample_bank.h
const int SAMPLE_MAX_PATH = 512;
const int SAMPLE_MAX_NAME = 128;
const int SAMPLE_MAX_ID = 128;

final class SampleSettings extends ffi.Struct {
  @ffi.Float()
  external double volume; // 0.0 to 1.0

  @ffi.Float()
  external double pitch; // 0.25 to 4.0
}

// Core sample data structure (mirrors native Sample)
final class Sample extends ffi.Struct {
  @ffi.Int32()
  external int loaded; // 0 = empty, 1 = loaded

  external SampleSettings settings;

  @ffi.Int32()
  external int is_processing; // mirrors native Sample.is_processing

  @ffi.Array(SAMPLE_MAX_ID)
  external ffi.Array<ffi.Char> sample_id; // Inline fixed-size array

  @ffi.Array(SAMPLE_MAX_PATH)
  external ffi.Array<ffi.Char> file_path; // Inline fixed-size array

  @ffi.Array(SAMPLE_MAX_NAME)
  external ffi.Array<ffi.Char> display_name; // Inline fixed-size array
}

// Helper to read C char array into Dart String (null-terminated)
String _cArrayToString(ffi.Array<ffi.Char> arr, int maxLen) {
  final codeUnits = <int>[];
  for (int i = 0; i < maxLen; i++) {
    final int c = arr[i];
    if (c == 0) break;
    codeUnits.add(c);
  }
  return String.fromCharCodes(codeUnits);
}

// Helper class to safely read Sample data
class SampleData {
  final bool loaded;
  final double volume;
  final double pitch;
  final bool isProcessing;
  final String? id;
  final String? filePath;
  final String? displayName;

  const SampleData({
    required this.loaded,
    required this.volume,
    required this.pitch,
    required this.isProcessing,
    this.id,
    this.filePath,
    this.displayName,
  });

  static SampleData fromPointer(ffi.Pointer<Sample> ptr) {
    final sample = ptr.ref;
    final id = _cArrayToString(sample.sample_id, SAMPLE_MAX_ID);
    final path = _cArrayToString(sample.file_path, SAMPLE_MAX_PATH);
    final name = _cArrayToString(sample.display_name, SAMPLE_MAX_NAME);
    return SampleData(
      loaded: sample.loaded != 0,
      volume: sample.settings.volume,
      pitch: sample.settings.pitch,
      isProcessing: sample.is_processing != 0,
      id: id.isEmpty ? null : id,
      filePath: path.isEmpty ? null : path,
      displayName: name.isEmpty ? null : name,
    );
  }
}

// Native SampleBankState structure (read-only snapshot)
final class NativeSampleBankState extends ffi.Struct {
  @ffi.Uint32()
  external int version; // even=stable, odd=write in progress

  @ffi.Int32()
  external int max_slots;

  @ffi.Int32()
  external int loaded_count;

  external ffi.Pointer<Sample> samples_ptr; // direct pointer to samples array
}

/// FFI bindings for native sample bank functions
class SampleBankBindings {
  SampleBankBindings() {
    final lib = NativeLibrary.instance;

    _sampleBankInitPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('sample_bank_init');
    sampleBankInit = _sampleBankInitPtr.asFunction<void Function()>();

    _sampleBankCleanupPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('sample_bank_cleanup');
    sampleBankCleanup = _sampleBankCleanupPtr.asFunction<void Function()>();

    _sampleBankLoadPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>)>>('sample_bank_load');
    sampleBankLoad = _sampleBankLoadPtr.asFunction<int Function(int, ffi.Pointer<ffi.Char>)>();

    _sampleBankLoadWithIdPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>>('sample_bank_load_with_id');
    sampleBankLoadWithId = _sampleBankLoadWithIdPtr.asFunction<int Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>();

    _sampleBankUnloadPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('sample_bank_unload');
    sampleBankUnload = _sampleBankUnloadPtr.asFunction<void Function(int)>();

    _sampleBankIsLoadedPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>>('sample_bank_is_loaded');
    sampleBankIsLoaded = _sampleBankIsLoadedPtr.asFunction<int Function(int)>();

    _sampleBankGetStatePtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<NativeSampleBankState> Function()>>('sample_bank_get_state_ptr');
    sampleBankGetStatePtr = _sampleBankGetStatePtr.asFunction<ffi.Pointer<NativeSampleBankState> Function()>();

    _sampleBankGetSamplePtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<Sample> Function(ffi.Int32)>>('sample_bank_get_sample');
    sampleBankGetSample = _sampleBankGetSamplePtr.asFunction<ffi.Pointer<Sample> Function(int)>();

    _sampleBankSetSampleVolumePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float)>>('sample_bank_set_sample_volume');
    sampleBankSetSampleVolume = _sampleBankSetSampleVolumePtr.asFunction<void Function(int, double)>();

    _sampleBankSetSamplePitchPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float)>>('sample_bank_set_sample_pitch');
    sampleBankSetSamplePitch = _sampleBankSetSamplePitchPtr.asFunction<void Function(int, double)>();
    _sampleBankSetSampleSettingsPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float, ffi.Float)>>('sample_bank_set_sample_settings');
    sampleBankSetSampleSettings = _sampleBankSetSampleSettingsPtr.asFunction<void Function(int, double, double)>();
  }

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _sampleBankInitPtr;
  late final void Function() sampleBankInit;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _sampleBankCleanupPtr;
  late final void Function() sampleBankCleanup;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>)>> _sampleBankLoadPtr;
  late final int Function(int, ffi.Pointer<ffi.Char>) sampleBankLoad;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>> _sampleBankLoadWithIdPtr;
  late final int Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>) sampleBankLoadWithId;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _sampleBankUnloadPtr;
  late final void Function(int) sampleBankUnload;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _sampleBankIsLoadedPtr;
  late final int Function(int) sampleBankIsLoaded;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<NativeSampleBankState> Function()>> _sampleBankGetStatePtr;
  late final ffi.Pointer<NativeSampleBankState> Function() sampleBankGetStatePtr;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<Sample> Function(ffi.Int32)>> _sampleBankGetSamplePtr;
  late final ffi.Pointer<Sample> Function(int) sampleBankGetSample;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float)>> _sampleBankSetSampleVolumePtr;
  late final void Function(int, double) sampleBankSetSampleVolume;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float)>> _sampleBankSetSamplePitchPtr;
  late final void Function(int, double) sampleBankSetSamplePitch;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Float, ffi.Float)>> _sampleBankSetSampleSettingsPtr;
  late final void Function(int, double, double) sampleBankSetSampleSettings;
}


