# Sequencer Architecture Overview

**Date:** November 16, 2025  
**Purpose:** Quick reference for understanding how all data structures work together

---

## 🎯 The Big Picture

The sequencer manages **three synchronized data structures** that must stay perfectly aligned:

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER VIEW                               │
│  "Section 0 has 16 steps, Section 1 has 16 steps"              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    NATIVE C++ LAYER                             │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. TABLE - Physical Cell Storage (table.mm)             │  │
│  │    Cell table[2048][128]  ← Contiguous compacted array  │  │
│  │    Row 0-15:   Section 0 data                           │  │
│  │    Row 16-31:  Section 1 data                           │  │
│  │    Row 32-47:  Section 2 data                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↕                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 2. SECTIONS - Logical Metadata                          │  │
│  │    Section sections[64]                                 │  │
│  │    sections[0] = {start_step: 0,  num_steps: 16}       │  │
│  │    sections[1] = {start_step: 16, num_steps: 16}       │  │
│  │    sections[2] = {start_step: 32, num_steps: 16}       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↕                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 3. SUNVOX WRAPPER - Audio Engine Sync                   │  │
│  │    int g_section_patterns[64]  ← Pattern IDs            │  │
│  │    g_section_patterns[0] = 5  (SunVox pattern ID)       │  │
│  │    g_section_patterns[1] = 6                            │  │
│  │    g_section_patterns[2] = 7                            │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    SUNVOX AUDIO ENGINE                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Pattern 5: X=0,  lines=16  (timeline position 0-15)     │  │
│  │ Pattern 6: X=16, lines=16  (timeline position 16-31)    │  │
│  │ Pattern 7: X=32, lines=16  (timeline position 32-47)    │  │
│  │                                                          │  │
│  │ 🎵 Audio callback reads patterns sequentially           │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 Data Structure Details

### 1. TABLE - Physical Storage

**Location:** `app/native/table.mm`  
**Type:** `Cell table[MAX_SEQUENCER_STEPS][MAX_SEQUENCER_COLS]`  
**Size:** 2048 rows × 128 columns = 262,144 cells

**Structure:**
```c
typedef struct {
    int sample_slot;              // Which sample to play (-1 = empty)
    CellSettings settings;        // Volume, pitch
    int is_processing;            // Playback flag
} Cell;
```

**Layout:** Contiguous compacted - all sections packed sequentially with **no gaps**

**Key Operations:**
- `table_insert_step()` - Inserts row, shifts ALL subsequent rows down
- `table_delete_step()` - Deletes row, shifts ALL subsequent rows up
- `table_reorder_section()` - Rebuilds entire table in new section order

**Critical Invariant:** Sections are always contiguous (no gaps between sections)

---

### 2. SECTIONS - Logical Metadata

**Location:** `app/native/table.mm`  
**Type:** `Section sections[MAX_SECTIONS]`  
**Size:** 64 sections max

**Structure:**
```c
typedef struct {
    int start_step;    // First row in table (CALCULATED, not independent!)
    int num_steps;     // How many rows this section occupies
} Section;
```

**Key Function:**
```c
void table_recompute_section_starts(void) {
    int cursor = 0;
    for (int i = 0; i < sections_count; i++) {
        sections[i].start_step = cursor;         // Cumulative sum!
        cursor += sections[i].num_steps;
    }
}
```

**Critical Invariant:** `start_step` is always cumulative sum of all previous `num_steps`

**User-Facing Behavior:**
- ✅ `num_steps` is independent per section
- ✅ Adding step to Section 0 doesn't change Section 1's `num_steps`
- ⚠️ BUT it DOES change Section 1's `start_step` (and physical cell positions)

---

### 3. SUNVOX PATTERNS - Audio Representation

**Location:** `app/native/sunvox_wrapper.mm`  
**Type:** `int g_section_patterns[MAX_SECTIONS]`  
**Size:** 64 pattern IDs

**Mapping:**
```
Section Index → Pattern ID → SunVox Internal Pattern
      0       →      5      →  {X: 0,  lines: 16}
      1       →      6      →  {X: 16, lines: 16}
      2       →      7      →  {X: 32, lines: 16}
```

**Key Operations:**
- `sunvox_wrapper_create_section_pattern()` - Creates/resizes pattern
- `sunvox_wrapper_update_timeline_seamless()` - Updates pattern X positions
- `sunvox_wrapper_sync_section()` - Copies cells to pattern notes

