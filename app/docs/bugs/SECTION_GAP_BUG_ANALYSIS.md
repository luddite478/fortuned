# Section Gap Bug - Root Cause Analysis

**Date:** November 16, 2025  
**Severity:** 🔴 **CRITICAL** - Causes playback desynchronization  
**Status:** 🟡 **IN PROGRESS** - Fix implemented but issue persists, further investigation needed

---

## Problem Statement

When transitioning between sections during playback, there are **GAPS** in the step sequence:
- Section 8 ends at step 138
- Section 9 starts at step 144
- **Missing steps: 139, 140, 141, 142, 143 (5-step gap!)**

This causes the playback position calculation to be incorrect, making the sequencer think it's already 5 steps into section 9 when it should be at the first step.

---

## Root Cause

### The Bug Location

**File:** `app/native/table.mm`  
**Function:** `table_set_section_step_count()` (lines 336-358)

```cpp
void table_set_section_step_count(int section_index, int steps, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        state_write_begin();
        g_table_state.sections[section_index].num_steps = steps;  // ⚠️ ONLY UPDATES num_steps
        state_write_end();
        
        // ❌ MISSING: Recalculation of start_step for subsequent sections!
        
        prnt("📏 [TABLE] Set section %d step count to %d", section_index, steps);
        
        // Recreate SunVox pattern with new size
        sunvox_wrapper_create_section_pattern(section_index, steps);
        
        if (undo_record) {
            UndoRedoManager_record();
        }
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}
```

**The Problem:** This function updates `num_steps` but **NEVER recalculates `start_step` values** for subsequent sections!

---

## How the Bug is Triggered

### Scenario 1: Project Import (MOST COMMON)

**File:** `app/lib/services/snapshot/import.dart`  
**Function:** `_importTableState()` (lines 242-349)

**Import Flow:**
1. **Delete all sections except section 0** (line 63-65)
   ```dart
   for (int i = currentSections - 1; i > 0; i--) {
     _tableState.deleteSection(i, undoRecord: false);
   }
   ```

2. **Append sections to reach target count** (lines 268-272)
   ```dart
   for (int i = currentCount; i < sectionsCount; i++) {
     _tableState.appendSection(undoRecord: false);
   }
   ```
   - At this point, sections have contiguous `start_step` values ✅
   - Section 0: start=0, steps=16
   - Section 1: start=16, steps=16
   - Section 2: start=32, steps=16
   - Section 3: start=48, steps=16
   - etc.

3. **Set section step counts from imported data** (lines 276-282)
   ```dart
   for (int i = 0; i < sections.length; i++) {
     final sectionData = sections[i] as Map<String, dynamic>;
     final numSteps = sectionData['num_steps'] as int;
     _tableState.setSectionStepCount(i, numSteps, undoRecord: false);
   }
   ```
   - This calls `table_set_section_step_count()` for each section
   - **BUG**: Only `num_steps` is updated, `start_step` remains unchanged! ❌

**Result After Import:**
```
Section 0: start=0,  steps=16 (updated from 16)  ✅ No gap
Section 1: start=16, steps=8  (updated from 16)  ✅ No gap yet
Section 2: start=32, steps=20 (updated from 16)  ❌ Should be start=24! GAP OF 8 STEPS!
Section 3: start=48, steps=16 (updated from 16)  ❌ Should be start=44! GAP OF 4 STEPS!
Section 4: start=64, steps=12 (updated from 16)  ❌ Gaps accumulate...
```

**The Math:**
- Section 0: [0-15]    (16 steps)
- Section 1: [16-23]   (8 steps)
- **Gap:**   [24-31]   (8 missing steps!)
- Section 2: [32-51]   (20 steps) - starts at 32 instead of 24!
- **Gap:**   [52-55]   (4 missing steps!)
- Section 3: [56-71]   (16 steps) - starts at 56 instead of 52!

---

### Scenario 2: Manual Section Step Count Changes

When a user manually changes a section's step count via the UI:
1. Calls `setSectionStepCount()` on one section
2. `num_steps` is updated for that section
3. **All subsequent sections keep their old `start_step` values** ❌
4. Gaps appear immediately

---

### Scenario 3: Undo/Redo

When undo/redo applies a state that has different section step counts:
1. Calls `table_apply_state()` which directly copies the snapshot
2. If the snapshot was created when gaps already existed, the gaps are preserved
3. **Undo/redo can restore a buggy state!**

---

## Why Delete/Reorder Don't Cause This Bug

Looking at other section operations, they correctly handle `start_step`:

### ✅ `table_delete_section()` (lines 443-508)
```cpp
// After shifting sections, ALWAYS recalculates start_step
int cursor = 0;
for (int i = 0; i < g_table_state.sections_count; i++) {
    g_table_state.sections[i].start_step = cursor;  // ✅ Recalculated!
    cursor += g_table_state.sections[i].num_steps;
}
```

### ✅ `table_reorder_section()` (lines 510-640)
```cpp
// After reordering, ALWAYS recalculates start_step
for (int i = 0; i < g_table_state.sections_count; i++) {
    // ... copy data ...
    g_table_state.sections[i].start_step = cursor;  // ✅ Recalculated!
    cursor += section_steps;
}
```

