# Effects Architecture for SunVox Integration

## Overview

This document describes how to add effects support to the sequencer, following the same inheritance pattern used for volume and pitch. Effects can be applied at both the sample level (defaults) and cell level (overrides), similar to how volume and pitch currently work.

## SunVox Effects System

### Pattern Event Structure

SunVox pattern events (`sunvox_note`) have the following structure:

```c
typedef struct {
    uint8_t  note;      // NN: 0-127 = note, 128 = note off, 129+ = commands
    uint8_t  vel;       // VV: Velocity 1-129, 0 = default
    uint16_t module;    // MM: 0 = none, 1-65535 = module number + 1
    uint16_t ctl;       // 0xCCEE: CC = controller (1-127), EE = effect code
    uint16_t ctl_val;   // 0xXXYY: controller value or effect parameter
} sunvox_note;
```

### Effects Encoding

- **`ctl` field (0xCCEE)**:
  - `CC` (high byte): Controller number + 1 (1-127), or 0 for no controller
  - `EE` (low byte): Effect code (standard tracker effects)
  
- **`ctl_val` field (0xXXYY)**:
  - Effect parameter value
  - Format depends on the effect type

### Common SunVox Effects

Standard tracker effects supported by SunVox (EE in 0xCCEE):
- `0x00` - No effect
- `0x01` - Pitch slide up
- `0x02` - Pitch slide down
- `0x03` - Tone portamento (slide to note)
- `0x04` - Vibrato
- `0x05` - Set pitch (fine)
- `0x06` - Set pitch (coarse)
- `0x07` - Volume slide
- `0x08` - Panning
- `0x09` - Sample offset
- `0x0A` - Volume slide + vibrato
- `0x0B` - Position jump
- `0x0C` - Set volume
- `0x0D` - Pattern break
- `0x0E` - Pattern delay
- `0x0F` - Retrigger note
- `0x10` - Speed (BPM/tempo)
- `0x11` - Arpeggio
- `0x19` - Retrigger with volume slide
- `0x1F` - Set BPM
- `0x33` - Sync
- ... and more (full list in SunVox documentation)

### Module Controllers vs Pattern Effects

**Important distinction:**

1. **Pattern Effects** (0xCCEE in pattern events):
   - Applied per-cell/note event
   - Stored in pattern data
   - Examples: pitch slide, vibrato, retrigger, volume slide
   - Perfect for per-cell effects

2. **Module Controllers** (via `sv_set_module_ctl_value()`):
   - Applied globally to a module (affects all notes)
   - Examples: reverb, delay, filter cutoff on a sampler module
   - Better for sample-level effects that affect all instances

## Recommended Architecture

### Follow the Volume/Pitch Pattern

Effects should follow the **exact same inheritance pattern** as volume and pitch:

1. **Sample-level effects (defaults)**:
   - Stored in `SampleSettings` (in `sample_bank.h`)
   - Apply to all cells using that sample (unless overridden)
   - Changed via sample bank API

2. **Cell-level effects (overrides)**:
   - Stored in `CellSettings` (in `table.h`)
   - Take precedence over sample defaults
   - Use sentinel value (`-1` or `0`) for "inherit from sample"

### Data Structure Changes

#### 1. Extend `CellSettings` (in `table.h`)

```c
// Cell audio settings
typedef struct {
    float volume;               // 0.0 to 1.0, or DEFAULT_CELL_VOLUME (-1.0) to inherit
    float pitch;                // PITCH_MIN_RATIO..PITCH_MAX_RATIO, or DEFAULT_CELL_PITCH (-1.0) to inherit
    
    // NEW: Effects
    uint16_t effect_code;       // Effect code (EE), or DEFAULT_CELL_EFFECT (0) to inherit
    uint16_t effect_param;      // Effect parameter (XXYY), or DEFAULT_CELL_EFFECT_PARAM (0) to inherit
} CellSettings;
```

**Constants:**
```c
#define DEFAULT_CELL_EFFECT        0      // Inherit effect from sample
#define DEFAULT_CELL_EFFECT_PARAM  0      // Inherit parameter from sample
```

#### 2. Extend `SampleSettings` (in `sample_bank.h`)

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

### Implementation Strategy

#### Option A: Single Effect Per Cell (Recommended for MVP)

