# Section Gap Bug - Investigation Summary

**Date:** November 16, 2025  
**Status:** 🟡 Diagnostic logging added, awaiting test results  
**Issue:** Section 10 doesn't start from its first step when transitioning from section 9

---

## 🎯 Key Findings

### ✅ GOOD NEWS: Sections Are Contiguous

The `table_recompute_section_starts()` fix IS working correctly!

**Proof from logs and saved project:**
```
Section 0:  steps [0-15]     (16 steps)
Section 1:  steps [16-31]    (16 steps)
Section 2:  steps [32-47]    (16 steps)
Section 3:  steps [48-63]    (16 steps)
Section 4:  steps [64-79]    (16 steps)
Section 5:  steps [80-95]    (16 steps)
Section 6:  steps [96-160]   (65 steps) ← Large section
Section 7:  steps [161-176]  (16 steps)
Section 8:  steps [177-187]  (11 steps) ← Small section
Section 9:  steps [188-203]  (16 steps)
Section 10: steps [204-219]  (16 steps)

Total: 220 steps, NO GAPS ✅
```

### ⚠️ SUSPICIOUS: Pattern ID Mapping

After import, the pattern-to-section mapping is unusual:

```
Section 0  → Pattern 10  ❌ Should be Pattern 0
Section 1  → Pattern 0   ← Gets the "first" pattern ID
Section 2  → Pattern 1
Section 3  → Pattern 2
...
Section 10 → Pattern 9
```

**Why this happens:**
1. `sunvox_wrapper_reset_all_patterns()` deletes all patterns (including pattern 0)
2. `g_section_patterns[0]` is set to -1 (no pattern)
3. Sections 1-10 are appended, creating patterns 0-9
4. When section 0's step count is set, it creates a NEW pattern (gets ID 10)

**Is this a problem?**
- Pattern IDs don't need to match section indices
- Pattern X positions (timeline layout) are what matters
- SunVox should handle this correctly

### ❓ UNKNOWN: Timeline Layout After Import

The logs show patterns being resized during import, but we DON'T see the final pattern X positions.

**What we need to verify:**
Do the pattern X positions match the section start steps?

Expected:
```
Pattern 10 (section 0): x=0
Pattern 0 (section 1): x=16
Pattern 1 (section 2): x=32
...
Pattern 7 (section 8): x=177
Pattern 8 (section 9): x=188   ← Should be here!
Pattern 9 (section 10): x=204  ← Should be here!
```

If these match, the timeline is correct.  
If these DON'T match, that's our bug!

---

## 🔍 What Diagnostic Logging Was Added

I've added three critical logging points:

### 1. Timeline Layout (sunvox_wrapper.mm)

Logs every time patterns are laid out on the timeline:

```cpp
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT (seamless) ===
  Section 0: Pattern 10 at x=0 (16 lines, ends at 16)
  Section 1: Pattern 0 at x=16 (16 lines, ends at 32)
  ...
  Section 9: Pattern 8 at x=188 (16 lines, ends at 204)
  Section 10: Pattern 9 at x=204 (16 lines, ends at 220)
🗺️ [SUNVOX TIMELINE] Total lines: 220
🗺️ [SUNVOX TIMELINE] =============================
```

This will appear:
- Multiple times during import (after each section resize)
- After manual section structure changes

### 2. Playback Position Tracking (playback_sunvox.mm)

Logs the position calculation every frame:

```cpp
🎯 [PLAYBACK POS] SunVox line 188 → Section 9, local_line 0, section_start_step 188
```

This shows:
- What SunVox line is currently playing
- Which section that line maps to
- The local offset within that section
- The section's start step from the table

### 3. End-of-Timeline Detection

If playback goes past the expected end:

```cpp
⚠️ [PLAYBACK POS] SunVox line 225 is past end of timeline (max: 220)
```

---

## 🧪 How to Test

### Quick Test
1. Rebuild the app: `./run.sh`
2. Load project: `69162e4ed22c469f10ad2d97`
3. Start playback from section 9
4. Let it play through and transition to section 10
5. Capture terminal logs

### What to Look For

**After Import:**
Look for the LAST occurrence of:
```
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT
```

This shows the final pattern positions. Verify they match expected values.

**During Playback:**
Watch for the transition:
```
🎯 [PLAYBACK POS] SunVox line 203 → Section 9, local_line 15, section_start_step 188
[transition happens]
🎯 [PLAYBACK POS] SunVox line ??? → Section 10, local_line ???, section_start_step 204
```

**Expected:** SunVox line should be 204, local_line should be 0  
**If buggy:** SunVox line might be > 204 (e.g., 209), local_line might be > 0