**SunVox Timeline:**
- Each pattern has X position (line offset in global timeline)
- Each pattern has Y position (visual display only, not used for audio)
- Patterns are played sequentially: Pattern 5 (lines 0-15) → Pattern 6 (lines 16-31) → ...

---

## 🔄 How They Stay Synchronized

### When User Adds/Removes Step

```
1. USER ACTION
   User clicks "+" on Section 1 (currently 16 steps)

2. DART LAYER
   Calls native: table_insert_step(section_index: 1, at_step: 25)

3. TABLE LAYER (table.mm)
   ├─ Calculate total_steps = 0+16+16+16 = 48
   ├─ Shift ALL rows from 47 down to 25 → move to 48 down to 26
   │  (This moves Section 2, 3, 4... data down by 1 row)
   ├─ Clear row 25 (new empty step)
   ├─ sections[1].num_steps = 17  (was 16)
   └─ table_recompute_section_starts()
      ├─ sections[0].start_step = 0   (unchanged)
      ├─ sections[1].start_step = 16  (unchanged)
      ├─ sections[2].start_step = 33  (was 32, now +1!)
      ├─ sections[3].start_step = 49  (was 48, now +1!)
      └─ ...

4. SUNVOX LAYER (sunvox_wrapper.mm)
   ├─ sunvox_wrapper_create_section_pattern(1, 17)
   │  ├─ sv_lock_slot()
   │  ├─ sv_set_pattern_size(pattern_id=6, tracks=16, lines=17)
   │  ├─ sunvox_wrapper_sync_section(1)  ← Copy cells to pattern
   │  └─ sv_unlock_slot()
   │
   └─ sunvox_wrapper_update_timeline_seamless(-1)
      ├─ Calculate new X positions:
      │  ├─ Pattern 5 (Section 0): X=0,  lines=16, ends at 16
      │  ├─ Pattern 6 (Section 1): X=16, lines=17, ends at 33 (was 32!)
      │  ├─ Pattern 7 (Section 2): X=33, lines=16, ends at 49 (was 48!)
      │  └─ Pattern 8 (Section 3): X=49, lines=16, ends at 65 (was 64!)
      │
      ├─ Update each pattern: sv_set_pattern_xy(slot, pat_id, new_x, y)
      │
      └─ Adjust playhead if needed: sv_set_position(slot, adjusted_line)
         (All seamless - no audio interruption!)

5. RESULT
   ✅ Table has new row at position 25, all subsequent rows shifted
   ✅ Sections metadata updated (start_step recalculated)
   ✅ SunVox pattern 6 resized from 16 to 17 lines
   ✅ SunVox patterns 7, 8, 9... X positions updated (+1 each)
   ✅ Audio continues playing seamlessly
   ✅ UI shows new step in Section 1
```

---

## 🎹 Example Walkthrough

### Initial State: 3 Sections

**Table (Physical):**
```
Row 0-15:   [Section 0 cells] (16 steps)
Row 16-31:  [Section 1 cells] (16 steps) ← Sample at row 21 (step 5 of Section 1)
Row 32-47:  [Section 2 cells] (16 steps)
```

**Sections (Metadata):**
```
Section 0: {start_step: 0,  num_steps: 16}
Section 1: {start_step: 16, num_steps: 16}
Section 2: {start_step: 32, num_steps: 16}
```

**SunVox (Audio):**
```
Pattern 5 (Section 0): X=0,  lines=16, timeline 0-15
Pattern 6 (Section 1): X=16, lines=16, timeline 16-31
Pattern 7 (Section 2): X=32, lines=16, timeline 32-47
```

---

### Action: Delete 5 Steps from Section 0

**Table (Physical) - After Shift:**
```
Row 0-10:   [Section 0 cells] (11 steps) ← Shrunk by 5
Row 11-26:  [Section 1 cells] (16 steps) ← MOVED UP from 16-31 to 11-26!
            Sample now at row 16 (still step 5 within Section 1!)
Row 27-42:  [Section 2 cells] (16 steps) ← MOVED UP from 32-47 to 27-42!
```

**Sections (Metadata) - After Recompute:**
```
Section 0: {start_step: 0,  num_steps: 11}  ← num_steps changed
Section 1: {start_step: 11, num_steps: 16}  ← start_step changed (was 16)
Section 2: {start_step: 27, num_steps: 16}  ← start_step changed (was 32)
```

**SunVox (Audio) - After Timeline Update:**
```
Pattern 5 (Section 0): X=0,  lines=11, timeline 0-10   ← Resized
Pattern 6 (Section 1): X=11, lines=16, timeline 11-26  ← X changed (was 16)
Pattern 7 (Section 2): X=27, lines=16, timeline 27-42  ← X changed (was 32)
```