**Simplest approach**: One effect per cell, stored as `(effect_code, effect_param)`.

**Pros:**
- Simple to implement
- Matches tracker paradigm (one effect column per track)
- Easy to serialize/store
- Works with both `sv_set_pattern_event()` and `sv_send_event()`

**Cons:**
- Can't combine multiple effects per cell
- May need expansion later for advanced use cases

**Encoding in SunVox:**
```c
// When setting pattern event:
sv_set_pattern_event(
    slot, pat_id, track, line,
    note,        // nn
    velocity,    // vv
    module + 1,  // mm
    effect_code, // ccee (low byte = EE, high byte = CC, 0 = no controller)
    effect_param // xxyy
);
```

#### Option B: Multiple Effects (Future Enhancement)

If you need multiple effects per cell, you could:
- Use multiple effect columns (requires more tracks)
- Chain effects via modules (more complex)
- Use module controllers for global effects

**Recommendation**: Start with Option A, expand later if needed.

### Integration Points

#### 1. Pattern Event Sync (`sunvox_wrapper_sync_cell`)

Current code:
```c
sv_set_pattern_event(
    SUNVOX_SLOT,
    pat_id,
    col,
    local_line,
    final_note,          // note
    velocity,            // velocity
    mod_id + 1,          // module
    0,                   // no controller/effect ← CHANGE THIS
    0                    // no parameter ← CHANGE THIS
);
```

**New code:**
```c
// Resolve effect from cell or sample settings
uint16_t effect_code = cell->settings.effect_code;
uint16_t effect_param = cell->settings.effect_param;

if (effect_code == DEFAULT_CELL_EFFECT) {
    // Inherit from sample
    Sample* s = sample_bank_get_sample(cell->sample_slot);
    if (s && s->loaded) {
        effect_code = s->settings.effect_code;
        effect_param = s->settings.effect_param;
    } else {
        effect_code = 0;  // No effect
        effect_param = 0;
    }
}

sv_set_pattern_event(
    SUNVOX_SLOT,
    pat_id,
    col,
    local_line,
    final_note,
    velocity,
    mod_id + 1,
    effect_code,         // ccee (0xCCEE format)
    effect_param         // xxyy (0xXXYY format)
);
```

#### 2. Live Preview (`sunvox_preview_cell`)

Current code uses `sv_send_event()`:
```c
sv_send_event(
    SUNVOX_SLOT,
    track,
    note,
    vel,
    mod_id + 1,
    0,    // no controller/effect ← CHANGE THIS
    0     // no parameter ← CHANGE THIS
);
```

**New code:**
```c
// Resolve effect (same logic as above)
uint16_t effect_code = ...;
uint16_t effect_param = ...;

sv_send_event(
    SUNVOX_SLOT,
    track,
    note,
    vel,
    mod_id + 1,
    effect_code,    // ccee
    effect_param    // xxyy
);
```

**Note**: `sv_send_event()` accepts effects the same way as `sv_set_pattern_event()`, so effects work for live preview!

#### 3. Section Sync (`sunvox_wrapper_sync_section`)

Apply the same effect resolution logic when syncing entire sections.

### API Changes

#### Native Layer

**`table.h`:**
```c
// Add to CellSettings:
uint16_t effect_code;
uint16_t effect_param;

// Add constants:
#define DEFAULT_CELL_EFFECT        0
#define DEFAULT_CELL_EFFECT_PARAM  0

// Update table_set_cell signature:
void table_set_cell(int step, int col, int sample_slot, 
                    float volume, float pitch, 
                    uint16_t effect_code, uint16_t effect_param, 
                    int undo_record);

// New: set only cell effects
void table_set_cell_effects(int step, int col, 
                           uint16_t effect_code, uint16_t effect_param, 
                           int undo_record);
```

**`sample_bank.h`:**
```c
// Add to SampleSettings:
uint16_t effect_code;
uint16_t effect_param;

// Update setters:
void sample_bank_set_sample_effects(int slot, uint16_t effect_code, uint16_t effect_param);
```

#### Dart Layer

**`table_bindings.dart`:**
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

**`TableState` (Dart):**
```dart
void setCellSettings(int step, int col, {
  double? volume, 
  double? pitch,
  int? effectCode,    // NEW
  int? effectParam,   // NEW
  bool undoRecord = true
}) {
  // Similar to current implementation
}
```

