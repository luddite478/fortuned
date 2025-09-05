import 'dart:ffi' as ffi;

import 'native_library.dart';

// Native CellSettings structure matching C definition
final class CellSettings extends ffi.Struct {
  @ffi.Float()
  external double volume;

  @ffi.Float()
  external double pitch;
}

// Native Cell structure matching C definition
final class Cell extends ffi.Struct {
  @ffi.Int32()
  external int sample_slot;

  external CellSettings settings;
}

// Native Section structure matching C definition
final class Section extends ffi.Struct {
  @ffi.Int32()
  external int start_step;

  @ffi.Int32()
  external int num_steps;
}

// Native Layer structure matching C definition
final class Layer extends ffi.Struct {
  @ffi.Int32()
  external int len;
}

// Native PublicTableState structure for seqlock pattern
final class NativeTableState extends ffi.Struct {
  @ffi.Uint32()
  external int version;

  @ffi.Int32()
  external int sections_count;

  external ffi.Pointer<Cell> table_ptr;
  external ffi.Pointer<Section> sections_ptr;
  external ffi.Pointer<Layer> layers_ptr;
}

/// Data holder for section updates (used for bulk section updates)
class SectionData {
  final int startStep;
  final int numSteps;
  const SectionData({required this.startStep, required this.numSteps});
}

// Helper class to wrap cell data for Flutter consumption
class CellData {
  final int sampleSlot;
  final double volume;
  final double pitch;

  const CellData({
    required this.sampleSlot,
    required this.volume,
    required this.pitch,
  });

  factory CellData.fromPointer(ffi.Pointer<Cell> cellPtr) {
    if (cellPtr == ffi.nullptr) {
      return const CellData(
        sampleSlot: -1,
        volume: 1.0,
        pitch: 1.0,
      );
    }

    final cell = cellPtr.ref;
    return CellData(
      sampleSlot: cell.sample_slot,
      volume: cell.settings.volume,
      pitch: cell.settings.pitch,
    );
  }

  bool get isEmpty => sampleSlot == -1;
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CellData &&
        other.sampleSlot == sampleSlot &&
        other.volume == volume &&
        other.pitch == pitch;
  }

  @override
  int get hashCode {
    return Object.hash(sampleSlot, volume, pitch);
  }

  @override
  String toString() {
    if (isEmpty) return 'CellData(empty)';
    return 'CellData(slot: $sampleSlot, vol: ${volume.toStringAsFixed(2)}, pitch: ${pitch.toStringAsFixed(2)})';
  }
}