**Result:**
- ✅ Section 1 still has 16 steps (num_steps unchanged)
- ✅ Sample in Section 1 still at step 5 (same position within section)
- ✅ But physical row changed: 21 → 16 (compaction!)
- ✅ SunVox pattern X position changed: 16 → 11 (timeline adjusted!)
- ✅ Audio plays correctly (seamless timeline update)

---

## 🔑 Key Principles

### 1. Logical vs Physical Independence

**Logical (User View):**
- ✅ Sections have independent `num_steps`
- ✅ Samples stay at same step within their section
- ✅ Section 1 step 5 is always "Section 1 step 5"

**Physical (Implementation):**
- ⚠️ Cell data is contiguously packed (no gaps)
- ⚠️ `start_step` is calculated (cumulative sum)
- ⚠️ Modifying Section 0 shifts Section 1, 2, 3... physical data

### 2. Synchronization Flow

```
Table Operation (table.mm)
    ↓
1. Modify cell data (shift/insert/delete)
2. Update sections[].num_steps
3. table_recompute_section_starts()  ← Recalc all start_step
    ↓
SunVox Sync (sunvox_wrapper.mm)
    ↓
4. sunvox_wrapper_create_section_pattern()  ← Resize pattern
5. sunvox_wrapper_sync_section()            ← Copy cells to notes
6. sunvox_wrapper_update_timeline_seamless() ← Update X positions
    ↓
Result: All three structures synchronized!
```

### 3. Seamless Operations

**What "Seamless" Means:**
- ✅ Playback continues without interruption
- ✅ No audio dropouts or clicks
- ✅ No rewind to beginning
- ✅ Playhead adjusts smoothly if needed

**How We Achieve It:**
- `sv_lock_slot()` - Prevents audio callback during modifications
- `sv_set_pattern_size()` - Resizes pattern during playback
- `sv_set_pattern_xy()` - Moves pattern without stopping audio
- `sv_set_position()` - Jumps playhead smoothly (not `sv_rewind()`)
- Operations happen between audio callbacks (~5ms window)

---

## 🐛 Common Pitfalls

### ❌ Pitfall 1: Forgetting to Shift Subsequent Sections

**Wrong:**
```cpp
// Only shift within section
for (int step = at_step; step < section_end; step++) {
    table[step][col] = table[step + 1][col];
}
```

**Result:** Section 1 metadata says start=11, but data still at row 16!

**Right:**
```cpp
// Shift entire table from deletion point
for (int step = at_step; step < total_steps - 1; step++) {
    table[step][col] = table[step + 1][col];
}
```

### ❌ Pitfall 2: Forgetting to Update Timeline

**Wrong:**
```cpp
sv_set_pattern_size(pattern_id, tracks, new_lines);
// Return immediately - patterns 7, 8, 9 still have old X positions!
```

**Result:** Section 1 plays, then jumps back 5 steps when Section 2 starts!

**Right:**
```cpp
sv_set_pattern_size(pattern_id, tracks, new_lines);
sunvox_wrapper_update_timeline_seamless(-1);  // Recalc ALL X positions
```

### ❌ Pitfall 3: Using sv_rewind() Instead of sv_set_position()

**Wrong:**
```cpp
sv_rewind(slot, line);  // Stops audio, then restarts!
```

**Result:** Audio interruption, playback restarts from beginning

**Right:**
```cpp
sv_set_position(slot, line);  // Seamless jump, audio continues
```

---

## 📚 Related Documentation

- **`app/native/table.mm`** - Table structure and operations
- **`app/native/sunvox_wrapper.mm`** - SunVox synchronization
- **`seamless_step_resize.md`** - Detailed implementation guide
- **`TABLE_COMPACTION_FIX.md`** - Recent bug fix for cell shifting
- **`seamless_playback.md`** - Seamless mode switching

---

## ✅ Summary

**Three Synchronized Structures:**
1. **Table** - Contiguous physical storage (cells in rows)
2. **Sections** - Logical metadata (start_step calculated from num_steps)
3. **SunVox Patterns** - Audio representation (X positions match start_step)

**Key Operations:**
- Insert/Delete Step → Shift entire table → Recompute positions → Update timeline
- All operations are seamless (no audio interruption)

**Design Principle:**
- Logical independence (sections have independent step counts)
- Physical compaction (contiguous memory, no gaps)
- Perfect synchronization (table, sections, SunVox always aligned)

**Result:** Fast, memory-efficient, seamless audio sequencer! 🎵