### ✅ `table_append_section()` (lines 360-441)
```cpp
// Calculates start step for new section at the end
int start = 0;
for (int i = 0; i < g_table_state.sections_count; i++) {
    start += g_table_state.sections[i].num_steps;  // ✅ Correctly calculated!
}
```

**Why they work:** These functions all use a **cursor-based calculation** that walks through sections and accumulates `start_step` values. This ensures sections are always contiguous.

**Why `setSectionStepCount()` doesn't work:** It only updates the **local** section's `num_steps` and forgets about all subsequent sections!

---

## Impact

### 🔴 Critical Issues
1. **Playback Position Desync:** Step counter jumps ahead when entering a section after a gap
2. **Audio-Visual Mismatch:** What you hear doesn't match what you see in the UI
3. **Data Integrity:** Gaps waste memory (unused cells in table) and confuse debugging
4. **Cumulative Effect:** Gaps accumulate across multiple sections, making the problem worse

### Example from Logs
```
Section 8: Steps [128-138] (11 steps)
  👉 Last step played: 138
Section 9: Steps [144-159] (16 steps)  ⚠️ Should start at 139!
  👉 First step played: 149 (actually step 5 of section 9!)
  
Gap: [139-143] = 5 steps lost!
```

---

## The Fix

### Option 1: Fix `table_set_section_step_count()` (RECOMMENDED)

Add start_step recalculation after changing num_steps:

```cpp
void table_set_section_step_count(int section_index, int steps, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        int old_steps = g_table_state.sections[section_index].num_steps;
        int step_delta = steps - old_steps;
        
        state_write_begin();
        g_table_state.sections[section_index].num_steps = steps;
        
        // ✅ FIX: Recalculate start_step for all subsequent sections
        if (step_delta != 0) {
            for (int i = section_index + 1; i < g_table_state.sections_count; i++) {
                g_table_state.sections[i].start_step += step_delta;
            }
        }
        
        state_write_end();
        
        prnt("📏 [TABLE] Set section %d step count to %d (delta: %+d)", 
             section_index, steps, step_delta);
        
        // Recreate SunVox pattern with new size
        sunvox_wrapper_create_section_pattern(section_index, steps);
        
        if (undo_record) {
            UndoRedoManager_record();
        }
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}
```

**Pro:** Fixes the root cause, simple delta-based update  
**Con:** Assumes sections were contiguous before (may not fix existing corrupted data)

---

### Option 2: Add Full Compaction Helper (SAFEST)

Create a helper function that fully recalculates all start_step values:

```cpp
// Helper: Recompute all section start_step values to ensure contiguous layout
static void table_compact_sections(void) {
    int cursor = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        g_table_state.sections[i].start_step = cursor;
        cursor += g_table_state.sections[i].num_steps;
    }
    prnt("🔧 [TABLE] Compacted sections: %d sections, total steps: %d", 
         g_table_state.sections_count, cursor);
}

void table_set_section_step_count(int section_index, int steps, int undo_record) {
    if (section_index < 0 || section_index >= g_table_state.sections_count) {
        prnt_err("❌ [TABLE] Invalid section index: %d", section_index);
        return;
    }
    
    if (steps > 0 && steps <= MAX_SEQUENCER_STEPS) {
        state_write_begin();
        g_table_state.sections[section_index].num_steps = steps;
        
        // ✅ FIX: Fully recompute all start_step values
        table_compact_sections();
        
        state_write_end();
        
        prnt("📏 [TABLE] Set section %d step count to %d", section_index, steps);
        
        // Recreate SunVox pattern with new size
        sunvox_wrapper_create_section_pattern(section_index, steps);
        
        if (undo_record) {
            UndoRedoManager_record();
        }
    } else {
        prnt_err("❌ [TABLE] Invalid steps count: %d", steps);
    }
}
```

**Pro:** 
- Fixes existing corrupted data automatically
- Guaranteed correct regardless of previous state
- Can be called after import to fix loaded data

**Con:** 
- Slightly more expensive (O(n) instead of O(n) but simpler)
- Recalculates even sections that don't need it

---

### Option 3: Fix During Import (BAND-AID)

Add compaction call after importing section step counts in `import.dart`:

```dart
// After setting all step counts, compact to fix any gaps
for (int i = 0; i < sections.length; i++) {
  final sectionData = sections[i] as Map<String, dynamic>;
  final numSteps = sectionData['num_steps'] as int;
  _tableState.setSectionStepCount(i, numSteps, undoRecord: false);
}

// ✅ FIX: Compact sections to remove gaps
_tableState.compactSections();  // New function that calls table_compact_sections()
```

**Pro:** Quick fix for the most common scenario  
**Con:** Doesn't fix manual edits or other scenarios

---

## Recommended Solution

**Implement Option 2** (Full Compaction Helper) because:
1. ✅ Fixes the root cause completely
2. ✅ Self-healing - fixes existing corrupted data
3. ✅ Simple and robust
4. ✅ Reusable - can be called from anywhere
5. ✅ Low performance cost (sections array is small, max 64 entries)

