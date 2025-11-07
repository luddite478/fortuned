# Effects Implementation Guide: Sample-Level Defaults + Cell-Level Overrides

## Overview

This guide shows how to implement effects using the **exact same pattern** as volume and pitch, ensuring consistency and efficiency.

## Implementation Strategy

### Pattern: Mirror Volume/Pitch Exactly

The resolution logic is identical:
1. Check cell settings first (override)
2. If sentinel value → check sample settings (default)
3. If no sample → use default (0 = no effect)

## Step-by-Step Implementation

### Step 1: Extend Data Structures

#### 1.1 Update `CellSettings` (in `table.h`)

```c
// Cell audio settings
typedef struct {
    float volume;               // 0.0 to 1.0, or DEFAULT_CELL_VOLUME (-1.0) to inherit
    float pitch;                // PITCH_MIN_RATIO..PITCH_MAX_RATIO, or DEFAULT_CELL_PITCH (-1.0) to inherit
    
    // NEW: Effects (same pattern as volume/pitch)
    uint16_t effect_code;       // Effect code (EE), or DEFAULT_CELL_EFFECT (0) to inherit
    uint16_t effect_param;      // Effect parameter (XXYY), or DEFAULT_CELL_EFFECT_PARAM (0) to inherit
} CellSettings;
```

**Add constants:**
```c
#define DEFAULT_CELL_EFFECT        0      // Inherit effect from sample (same as 0 = no effect initially)
#define DEFAULT_CELL_EFFECT_PARAM  0      // Inherit parameter from sample
```

#### 1.2 Update `SampleSettings` (in `sample_bank.h`)

```c
// Sample audio settings
typedef struct {
    float volume;                       // 0.0 to 1.0 (default: 1.0)
    float pitch;                        // 0.25 to 4.0 (default: 1.0)
    
    // NEW: Default effects
    uint16_t effect_code;               // Default effect code (EE), 0 = no effect
    uint16_t effect_param;              // Default effect parameter (XXYY), 0 = no param
} SampleSettings;
```

### Step 2: Create Helper Function for Effect Resolution

**Add to `sunvox_wrapper.mm`:**

```c
// Resolve effect from cell or sample settings (mirrors volume/pitch resolution)
static void resolve_effect(Cell* cell, uint16_t* out_effect_code, uint16_t* out_effect_param) {
    // Start with cell's effect
    uint16_t effect_code = cell->settings.effect_code;
    uint16_t effect_param = cell->settings.effect_param;
    
    // If cell has sentinel value (inherit), get from sample
    if (effect_code == DEFAULT_CELL_EFFECT) {
        Sample* s = sample_bank_get_sample(cell->sample_slot);
        if (s && s->loaded) {
            effect_code = s->settings.effect_code;
            effect_param = s->settings.effect_param;
        } else {
            // No sample or sample not loaded - default to no effect
            effect_code = 0;
            effect_param = 0;
        }
    }
    
    *out_effect_code = effect_code;
    *out_effect_param = effect_param;
}
```

### Step 3: Update `sunvox_wrapper_sync_cell()`

**Current code (lines 348-358):**
```c
int result = sv_set_pattern_event(
    SUNVOX_SLOT,
    pat_id,              // section's pattern
    col,                 // track
    local_line,          // line within pattern
    final_note,          // note
    velocity,            // velocity
    mod_id + 1,          // module (1-indexed)
    0,                   // no controller/effect ← CHANGE THIS
    0                    // no parameter ← CHANGE THIS
);
```

**New code:**
```c
// Resolve effect from cell or sample settings (same pattern as volume/pitch)
uint16_t effect_code, effect_param;
resolve_effect(cell, &effect_code, &effect_param);

int result = sv_set_pattern_event(
    SUNVOX_SLOT,
    pat_id,              // section's pattern
    col,                 // track
    local_line,          // line within pattern
    final_note,          // note
    velocity,            // velocity
    mod_id + 1,          // module (1-indexed)
    effect_code,         // effect code (0xCCEE format)
    effect_param         // effect parameter (0xXXYY format)
);
```

### Step 4: Update `sunvox_wrapper_sync_section()`

**Current code (lines 577-587):**
```c
sv_set_pattern_event(
    SUNVOX_SLOT, 
    pat_id, 
    col, 
    local_line, 
    final_note,        // note
    velocity,          // velocity
    mod_id + 1,        // module
    0,                 // no controller ← CHANGE THIS
    0                  // no controller value ← CHANGE THIS
);
```

**New code:**
```c
// Resolve effect (same pattern as volume/pitch)
uint16_t effect_code, effect_param;
resolve_effect(cell, &effect_code, &effect_param);

sv_set_pattern_event(
    SUNVOX_SLOT, 
    pat_id, 
    col, 
    local_line, 
    final_note,        // note
    velocity,          // velocity
    mod_id + 1,        // module
    effect_code,       // effect code
    effect_param       // effect parameter
);
```