### Effect Encoding Details

#### Effect Code Format (0xCCEE)

- **CC (high byte)**: Controller number + 1 (1-127), or 0 for no controller
- **EE (low byte)**: Effect code (0x00-0xFF)

**For most effects, CC = 0** (no controller), so:
- `effect_code = 0x0001` = Pitch slide up
- `effect_code = 0x0004` = Vibrato
- `effect_code = 0x000C` = Set volume
- `effect_code = 0x0000` = No effect

**Example with controller:**
- `effect_code = 0x0104` = Controller 1 + Vibrato effect (rare, usually not needed)

#### Effect Parameter Format (0xXXYY)

Most effects use **XXYY** as a single 16-bit value:
- `0x0010` = parameter value 16
- `0x1000` = parameter value 4096

Some effects interpret it differently:
- **Volume slide (0x07)**: `XX` = slide up, `YY` = slide down
- **Panning (0x08)**: `0x0000` = left, `0x8000` = center, `0xFFFF` = right
- **Retrigger (0x0F)**: `XX` = retrigger speed, `YY` = volume

### UI Considerations

1. **Effect Selection**:
   - Dropdown/selector for effect type (Pitch slide, Vibrato, etc.)
   - Parameter slider/input for effect value
   - "None" option = inherit from sample

2. **Inheritance Display**:
   - Show effect label on cell when overridden (like volume/pitch)
   - No label when inheriting from sample

3. **Sample Bank UI**:
   - Add effect controls to sample settings panel
   - Set default effects per sample

### Migration Path

1. **Phase 1**: Add data structures (no UI)
   - Extend `CellSettings` and `SampleSettings`
   - Update serialization/deserialization
   - Set defaults to "no effect" (0)

2. **Phase 2**: Native integration
   - Update `sunvox_wrapper_sync_cell()` to apply effects
   - Update `sunvox_preview_cell()` for live preview
   - Test with hardcoded effects

3. **Phase 3**: Dart API
   - Add setters/getters to `TableState` and `SampleBankState`
   - Update FFI bindings

4. **Phase 4**: UI
   - Add effect controls to cell settings overlay
   - Add effect controls to sample bank panel
   - Update snapshot import/export

### Testing Strategy

1. **Unit Tests**:
   - Effect inheritance (cell → sample → none)
   - Effect encoding/decoding
   - Pattern event sync with effects

2. **Integration Tests**:
   - Live preview with effects
   - Pattern playback with effects
   - Sample-level effect changes propagate to cells

3. **Manual Tests**:
   - Pitch slide effects
   - Vibrato effects
   - Volume slide effects
   - Retrigger effects

## Multiple Effects Per Sound

### Levels of Effects Application

#### 1. **Per-Pattern-Event (Per Cell) - ONE Effect**

At the pattern event level (`sunvox_note` structure), you can only have **ONE effect per note event**:

```c
typedef struct {
    uint8_t  note;
    uint8_t  vel;
    uint16_t module;
    uint16_t ctl;       // ← Only ONE effect field
    uint16_t ctl_val;   // ← Only ONE parameter field
} sunvox_note;
```

**Limitation**: Each pattern event (`sv_set_pattern_event`) stores only one `(ctl, ctl_val)` pair.

**Combined Effects**: Some effect codes combine multiple effects:
- `0x0A` = Volume slide + Vibrato (two effects in one code)
- `0x19` = Retrigger with volume slide (two effects in one code)

#### 2. **Module Chaining - Unlimited Effects**

You can chain effect modules in SunVox's routing graph:

```
Sampler → Reverb → Delay → Filter → Distortion → Output
```

**How it works:**
- Each sampler module can route through multiple effect modules
- Effects are applied sequentially in the chain
- Each effect module processes the audio signal independently
- **No limit** on the number of chained effect modules

**Current Implementation:**
```c
// Currently: Sampler → Output (direct connection)
sv_connect_module(SUNVOX_SLOT, sampler_id, SUNVOX_OUTPUT_MODULE);
```

