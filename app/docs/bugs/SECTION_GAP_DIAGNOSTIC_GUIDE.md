# Section Gap Bug - Diagnostic Guide

**Date:** November 16, 2025  
**Purpose:** Capture diagnostic information to identify the section 9 → 10 transition bug

---

## What We've Added

### Enhanced Logging

Three new logging points have been added to help diagnose the issue:

#### 1. Timeline Layout Logging (sunvox_wrapper.mm)

**When it logs:**
- Every time `sunvox_wrapper_update_timeline_seamless()` is called (during pattern resizes)
- Every time `sunvox_wrapper_update_timeline()` is called (during section structure changes)

**What it shows:**
```
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT (seamless) ===
  Section 0: Pattern 10 at x=0 (16 lines, ends at 16)
  Section 1: Pattern 0 at x=16 (16 lines, ends at 32)
  ...
  Section 9: Pattern 8 at x=188 (16 lines, ends at 204)
  Section 10: Pattern 9 at x=204 (16 lines, ends at 220)
🗺️ [SUNVOX TIMELINE] Total lines: 220
🗺️ [SUNVOX TIMELINE] =============================
```

**What to look for:**
- ✅ Pattern X positions should match section start steps
- ✅ Pattern line counts should match section step counts
- ✅ No gaps between patterns (each starts where previous ends)

#### 2. Playback Position Calculation (playback_sunvox.mm)

**When it logs:**
- Every audio callback frame when position changes

**What it shows:**
```
🎯 [PLAYBACK POS] SunVox line 188 → Section 9, local_line 0, section_start_step 188
```

**What to look for:**
- Does SunVox line match expected section start?
- Does calculated section match the actual playing section?
- Does section_start_step match the table value?

---

## How to Reproduce the Bug

### Step 1: Rebuild the App

The new logging is already added to the code. Rebuild and run:

```bash
cd /Users/romansmirnov/projects/fortuned
./run.sh
```

### Step 2: Load the Project

1. Open the app
2. Navigate to the sequencer
3. Load the project with ID: `69162e4ed22c469f10ad2d97`

### Step 3: Check Timeline After Import

Look in the terminal for the final timeline layout. You should see:

```
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT (seamless) ===
```

This will appear multiple times during import (after each section resize). The LAST occurrence shows the final state.

**Expected values for this project:**
- Section 0: x=0, 16 lines, ends at 16
- Section 1: x=16, 16 lines, ends at 32
- Section 2: x=32, 16 lines, ends at 48
- Section 3: x=48, 16 lines, ends at 64
- Section 4: x=64, 16 lines, ends at 80
- Section 5: x=80, 16 lines, ends at 96
- Section 6: x=96, 65 lines, ends at 161  ← Large section!
- Section 7: x=161, 16 lines, ends at 177
- Section 8: x=177, 11 lines, ends at 188  ← Small section!
- Section 9: x=188, 16 lines, ends at 204
- Section 10: x=204, 16 lines, ends at 220

### Step 4: Start Playback from Section 9

1. In the UI, select section 9
2. Start playback
3. Let it play through section 9's 4 loops
4. Watch as it transitions to section 10

### Step 5: Observe the Bug

**What you'll see in the UI:**
- Section 10 starts, but NOT from step 0
- The step counter shows a value > 0 (e.g., step 5 or step 10)

**What to capture in terminal logs:**

Look for these patterns around the transition:

```
🎯 [PLAYBACK POS] SunVox line 203 → Section 9, local_line 15, section_start_step 188
[Section 9 ends]
🎯 [PLAYBACK POS] SunVox line ??? → Section ??, local_line ??, section_start_step ???
```

The question marks are what we need to see!

---

## Critical Questions to Answer

### 1. What is the final pattern layout after import?

Copy the LAST occurrence of:
```
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT (seamless) ===
  ...
🗺️ [SUNVOX TIMELINE] =============================
```

### 2. What SunVox line does section 10 transition at?

When you see section 10 starting in the UI, look for the FIRST:
```
🎯 [PLAYBACK POS] SunVox line ??? → Section 10, ...
```