### Step 5: Update `sunvox_preview_cell()`

**Current code (lines 1254):**
```c
int res = sv_send_event(SUNVOX_SLOT, track, note, vel, mod_id + 1, 0, 0);
```

**New code:**
```c
// Resolve effect (same pattern as volume/pitch)
uint16_t effect_code, effect_param;
resolve_effect(cell, &effect_code, &effect_param);

int res = sv_send_event(SUNVOX_SLOT, track, note, vel, mod_id + 1, effect_code, effect_param);
```

### Step 6: Update `sunvox_wrapper_trigger_step()`

**Current code (lines 1037-1046):**
```c
sv_send_event(
    SUNVOX_SLOT,        // slot
    col,                // track/column
    final_note,         // note
    velocity,           // velocity
    mod_id + 1,         // module (sampler ID + 1)
    0,                  // no controller ← CHANGE THIS
    0                   // no controller value ← CHANGE THIS
);
```

**New code:**
```c
// Resolve effect (same pattern as volume/pitch)
uint16_t effect_code, effect_param;
resolve_effect(cell, &effect_code, &effect_param);

sv_send_event(
    SUNVOX_SLOT,        // slot
    col,                // track/column
    final_note,         // note
    velocity,           // velocity
    mod_id + 1,         // module (sampler ID + 1)
    effect_code,        // effect code
    effect_param        // effect parameter
);
```

### Step 7: Update Native API Functions

#### 7.1 Update `table_set_cell()` signature

**In `table.h`:**
```c
void table_set_cell(int step, int col, int sample_slot, 
                    float volume, float pitch, 
                    uint16_t effect_code, uint16_t effect_param, 
                    int undo_record);
```

**In `table.mm`:** Update implementation to store effect_code and effect_param.

#### 7.2 Add `table_set_cell_effects()` function

**In `table.h`:**
```c
// Set only cell effects (preserves volume/pitch)
void table_set_cell_effects(int step, int col, 
                           uint16_t effect_code, uint16_t effect_param, 
                           int undo_record);
```

**In `table.mm`:**
```c
void table_set_cell_effects(int step, int col, 
                           uint16_t effect_code, uint16_t effect_param, 
                           int undo_record) {
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    state_write_begin();
    cell->settings.effect_code = effect_code;
    cell->settings.effect_param = effect_param;
    state_write_end();
    
    // Sync to SunVox immediately
    sunvox_wrapper_sync_cell(step, col);
    
    if (undo_record) {
        UndoRedoManager_record();
    }
}
```

#### 7.3 Update `sample_bank_set_sample_settings()`

**In `sample_bank.h`:**
```c
void sample_bank_set_sample_settings(int slot, float volume, float pitch, 
                                     uint16_t effect_code, uint16_t effect_param);
```

**In `sample_bank.mm`:** Update to store effects and re-sync cells that inherit (same pattern as volume/pitch):
```c
void sample_bank_set_sample_settings(int slot, float volume, float pitch, 
                                     uint16_t effect_code, uint16_t effect_param) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_bank_state.samples[slot].loaded) {
        return;
    }

    // Clamp values
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    if (pitch < 0.25f) pitch = 0.25f;
    if (pitch > 4.0f) pitch = 4.0f;

    state_write_begin();
    g_sample_bank_state.samples[slot].settings.volume = volume;
    g_sample_bank_state.samples[slot].settings.pitch = pitch;
    g_sample_bank_state.samples[slot].settings.effect_code = effect_code;
    g_sample_bank_state.samples[slot].settings.effect_param = effect_param;
    state_write_end();

    // Re-sync all cells using this sample with default effects (same pattern as volume/pitch)
    for (int i = 0; i < table_get_max_steps(); i++) {
        for (int j = 0; j < table_get_max_cols(); j++) {
            Cell* cell = table_get_cell(i, j);
            if (cell && cell->sample_slot == slot && 
                cell->settings.effect_code == DEFAULT_CELL_EFFECT) {
                sunvox_wrapper_sync_cell(i, j);
            }
        }
    }

    UndoRedoManager_record();
}
```

### Step 8: Update Dart/FFI Layer

#### 8.1 Update `CellSettings` FFI struct

**In `table_bindings.dart`:**
```dart
final class CellSettings extends ffi.Struct {
  @ffi.Float()
  external double volume;
  @ffi.Float()
  external double pitch;
  
  // NEW:
  @ffi.Uint16()
  external int effectCode;
  @ffi.Uint16()
  external int effectParam;
}
```