/// FFI bindings for native table functions
class TableBindings {
  TableBindings() {
    final lib = NativeLibrary.instance;

    _tableInitPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function()>>('table_init');
    tableInit = _tableInitPtr.asFunction<void Function()>();

    _tableGetCellPtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<Cell> Function(ffi.Int32, ffi.Int32)>>('table_get_cell');
    tableGetCell = _tableGetCellPtr.asFunction<ffi.Pointer<Cell> Function(int, int)>();

    _tableSetCellPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32)>>('table_set_cell');
    tableSetCell = _tableSetCellPtr.asFunction<void Function(int, int, int, double, double, int)>();
    _tableSetCellSettingsPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32)>>('table_set_cell_settings');
    tableSetCellSettings = _tableSetCellSettingsPtr.asFunction<void Function(int, int, double, double, int)>();
    _tableSetCellSampleSlotPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>>('table_set_cell_sample_slot');
    tableSetCellSampleSlot = _tableSetCellSampleSlotPtr.asFunction<void Function(int, int, int, int)>();

    _tableClearCellPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>('table_clear_cell');
    tableClearCell = _tableClearCellPtr.asFunction<void Function(int, int, int)>();

    _tableInsertStepPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>('table_insert_step');
    tableInsertStep = _tableInsertStepPtr.asFunction<void Function(int, int, int)>();

    _tableDeleteStepPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>('table_delete_step');
    tableDeleteStep = _tableDeleteStepPtr.asFunction<void Function(int, int, int)>();

    // getters
    _tableGetMaxStepsPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('table_get_max_steps');
    tableGetMaxSteps = _tableGetMaxStepsPtr.asFunction<int Function()>();

    _tableGetMaxColsPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('table_get_max_cols');
    tableGetMaxCols = _tableGetMaxColsPtr.asFunction<int Function()>();

    _tableGetSectionsCountPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function()>>('table_get_sections_count');
    tableGetSectionsCount = _tableGetSectionsCountPtr.asFunction<int Function()>();



    _tableGetSectionStartStepPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>>('table_get_section_start_step');
    tableGetSectionStartStep = _tableGetSectionStartStepPtr.asFunction<int Function(int)>();

    _tableGetSectionStepCountPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>>('table_get_section_step_count');
    tableGetSectionStepCount = _tableGetSectionStepCountPtr.asFunction<int Function(int)>();

    _tableGetSectionAtStepPtr = lib.lookup<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>>('table_get_section_at_step');
    tableGetSectionAtStep = _tableGetSectionAtStepPtr.asFunction<int Function(int)>();

    // section management
    _tableSetSectionStepCountPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>('table_set_section_step_count');
    tableSetSectionStepCount = _tableSetSectionStepCountPtr.asFunction<void Function(int, int, int)>();

    // State pointer getter
    _tableGetStatePtrPtr = lib.lookup<ffi.NativeFunction<ffi.Pointer<NativeTableState> Function()>>('table_get_state_ptr');
    tableGetStatePtr = _tableGetStatePtrPtr.asFunction<ffi.Pointer<NativeTableState> Function()>();

    // Optional: section creation (if provided by native)
    _tableAppendSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>('table_append_section');
    tableAppendSection = _tableAppendSectionPtr!.asFunction<void Function(int, int, int)>();
    _tableDeleteSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>('table_delete_section');
    tableDeleteSection = _tableDeleteSectionPtr!.asFunction<void Function(int, int)>();
    // New single setters for batch updates
    _tableSetSectionPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>>('table_set_section');
    tableSetSection = _tableSetSectionPtr.asFunction<void Function(int, int, int, int)>();

    _tableSetLayerLenPtr = lib.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>>('table_set_layer_len');
    tableSetLayerLen = _tableSetLayerLenPtr.asFunction<void Function(int, int, int, int)>();
  }

  // pointers
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> _tableInitPtr;
  late final void Function() tableInit;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<Cell> Function(ffi.Int32, ffi.Int32)>> _tableGetCellPtr;
  late final ffi.Pointer<Cell> Function(int, int) tableGetCell;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32)>> _tableSetCellPtr;
  late final void Function(int, int, int, double, double, int) tableSetCell;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Float, ffi.Float, ffi.Int32)>> _tableSetCellSettingsPtr;
  late final void Function(int, int, double, double, int) tableSetCellSettings;
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>> _tableSetCellSampleSlotPtr;
  late final void Function(int, int, int, int) tableSetCellSampleSlot;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>> _tableClearCellPtr;
  late final void Function(int, int, int) tableClearCell;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>> _tableInsertStepPtr;
  late final void Function(int, int, int) tableInsertStep;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>> _tableDeleteStepPtr;
  late final void Function(int, int, int) tableDeleteStep;

  // getters
  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _tableGetMaxStepsPtr;
  late final int Function() tableGetMaxSteps;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _tableGetMaxColsPtr;
  late final int Function() tableGetMaxCols;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function()>> _tableGetSectionsCountPtr;
  late final int Function() tableGetSectionsCount;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _tableGetSectionStartStepPtr;
  late final int Function(int) tableGetSectionStartStep;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _tableGetSectionStepCountPtr;
  late final int Function(int) tableGetSectionStepCount;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Int32 Function(ffi.Int32)>> _tableGetSectionAtStepPtr;
  late final int Function(int) tableGetSectionAtStep;

  // section management
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>> _tableSetSectionStepCountPtr;
  late final void Function(int, int, int) tableSetSectionStepCount;

  // State pointer getter
  late final ffi.Pointer<ffi.NativeFunction<ffi.Pointer<NativeTableState> Function()>> _tableGetStatePtrPtr;
  late final ffi.Pointer<NativeTableState> Function() tableGetStatePtr;

  // Optional native: append a new section with given number of steps
  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32)>>? _tableAppendSectionPtr;
  void Function(int, int, int)? tableAppendSection; // (steps, copyFromSection or -1, undo)

  ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32)>>? _tableDeleteSectionPtr;
  void Function(int, int)? tableDeleteSection; // (sectionIndex, undo)
  // Single setters for batch updates
  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>> _tableSetSectionPtr;
  late final void Function(int, int, int, int) tableSetSection;

  late final ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32)>> _tableSetLayerLenPtr;
  late final void Function(int, int, int, int) tableSetLayerLen;
}


