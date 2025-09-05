import 'dart:ffi' as ffi;

import 'native_library.dart';

// Dart FFI mirror of PublicUndoRedoState
final class NativePublicUndoRedoState extends ffi.Struct {
  @ffi.Uint32()
  external int version;

  @ffi.Int32()
  external int count;

  @ffi.Int32()
  external int cursor;

  @ffi.Int32()
  external int can_undo;

  @ffi.Int32()
  external int can_redo;
}

typedef _CInit = ffi.Void Function();
typedef _CClear = ffi.Void Function();
typedef _CCan = ffi.Int32 Function();
typedef _CAction = ffi.Int32 Function();

class UndoRedoFfi {
  UndoRedoFfi._();

  static final ffi.DynamicLibrary _lib = NativeLibrary.instance;

  static final _initPtr = _lib.lookup<ffi.NativeFunction<_CInit>>("UndoRedoManager_init");
  static final _clearPtr = _lib.lookup<ffi.NativeFunction<_CClear>>("UndoRedoManager_clear");
  static final _canUndoPtr = _lib.lookup<ffi.NativeFunction<_CCan>>("UndoRedoManager_canUndo");
  static final _canRedoPtr = _lib.lookup<ffi.NativeFunction<_CCan>>("UndoRedoManager_canRedo");
  static final _undoPtr = _lib.lookup<ffi.NativeFunction<_CAction>>("UndoRedoManager_undo");
  static final _redoPtr = _lib.lookup<ffi.NativeFunction<_CAction>>("UndoRedoManager_redo");
  static final _getStatePtr = _lib.lookup<ffi.NativeFunction<ffi.Pointer<NativePublicUndoRedoState> Function()>>("UndoRedoManager_get_state_ptr");

  static void init() => _initPtr.asFunction<void Function()>()();
  static void clear() => _clearPtr.asFunction<void Function()>()();
  static bool canUndo() => _canUndoPtr.asFunction<int Function()>()() != 0;
  static bool canRedo() => _canRedoPtr.asFunction<int Function()>()() != 0;
  static bool undo() => _undoPtr.asFunction<int Function()>()() != 0;
  static bool redo() => _redoPtr.asFunction<int Function()>()() != 0;

  static ffi.Pointer<NativePublicUndoRedoState> getStatePtr() => _getStatePtr.asFunction<ffi.Pointer<NativePublicUndoRedoState> Function()>()();
}