---

## Testing Strategy

### 1. Reproduce the Bug
```
1. Create a project with multiple sections
2. Set different step counts for each section
3. Save the project
4. Load the project
5. Enable enhanced playback logging
6. Play through sections - observe gaps in logs
```

### 2. Verify the Fix
```
1. Apply the fix to table_set_section_step_count()
2. Load a corrupted project (with gaps)
3. Check enhanced playback logs:
   - All sections should be contiguous
   - No gaps between sections
   - Step counter should increment smoothly at boundaries
```

### 3. Regression Test
```
1. Test section delete - should still work ✅
2. Test section reorder - should still work ✅  
3. Test section append - should still work ✅
4. Test undo/redo - should work without gaps ✅
5. Test manual step count changes - should work ✅
```

---

## Prevention

### Add Validation
Add a function to detect and report gaps:

```cpp
void table_validate_sections(const char* context) {
    int expected_start = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        if (g_table_state.sections[i].start_step != expected_start) {
            prnt_err("⚠️ [TABLE] Section gap detected at section %d (context: %s)", i, context);
            prnt_err("   Expected start: %d, actual: %d, gap: %d steps",
                     expected_start,
                     g_table_state.sections[i].start_step,
                     g_table_state.sections[i].start_step - expected_start);
        }
        expected_start += g_table_state.sections[i].num_steps;
    }
}
```

Call this after every section modification during development.

---

## Related Files

### Native (C++)
- `app/native/table.mm` - Section management (BUG HERE)
- `app/native/table.h` - Section structure definitions
- `app/native/playback_sunvox.mm` - Playback position calculation (affected by bug)

### Flutter (Dart)
- `app/lib/services/snapshot/import.dart` - Project loading (triggers bug)
- `app/lib/state/sequencer/table.dart` - Table state management

---

## 🎉 Fix Implementation

**Date Implemented:** November 16, 2025  
**Implementation:** Complete and tested

### Solution: `table_recompute_section_starts()`

Created a new helper function that recalculates all section `start_step` values to ensure they are always contiguous:

```cpp
// Helper to recompute all section start_step values to ensure they are contiguous
// This ensures there are no gaps or overlaps in the section ranges
// Call this after any operation that modifies section structure or step counts
static void table_recompute_section_starts(void) {
    int cursor = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        g_table_state.sections[i].start_step = cursor;
        cursor += g_table_state.sections[i].num_steps;
    }
    prnt_debug("🔧 [TABLE] Recomputed section starts (total steps: %d)", cursor);
}
```

### Functions Updated

Added `table_recompute_section_starts()` calls to all functions that modify section structure:

1. ✅ **`table_set_section_step_count()`** - Called after updating `num_steps`
2. ✅ **`table_insert_step()`** - Called after incrementing section length
3. ✅ **`table_delete_step()`** - Called after decrementing section length
4. ✅ **`table_append_section()`** - Called after adding new section
5. ✅ **`table_delete_section()`** - Called after removing section
6. ✅ **`table_reorder_section()`** - Called after reordering sections
7. ✅ **`table_set_section()`** - Called after direct section metadata update

### Self-Healing Property

**Important:** This fix will **automatically repair existing corrupted projects** when you reload them!

- When import calls `setSectionStepCount()` for each section (which happens during project load)
- Each call triggers `table_recompute_section_starts()`
- The gaps are automatically eliminated
- No manual migration or data repair needed!

### Verification

The enhanced playback logging will now show:
- ✅ Contiguous section ranges with no gaps
- ✅ Correct step calculations during playback
- ✅ UI and audio staying in sync

---

---

## 🔍 Current Status Update

**Date:** November 16, 2025 (Updated)  
**Status:** Issue persists after initial fix

### Fix Attempt 1: `table_recompute_section_starts()`

**What was done:**
- Created helper function to recalculate section starts
- Added calls to all 7 functions that modify section structure
- Tested with app rebuild

**Result:** ⚠️ **Issue still persists**

### Next Steps for Investigation

1. **Verify the recompute function is actually being called**
   - Add more logging to `table_recompute_section_starts()` 
   - Check if it's called during project import
   - Verify the computed values are correct

2. **Check if gaps are created elsewhere**
   - Search for other locations that modify `section.start_step` directly
   - Check if there are race conditions during import
   - Verify undo/redo doesn't bypass the fix

3. **Investigate project import flow**
   - Trace exactly how sections are restored from snapshot
   - Check if `table_apply_state` bypasses section management functions
   - Look for direct memory copies that skip recompute

4. **Check SunVox pattern synchronization**
   - Verify SunVox patterns are created with correct sizes
   - Check if pattern indices mismatch with section indices
   - Look for off-by-one errors in pattern/section mapping

### Information Needed

- [ ] Terminal logs with enhanced playback logging after the fix
- [ ] Project message_id for reproducibility
- [ ] Section overview before/after project load
- [ ] Exact steps to reproduce consistently

---

**Analysis by:** AI Assistant + Enhanced Playback Logging  
**Implementation by:** AI Assistant  
**Date:** November 16, 2025  
**Status:** 🟡 In Progress - Further investigation required

