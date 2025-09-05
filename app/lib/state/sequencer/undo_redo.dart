import 'dart:ffi' as ffi;
import 'package:flutter/foundation.dart';
import '../../ffi/undo_redo_bindings.dart';

/// Placeholder undo/redo state for V2
/// Provides ValueNotifiers for UI binding and no-op methods to be implemented later
class UndoRedoState extends ChangeNotifier {
  bool _canUndo = false;
  bool _canRedo = false;

  final ValueNotifier<bool> canUndoNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canRedoNotifier = ValueNotifier<bool>(false);

  UndoRedoState() {
    UndoRedoFfi.init();
  }

  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;

  void _setCanUndo(bool value) {
    if (_canUndo == value) return;
    _canUndo = value;
    canUndoNotifier.value = value;
    notifyListeners();
  }

  void _setCanRedo(bool value) {
    if (_canRedo == value) return;
    _canRedo = value;
    canRedoNotifier.value = value;
    notifyListeners();
  }

  // Seqlock reader for public undo/redo state; call from your app tick if desired.
  void syncFromNative() {
    final ffi.Pointer<NativePublicUndoRedoState> ptr = UndoRedoFfi.getStatePtr();
    int tries = 0;
    while (true) {
      final v1 = ptr.ref.version;
      if ((v1 & 1) != 0) {
        if (++tries >= 3) return;
        continue;
      }
      final canUndo = ptr.ref.can_undo != 0;
      final canRedo = ptr.ref.can_redo != 0;
      final v2 = ptr.ref.version;
      if (v1 == v2) {
        _setCanUndo(canUndo);
        _setCanRedo(canRedo);
        break;
      }
      if (++tries >= 3) return;
    }
  }

  void undo() {
    UndoRedoFfi.undo();
  }

  void redo() {
    UndoRedoFfi.redo();
  }

  @override
  void dispose() {
    canUndoNotifier.dispose();
    canRedoNotifier.dispose();
    super.dispose();
  }
}


