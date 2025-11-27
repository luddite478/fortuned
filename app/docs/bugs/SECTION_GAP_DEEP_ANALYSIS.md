# Section Gap Bug - Deep Analysis
**Date:** November 16, 2025  
**Issue:** Section 10 doesn't start from its first step when transitioning from section 9 in song mode

---

## Summary of Findings

### ✅ Sections Are Contiguous in Table

From both the saved project file and import logs:
- Section 0: start=0, steps=16 (range: 0-15)
- Section 1: start=16, steps=16 (range: 16-31)
- Section 2: start=32, steps=16 (range: 32-47)
- Section 3: start=48, steps=16 (range: 48-63)
- Section 4: start=64, steps=16 (range: 64-79)
- Section 5: start=80, steps=16 (range: 80-95)
- Section 6: start=96, steps=65 (range: 96-160)
- Section 7: start=161, steps=16 (range: 161-176)
- Section 8: start=177, steps=11 (range: 177-187)
- Section 9: start=188, steps=16 (range: 188-203)
- Section 10: start=204, steps=16 (range: 204-219)

**Total: 220 steps, perfectly contiguous** ✅

The `table_recompute_section_starts()` fix is working correctly!

---

## 🔴 Critical Issue Found: Pattern ID Mismatch

### Pattern-to-Section Mapping After Import

From debug.log lines 424-435:
```
Section 0  → Pattern 10  ❌ WRONG!
Section 1  → Pattern 0
Section 2  → Pattern 1
Section 3  → Pattern 2
Section 4  → Pattern 3
Section 5  → Pattern 4
Section 6  → Pattern 5
Section 7  → Pattern 6
Section 8  → Pattern 7
Section 9  → Pattern 8
Section 10 → Pattern 9
```

**Expected mapping:** Section i → Pattern i  
**Actual mapping:** Section 0 → Pattern 10, Section 1-10 → Pattern 0-9

### Root Cause

In `sunvox_wrapper_reset_all_patterns()` (sunvox_wrapper.mm:525-564):

```cpp
void sunvox_wrapper_reset_all_patterns(void) {
    // ...
    // Remove all existing patterns
    sv_lock_slot(SUNVOX_SLOT);
    for (int i = 0; i < num_pattern_slots; i++) {
        int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
        if (lines > 0) {
            sv_remove_pattern(SUNVOX_SLOT, i);  // ❌ This deletes pattern 0!
        }
    }
    sv_unlock_slot(SUNVOX_SLOT);
    
    // Clear all section pattern mappings
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1;  // ❌ Section 0 loses its pattern!
    }
}
```

**What happens during import:**

1. App starts with section 0 having pattern 0
2. `resetAllSunVoxPatterns()` is called (import.dart:45)
   - Pattern 0 is deleted from SunVox
   - `g_section_patterns[0]` is set to -1
3. `appendSection()` is called 10 times to create sections 1-10
   - Section 1 creates pattern 0 (first available ID)
   - Section 2 creates pattern 1
   - ...
   - Section 10 creates pattern 9
4. `setSectionStepCount(0, 16)` is called (import.dart:280)
   - Calls `sunvox_wrapper_create_section_pattern(0, 16)`
   - Sees `g_section_patterns[0] == -1` (no existing pattern)
   - Creates NEW pattern (gets ID 10, first available)
   - `g_section_patterns[0] = 10`

Result: Section 0 gets pattern 10 instead of pattern 0!

---

## Pattern Sizes Are Correct

From sync logs:
- Section 6: 1040 cells = 65 steps × 16 cols ✅
- Section 8: 176 cells = 11 steps × 16 cols ✅  
- Section 9: 256 cells = 16 steps × 16 cols ✅
- Section 10: 256 cells = 16 steps × 16 cols ✅

Patterns have correct sizes matching section step counts.

---

## Timeline Position Calculation

### Playback Code (playback_sunvox.mm:803-826)

```cpp
int timeline_pos = 0;
for (int i = 0; i < sections_count; i++) {
    int section_steps = table_get_section_step_count(i);  // ← Uses TABLE
    if (line >= timeline_pos && line < timeline_pos + section_steps) {
        current_section_from_line = i;
        section_start_step = table_get_section_start_step(i);  // ← Uses TABLE
        break;
    }
    timeline_pos += section_steps;
}
```