**Future Enhancement - Add Effect Chain:**
```c
// Example: Add reverb effect module
int reverb_id = sv_new_module(SUNVOX_SLOT, "Reverb", "Reverb", x, y, 0);
sv_connect_module(SUNVOX_SLOT, sampler_id, reverb_id);      // Sampler → Reverb
sv_connect_module(SUNVOX_SLOT, reverb_id, SUNVOX_OUTPUT_MODULE); // Reverb → Output
```

**Pros:**
- Unlimited effects per sample
- Each effect can have its own controls (via `sv_set_module_ctl_value()`)
- Global to all notes from that sampler (affects all cells using that sample)

**Cons:**
- Not per-cell (applies to all instances of the sample)
- More complex routing management
- Requires creating and managing effect modules

#### 3. **Hybrid Approach - Recommended**

Combine both approaches:

1. **Per-Cell Pattern Effects** (ONE per cell):
   - Vibrato, pitch slide, retrigger, volume slide
   - Stored in `CellSettings` / `SampleSettings`
   - Applied via pattern events

2. **Per-Sample Module Effects** (UNLIMITED):
   - Reverb, delay, filter, distortion, compression
   - Created as effect modules, chained after sampler
   - Applied globally to all cells using that sample
   - Controlled via `sv_set_module_ctl_value()`

**Example Architecture:**
```
Sample A:
  Sampler → Reverb → Delay → Output
  (Module chain affects all cells using Sample A)

Cell [3, 5] using Sample A:
  Pattern event: Note + Vibrato effect (0x04)
  (Per-cell effect applied via pattern event)
  
Result: Sample plays with Reverb + Delay (module chain) 
        AND Vibrato (pattern effect)
```

### Recommended Implementation Strategy

#### Phase 1: Per-Cell Pattern Effects (Start Here)
- **ONE effect per cell** (via pattern events)
- Follows volume/pitch pattern
- Simple to implement
- Supports: vibrato, pitch slide, retrigger, volume slide, etc.

#### Phase 2: Per-Sample Module Effects (Future)
- Create effect modules (Reverb, Delay, Filter, etc.)
- Chain them after sampler modules
- Store effect module IDs per sample slot
- Control via module controllers
- Supports: reverb, delay, filter, distortion, compression, etc.

### Data Structure Considerations

**For Phase 1 (Pattern Effects):**
```c
// ONE effect per cell - stored in pattern event
typedef struct {
    float volume;
    float pitch;
    uint16_t effect_code;    // ONE effect code (or 0 = inherit)
    uint16_t effect_param;   // ONE effect parameter
} CellSettings;
```

**For Phase 2 (Module Effects):**
```c
// Effect module chain per sample
typedef struct {
    int effect_module_ids[8];  // IDs of effect modules in chain
    int effect_count;           // Number of effects in chain
} SampleEffectChain;
```

### Answer: How Many Effects?

**Short Answer:**
- **Per cell (pattern event)**: **ONE effect** (or one combined effect like 0x0A)
- **Per sample (module chain)**: **UNLIMITED effects** (via chained modules)

**Practical Answer:**
- Start with **ONE pattern effect per cell** (matches tracker paradigm)
- Add **module effect chains** later for advanced use cases (reverb, delay, etc.)

## Summary

**Recommended approach:**
1. ✅ **Follow volume/pitch pattern** - Same inheritance model
2. ✅ **One pattern effect per cell** - Simple, matches tracker paradigm
3. ✅ **Works with both APIs** - `sv_set_pattern_event()` and `sv_send_event()` support effects
4. ✅ **Effect format** - Use `(effect_code, effect_param)` as `(uint16_t, uint16_t)`
5. ✅ **Sentinel values** - `0` = inherit from sample, `0` = no effect
6. ✅ **Future: Module chains** - Unlimited effects via effect modules (reverb, delay, etc.)

**Effects ARE supported** in both:
- ✅ Pattern events (`sv_set_pattern_event`) - for persistent playback (ONE per cell)
- ✅ Live events (`sv_send_event`) - for preview/triggering (ONE per event)
- ✅ Module chains - unlimited effects via `sv_connect_module()` (future enhancement)

**For your use case**: Start with **ONE pattern effect per cell**. This covers most tracker-style effects (vibrato, pitch slide, retrigger, etc.). Add module effect chains later if you need reverb, delay, or other DSP effects that should apply globally to all instances of a sample.