**Expected:** Line should be 204 (start of section 10)  
**If buggy:** Line might be > 204 (e.g., 209, 214, etc.)

### 3. What is the calculated position?

From the same log line:
```
🎯 [PLAYBACK POS] SunVox line ??? → Section 10, local_line ???, section_start_step 204
```

**Expected:** `local_line` should be 0 (first step of section)  
**If buggy:** `local_line` might be > 0 (skipped steps)

### 4. Does the pattern layout match expected values?

Compare the logged pattern X positions with the expected values above.

If pattern X positions are wrong, the bug is in timeline layout.  
If pattern X positions are correct but playback position is wrong, the bug is in SunVox's pattern advancement logic or loop counting.

---

## Alternative Test: Start from Section 7

If you want to see more transitions:

1. Start playback from section 7 (which has 2 loops)
2. Let it play through: 7 → 8 → 9 → 10
3. Capture logs for ALL transitions

This will show if the bug is specific to the 9→10 transition or affects multiple transitions.

---

## What to Send

Please provide:

1. **Complete terminal output** from app launch through the section 9→10 transition
2. **Screenshot** of the UI showing section 10 with the wrong step number
3. **Project ID** (already have it: `69162e4ed22c469f10ad2d97`)

Save the terminal output to a file:
```bash
# In your terminal
./run.sh 2>&1 | tee section-bug-logs.txt
```

Then play through the bug and stop. The logs will be in `section-bug-logs.txt`.

---

## Expected Behavior vs Actual Behavior

### Expected ✅

**Terminal:**
```
🎯 [PLAYBACK POS] SunVox line 203 → Section 9, local_line 15, section_start_step 188
🎯 [PLAYBACK POS] SunVox line 204 → Section 10, local_line 0, section_start_step 204
```

**UI:**
- Section 10 indicator lights up
- Step counter shows step 204 (or 0 relative to section 10)
- Playback starts from first beat of section 10

### Actual Bug ❌

**Terminal (hypothesis):**
```
🎯 [PLAYBACK POS] SunVox line 203 → Section 9, local_line 15, section_start_step 188
🎯 [PLAYBACK POS] SunVox line 209 → Section 10, local_line 5, section_start_step 204
```

**UI:**
- Section 10 indicator lights up
- Step counter shows step 209 (or 5 relative to section 10)
- Playback starts MIDWAY through section 10 (skipped first 5 steps!)

---

## Analysis After Logs

Once we have the logs, we can determine:

1. **Is the timeline layout correct?**
   - If NO → Bug is in `sunvox_wrapper_update_timeline_seamless`
   - If YES → Continue to #2

2. **Is the SunVox line correct when section 10 starts?**
   - If SunVox line ≠ 204 → Bug is in SunVox pattern advancement
   - If SunVox line = 204 but calculated position is wrong → Bug is in `update_current_step_from_sunvox`

3. **Is there a mismatch between pattern sizes and section step counts?**
   - Compare pattern lines from timeline log with section steps from table
   - If mismatch → Bug is in pattern resize logic

---

## Next Steps After Diagnosis

Based on what we find, the fix will be one of:

### Fix A: Pattern ID Confusion

If the pattern ID mapping (section 0 → pattern 10, etc.) causes issues, we need to:
1. Fix `sunvox_wrapper_reset_all_patterns` to preserve section 0's pattern
2. OR fix the import flow to recreate patterns in the correct order

### Fix B: Timeline Position Update

If patterns aren't repositioned correctly after resize:
1. Verify `sunvox_wrapper_update_timeline_seamless` is called after each resize
2. Add error handling for rapid successive updates
3. Ensure SunVox's internal timeline state is refreshed

### Fix C: Playback Position Calculation

If the calculation from SunVox line → section → step is wrong:
1. Fix the loop that accumulates `timeline_pos`
2. Ensure `table_get_section_step_count` returns correct values
3. Verify `table_get_section_start_step` returns correct values

---

**Ready to test!** Run the app, reproduce the bug, and share the logs.