**Uses:** `table_get_section_step_count()` and `table_get_section_start_step()`

### SunVox Timeline Layout (sunvox_wrapper.mm:790-796)

```cpp
int timeline_x = 0;
for (int i = 0; i < sections_count; i++) {
    int pat_id = g_section_patterns[i];
    sv_set_pattern_xy(SUNVOX_SLOT, pat_id, timeline_x, i);
    timeline_x += sv_get_pattern_lines(SUNVOX_SLOT, pat_id);  // ← Uses PATTERN
}
```

**Uses:** `sv_get_pattern_lines()` for actual pattern objects

### Potential Mismatch?

IF pattern sizes don't match table section step counts, the two timelines diverge:

- **Playback expects:** Line 188 = start of section 9
- **SunVox has:** Line X = start of pattern 8 (section 9's pattern)

If X ≠ 188, then playback will calculate wrong section!

---

## Why This Causes Step Jumping

Hypothesis: After section 8 (11 steps, pattern 7), the timeline positions differ:

**Table-based calculation (playback code):**
- Section 8 ends at step 187 (start=177, steps=11)
- Section 9 should start at step 188
- Timeline line 188 should map to section 9, step 0

**SunVox pattern layout:**
- Pattern 7 (section 8) ends at line 177 + 11 = 188
- Pattern 8 (section 9) starts at line 188
- ...wait, that's the same!

Actually, if the pattern sizes ARE correct (which the logs show), then the timelines should match perfectly.

Let me recalculate manually:
- Pattern 10 (sec 0): x=0, 16 lines → ends at 16
- Pattern 0 (sec 1): x=16, 16 lines → ends at 32
- Pattern 1 (sec 2): x=32, 16 lines → ends at 48
- Pattern 2 (sec 3): x=48, 16 lines → ends at 64
- Pattern 3 (sec 4): x=64, 16 lines → ends at 80
- Pattern 4 (sec 5): x=80, 16 lines → ends at 96
- Pattern 5 (sec 6): x=96, 65 lines → ends at 161  ✅
- Pattern 6 (sec 7): x=161, 16 lines → ends at 177  ✅
- Pattern 7 (sec 8): x=177, 11 lines → ends at 188  ✅
- Pattern 8 (sec 9): x=188, 16 lines → ends at 204  ✅
- Pattern 9 (sec 10): x=204, 16 lines → ends at 220  ✅

**Conclusion:** If patterns have correct sizes, timeline should be correct!

---

## 🤔 Missing Information

The debug logs DON'T show:

1. **Enhanced playback logging** - Would show step-by-step position tracking
2. **Transition from section 9 → 10** - Playback stopped at section 9
3. **Final pattern X positions** - No log after all resizes complete

### What We Need

Run the app with enhanced playback logging enabled and capture:
1. Complete pattern layout AFTER import (with X positions)
2. Playback through sections 9 → 10 transition
3. Current line, calculated section, calculated step at each frame

---

## Potential Bugs to Investigate

### 1. Timeline Not Updated After All Resizes

During import, `setSectionStepCount` is called 11 times. Each call to `sunvox_wrapper_create_section_pattern` that resizes an existing pattern calls `sunvox_wrapper_update_timeline_seamless`.

**Question:** Does calling update_timeline_seamless multiple times in rapid succession cause race conditions?

**Test:** Add logging to `sunvox_wrapper_update_timeline_seamless` to print all pattern X positions.

### 2. Pattern Sequence vs Timeline Layout

In song mode, SunVox uses BOTH:
- Pattern X positions (timeline layout)
- Pattern sequence array (playback order)

From import.dart, after setting playback mode to song (line 799):
```
SUNVOX:   📍 [SUNVOX] Pattern 10 (section 0): 4 loops
SUNVOX:   📍 [SUNVOX] Pattern 0 (section 1): 2 loops
...
SUNVOX:   📋 [SUNVOX] Pattern sequence: 11 patterns
```

**Question:** Does the pattern sequence order match the timeline X position order?

Looking at `sunvox_wrapper_set_playback_mode` (lines 660-752), in song mode:
```cpp
for (int i = 0; i < sections_count && seq_count < 64; i++) {
    int pat_id = g_section_patterns[i];
    pattern_sequence[seq_count++] = pat_id;
}
```

So sequence order is: [10, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

But timeline X order should be: pattern 10 at x=0, then pattern 0 at x=16, etc.

**This should be fine** - SunVox uses X positions for timeline layout, sequence just determines which pattern comes "next" after loops complete.

### 3. Section Start Step Calculation

In `update_current_step_from_sunvox` (line 822):
```cpp
section_start_step = table_get_section_start_step(i);
```

Then line 840:
```cpp
int new_global_step = section_start_step + local_line;
```

If `section_start_step` is correct (188 for section 9), and `local_line` is calculated correctly from the SunVox line, this should work.

**BUT:** If the SunVox line is at the WRONG position due to pattern sequence or loop logic, then `local_line` could be wrong!

---

## Recommended Next Steps

### 1. Add Comprehensive Logging

Modify `sunvox_wrapper_update_timeline_seamless` to log all pattern positions:

```cpp
prnt("🗺️ [SUNVOX TIMELINE] === PATTERN LAYOUT ===");
for (int i = 0; i < sections_count; i++) {
    int pat_id = g_section_patterns[i];
    if (pat_id < 0) continue;
    int pat_x = sv_get_pattern_x(SUNVOX_SLOT, pat_id);
    int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
    prnt("  Section %d: Pattern %d at x=%d (%d lines, ends at %d)", 
         i, pat_id, pat_x, pat_lines, pat_x + pat_lines);
}
prnt("🗺️ [SUNVOX TIMELINE] =============================");
```

### 2. Enable Enhanced Playback Logging

Run the app with enhanced playback logging to see:
- Current SunVox line
- Calculated section
- Calculated step
- Expected vs actual

### 3. Verify Loop Counter Logic

The issue might be in how SunVox advances from pattern 8 (section 9) to pattern 9 (section 10).

Check if `sv_get_pattern_current_loop` returns correct values during transitions.

---

## Hypothesis: Song Mode Pattern Advancement Bug

When playing in song mode with loop counts:
- Section 9 has 4 loops (lines 810, 874)
- Section 10 has 4 loops

After section 9 completes its 4 loops at pattern 8, SunVox should advance to pattern 9.

**But:** The pattern sequence order is [10, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

When SunVox looks for "next pattern after pattern 8" in the sequence, it finds pattern 9 ✅

**This should work correctly.**

---

## Most Likely Bug

After analyzing all the code, I believe the issue is:

**The pattern X positions are NOT updated correctly after all section resizes during import.**

Specifically:
1. Sections 1-10 are appended with default 16 steps
2. Timeline is built: patterns at x=[16, 32, 48, 64, 80, 96, 112, 128, 144, 160]
3. Section 6 is resized to 65 steps
4. `update_timeline_seamless` is called → pattern 5 stays at x=96 but now has 65 lines
5. **BUG:** Pattern 6 (section 7) should move to x=161 (96+65), but...
   
Let me check if `update_timeline_seamless` actually updates ALL patterns or just the current one.

Looking at sunvox_wrapper.mm:790-796:
```cpp
for (int i = 0; i < sections_count; i++) {
    int pat_id = g_section_patterns[i];
    if (pat_id < 0) continue;
    sv_set_pattern_xy(SUNVOX_SLOT, pat_id, timeline_x, i);
    timeline_x += sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
}
```

This DOES update all patterns! So after section 6 is resized, all subsequent patterns should be repositioned correctly.

---

## Conclusion

The section table data is correct, pattern sizes are correct, and the timeline update logic SHOULD work correctly.

**We need actual playback logs** with the transition from section 9 to 10 to see where the bug actually occurs.

The most likely scenarios are:
1. SunVox loop counter logic advancing to wrong pattern
2. Timeline positions not matching expected values (need logging to verify)
3. Race condition in `update_timeline_seamless` when called multiple times rapidly

**Action Required:** Run app with enhanced logging and capture logs showing the section 9 → 10 transition.