---

## 🐛 Possible Root Causes

Based on analysis, the bug could be:

### Hypothesis A: Timeline Not Updated After Resizes

**Likelihood:** Medium

**Description:** During import, sections are resized multiple times (especially section 6 → 65 steps, section 8 → 11 steps). If `sunvox_wrapper_update_timeline_seamless` isn't working correctly, patterns might be at wrong X positions.

**How to verify:** Check the final timeline layout log. If pattern X positions don't match section start steps, this is the bug.

**Fix:** Ensure `sunvox_wrapper_update_timeline_seamless` is called after each resize and updates ALL patterns correctly.

### Hypothesis B: SunVox Pattern Advancement Issue

**Likelihood:** High

**Description:** When playing in song mode with loop counts, SunVox's internal pattern advancement might not correctly handle the transition from pattern 8 (section 9) to pattern 9 (section 10).

**How to verify:** Check if SunVox line is at wrong position when section 10 starts. If line ≠ 204, SunVox advanced incorrectly.

**Possible causes:**
1. Pattern loop counter not resetting correctly
2. Pattern sequence order confusion (sequence is [10, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
3. SunVox using wrong "next pattern" logic after loops complete

**Fix:** Investigate SunVox pattern loop handling, especially with non-sequential pattern IDs.

### Hypothesis C: Playback Position Calculation Mismatch

**Likelihood:** Low

**Description:** The `update_current_step_from_sunvox` function calculates section from SunVox line by accumulating section step counts. If there's a mismatch between pattern sizes and section step counts, the calculation will be wrong.

**How to verify:** If SunVox line is correct (204) but calculated section/step is wrong, this is the bug.

**Fix:** Ensure `table_get_section_step_count` returns values that exactly match `sv_get_pattern_lines`.

### Hypothesis D: Pattern Sizes Don't Match Section Step Counts

**Likelihood:** Very Low (but check!)

**Description:** If patterns weren't resized correctly during import, their line counts won't match section step counts.

**How to verify:** Look at the timeline layout log. Check if pattern line counts match section steps (especially sections 6 and 8).

**Fix:** Investigate `sv_set_pattern_size` calls during import.

---

## 📊 Decision Tree

After getting the test logs:

```
START → Check final timeline layout log
    ↓
    Are pattern X positions correct?
    ├─ NO → FIX: Timeline update logic
    └─ YES → Check first playback position log for section 10
        ↓
        Is SunVox line = 204?
        ├─ NO → FIX: SunVox pattern advancement
        └─ YES → Check calculated position
            ↓
            Is local_line = 0?
            ├─ NO → FIX: Position calculation
            └─ YES → Bug is elsewhere (UI desync?)
```

---

## 🎬 Next Steps

### Immediate Action Required

**YOU NEED TO:**
1. Run `./run.sh` to rebuild with new logging
2. Load the problematic project
3. Play through sections 9 → 10 transition
4. Capture and share terminal logs

**I WILL:**
1. Analyze the logs to identify exact bug location
2. Implement targeted fix based on findings
3. Verify fix resolves the issue

### Documents Created

1. `SECTION_GAP_DEEP_ANALYSIS.md` - Comprehensive technical analysis
2. `SECTION_GAP_DIAGNOSTIC_GUIDE.md` - Step-by-step testing instructions
3. `SECTION_GAP_FINDINGS_SUMMARY.md` - This document

### Files Modified

1. `app/native/sunvox_wrapper.mm` - Added timeline layout logging
2. `app/native/playback_sunvox.mm` - Added position calculation logging

---

## 💡 Why We Can't Fix It Yet

The current logs DON'T show:
- ❌ Final pattern X positions after import
- ❌ The actual section 9 → 10 transition (playback stopped before reaching it)
- ❌ Whether SunVox line is at wrong position or calculation is wrong

Without this information, we'd be guessing. The diagnostic logging will give us the exact data needed to fix it correctly.

---

## 📝 Summary

**Status:**
- ✅ Section table data is correct (gaps fixed)
- ✅ Pattern sizes appear correct
- ⚠️ Pattern ID mapping is unusual but might be OK
- ❓ Pattern X positions need verification
- ❓ Section 9→10 transition behavior unknown

**What's blocking us:**
- Need test logs showing the actual bug in action

**Estimated time to fix after getting logs:**
- 30-60 minutes to analyze logs
- 30-60 minutes to implement fix
- 30 minutes to test and verify

---

**🚀 Ready for you to test!** Follow the instructions in `SECTION_GAP_DIAGNOSTIC_GUIDE.md` and share the results.