#### 8.2 Update `CellData` class

**In `table_bindings.dart`:**
```dart
class CellData {
  final int sampleSlot;
  final double volume;
  final double pitch;
  final int effectCode;    // NEW
  final int effectParam;   // NEW
  final bool isProcessing;

  const CellData({
    required this.sampleSlot,
    required this.volume,
    required this.pitch,
    required this.effectCode,    // NEW
    required this.effectParam,   // NEW
    required this.isProcessing,
  });

  factory CellData.fromPointer(ffi.Pointer<Cell> cellPtr) {
    if (cellPtr == ffi.nullptr) {
      return const CellData(
        sampleSlot: -1,
        volume: 1.0,
        pitch: 1.0,
        effectCode: 0,     // NEW
        effectParam: 0,   // NEW
        isProcessing: false,
      );
    }

    final cell = cellPtr.ref;
    return CellData(
      sampleSlot: cell.sample_slot,
      volume: cell.settings.volume,
      pitch: cell.settings.pitch,
      effectCode: cell.settings.effectCode,    // NEW
      effectParam: cell.settings.effectParam, // NEW
      isProcessing: cell.is_processing != 0,
    );
  }
  
  // ... rest of class
}
```

#### 8.3 Update `TableState.setCellSettings()`

**In `table.dart`:**
```dart
void setCellSettings(int step, int col, {
  double? volume, 
  double? pitch,
  int? effectCode,    // NEW
  int? effectParam,   // NEW
  bool undoRecord = true
}) {
  final cellPtr = getCellPointer(step, col);
  if (cellPtr.address == 0) return;
  final current = cellPtr.ref;
  
  // Preserve sentinel values if not explicitly set (same pattern as volume/pitch)
  double nextVolume = volume ?? current.settings.volume;
  if (nextVolume >= 0.0) nextVolume = nextVolume.clamp(0.0, 1.0);

  double nextPitch = pitch ?? current.settings.pitch;
  if (nextPitch >= 0.0) nextPitch = nextPitch.clamp(0.03125, 32.0);
  
  // NEW: Effects (preserve sentinel 0 if not set)
  int nextEffectCode = effectCode ?? current.settings.effectCode;
  int nextEffectParam = effectParam ?? current.settings.effectParam;
  
  _table_ffi.tableSetCellSettings(
    step, col, 
    nextVolume, nextPitch, 
    nextEffectCode, nextEffectParam,  // NEW
    undoRecord ? 1 : 0
  );
  
  debugPrint('🎚️ [TABLE_STATE] Set cell settings [$step, $col]: '
             'vol=${nextVolume.toStringAsFixed(2)}, '
             'pitch=${nextPitch.toStringAsFixed(2)}, '
             'effect=0x${nextEffectCode.toRadixString(16)}, '
             'param=0x${nextEffectParam.toRadixString(16)}');
}
```

## Efficient Implementation Summary

### Key Principles

1. **Same Resolution Pattern**: Effects resolve exactly like volume/pitch
   - Cell override → Sample default → No effect (0)

2. **Single Helper Function**: `resolve_effect()` handles all resolution logic
   - Used in sync_cell, sync_section, preview_cell, trigger_step
   - Eliminates code duplication

3. **Sentinel Value**: `0` means "inherit from sample"
   - Same semantic as volume/pitch using `-1.0`
   - `0` is also "no effect", so inheritance defaults to no effect if sample has none

4. **Immediate Sync**: When sample defaults change, only cells that inherit get synced
   - Same efficient pattern as volume/pitch
   - Cells with explicit overrides don't get touched

### Where Effects Are Applied

1. **Pattern Events** (`sv_set_pattern_event`):
   - `sunvox_wrapper_sync_cell()` - Single cell update
   - `sunvox_wrapper_sync_section()` - Full section sync

2. **Live Events** (`sv_send_event`):
   - `sunvox_preview_cell()` - Live preview
   - `sunvox_wrapper_trigger_step()` - Manual triggering

### Benefits of This Approach

✅ **Consistency**: Same pattern as volume/pitch, easy to understand  
✅ **Efficiency**: Single resolution function, no code duplication  
✅ **Performance**: Only syncs cells that actually inherit  
✅ **Flexibility**: Cell overrides work independently of sample defaults  
✅ **Future-proof**: Easy to extend with more effect types later  

## Testing Checklist

- [ ] Cell with explicit effect → uses cell effect
- [ ] Cell with inherited effect (0) → uses sample effect
- [ ] Sample effect changes → inheriting cells update
- [ ] Sample effect changes → non-inheriting cells don't change
- [ ] Preview applies effects correctly
- [ ] Pattern playback applies effects correctly
- [ ] Snapshot import/export preserves effects







