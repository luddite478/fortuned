import 'dart:ffi' as ffi;

import 'native_library.dart';

// Native PlaybackState structure (read-only snapshot)
final class NativePlaybackState extends ffi.Struct {
  @ffi.Uint32()
  external int version; // even=stable, odd=write in progress

  @ffi.Int32()
  external int is_playing;

  @ffi.Int32()
  external int current_step;

  @ffi.Int32()
  external int bpm;

  @ffi.Int32()
  external int region_start;

  @ffi.Int32()
  external int region_end;

  @ffi.Int32()
  external int song_mode;

  external ffi.Pointer<ffi.Int32> sections_loops_num; // pointer to per-section loop counts array

  @ffi.Int32()
  external int current_section;

  @ffi.Int32()
  external int current_section_loop;
}

// Native PlaybackRegion structure (if needed)
final class PlaybackRegion extends ffi.Struct {
  @ffi.Int32()
  external int start;

  @ffi.Int32()
  external int end;
}

/// FFI bindings for native playback functions
class PlaybackBindings {
  PlaybackBindings() {
    final lib = NativeLibrary.instance;

    _playbackInitPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('playback_init');
    playbackInit = _playbackInitPtr.asFunction<int Function()>();

    _playbackCleanupPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('playback_cleanup');
    playbackCleanup = _playbackCleanupPtr.asFunction<void Function()>();

    _playbackStartPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32)>>('playback_start');
    playbackStart = _playbackStartPtr.asFunction<int Function(int, int)>();

    _playbackStopPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('playback_stop');
    playbackStop = _playbackStopPtr.asFunction<void Function()>();

    _playbackSetBpmPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('playback_set_bpm');
    playbackSetBpm = _playbackSetBpmPtr.asFunction<void Function(int)>();

    _playbackSetRegionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('playback_set_region');
    playbackSetRegion = _playbackSetRegionPtr.asFunction<void Function(int, int)>();

    _playbackSetModePtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('playback_set_mode');
    playbackSetMode = _playbackSetModePtr.asFunction<void Function(int)>();

    _playbackGetStatePtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<NativePlaybackState> Function()>>('playback_get_state_ptr');
    playbackGetStatePtr = _playbackGetStatePtr.asFunction<ffi.Pointer<NativePlaybackState> Function()>();

    _playbackSetSectionLoopsNumPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('playback_set_section_loops_num');
    playbackSetSectionLoopsNum = _playbackSetSectionLoopsNumPtr.asFunction<void Function(int, int)>();

    _switchToSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>>('switch_to_section');
    switchToSection = _switchToSectionPtr.asFunction<void Function(int)>();

    // Recording
    _recordingStartPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>>('recording_start');
    recordingStart = _recordingStartPtr.asFunction<int Function(ffi.Pointer<ffi.Char>)>();
    _recordingStopPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('recording_stop');
    recordingStop = _recordingStopPtr.asFunction<void Function()>();
    _recordingIsActivePtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('recording_is_active');
    recordingIsActive = _recordingIsActivePtr.asFunction<int Function()>();
  }

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _playbackInitPtr;
  late final int Function() playbackInit;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _playbackCleanupPtr;
  late final void Function() playbackCleanup;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32)>> _playbackStartPtr;
  late final int Function(int, int) playbackStart;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _playbackStopPtr;
  late final void Function() playbackStop;


  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _playbackSetBpmPtr;
  late final void Function(int) playbackSetBpm;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>> _playbackSetRegionPtr;
  late final void Function(int, int) playbackSetRegion;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _playbackSetModePtr;
  late final void Function(int) playbackSetMode;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<NativePlaybackState> Function()>> _playbackGetStatePtr;
  late final ffi.Pointer<NativePlaybackState> Function() playbackGetStatePtr;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>> _playbackSetSectionLoopsNumPtr;
  late final void Function(int, int) playbackSetSectionLoopsNum;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32)>> _switchToSectionPtr;
  late final void Function(int) switchToSection;

  // Recording
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>> _recordingStartPtr;
  late final int Function(ffi.Pointer<ffi.Char>) recordingStart;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _recordingStopPtr;
  late final void Function() recordingStop;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _recordingIsActivePtr;
  late final int Function() recordingIsActive;
}


