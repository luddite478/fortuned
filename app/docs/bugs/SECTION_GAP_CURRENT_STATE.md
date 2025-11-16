# Section Gap Bug - Current State

**Date:** November 16, 2025  
**Status:** 🟡 **UNDER INVESTIGATION**

---

## Problem Summary

Sections are not contiguous after project load, causing playback desynchronization where the UI displays one step but audio plays a different step.

**Example:**
```
Section 8:  Steps [128-138] (11 steps)  ← ends at 138
Section 9:  Steps [144-159] (16 steps)  ← starts at 144
                  ^^^^^ GAP of 5 steps (139-143 missing)
```

**Impact:**
- UI shows step 139 when transitioning from section 8 to section 9
- Audio actually plays step 144 (first step of section 9)
- This causes a 5-step desynchronization between UI and audio

---

## Fix Attempts

### Attempt #1: `table_recompute_section_starts()` - Status: ⚠️ Incomplete

**What was implemented:**

1. Created helper function `table_recompute_section_starts()` to recalculate all section `start_step` values
2. Added calls to this function in 7 places that modify section structure:
   - `table_set_section_step_count()`
   - `table_insert_step()`
   - `table_delete_step()`
   - `table_append_section()`
   - `table_delete_section()`
   - `table_reorder_section()`
   - `table_set_section()`

**Result:** Issue still persists after implementation

**Why it might not be working:**

1. **The recompute function may not be called during project import**
   - Import might bypass the modified functions
   - Import might use direct memory operations
   - Import might call functions in an order that recreates gaps

2. **The gaps might be created before import**
   - The saved project snapshot itself might have corrupted section data
   - The snapshot export might be saving incorrect start_step values

3. **Race conditions**
   - Multiple threads accessing section data simultaneously
   - State updates happening out of order during import

---

## Current Investigation Plan

### Phase 1: Verify Recompute is Being Called ✅ Done

**Added verbose logging to `table_recompute_section_starts()`:**

```cpp
static void table_recompute_section_starts(void) {
    prnt_info("🔧 [TABLE_RECOMPUTE] === RECOMPUTING SECTION STARTS ===");
    prnt_info("🔧 [TABLE_RECOMPUTE] Sections count: %d", g_table_state.sections_count);
    
    int cursor = 0;
    for (int i = 0; i < g_table_state.sections_count; i++) {
        int old_start = g_table_state.sections[i].start_step;
        int num_steps = g_table_state.sections[i].num_steps;
        g_table_state.sections[i].start_step = cursor;
        
        prnt_info("🔧 [TABLE_RECOMPUTE]   Section %d: start %d → %d, steps: %d", 
                  i, old_start, cursor, num_steps);
        
        cursor += num_steps;
    }
    
    prnt_info("🔧 [TABLE_RECOMPUTE] Total steps after recompute: %d", cursor);
    prnt_info("🔧 [TABLE_RECOMPUTE] === RECOMPUTE COMPLETE ===");
}
```

**Next steps:**
1. Load the problematic project
2. Check terminal logs for `[TABLE_RECOMPUTE]` messages
3. Verify if the function is called at all
4. If called, verify the old_start → new_start values show the fix being applied

### Phase 2: Trace Project Import Flow 🔜 Next

**Files to investigate:**
- `app/lib/services/snapshot/import.dart` - Main import logic
- `app/lib/state/threads_state.dart` - Project loading coordinator
- `app/native/table.mm` - Section management
- `app/native/undo_redo.mm` - State serialization/restoration

**Questions to answer:**
1. How exactly are sections restored from snapshot?
2. Does import call `table_set_section_step_count()` or something else?
3. Are start_step values saved in the snapshot and restored directly?
4. Is there a code path that bypasses our recompute calls?

### Phase 3: Check Snapshot Data 🔜 Next

**What to examine:**
1. Export a snapshot of the problematic project
2. Examine the JSON to see if sections have correct start_step values
3. If snapshot has correct values → problem is in import
4. If snapshot has gaps → problem is in export/save

---

## Testing Tools Added

### 1. Enhanced Playback Logging ✅

**Location:** Sequencer Settings → Developer Settings → Enhanced Playback Logging

**What it shows:**
- Complete section overview with start/end steps
- Current playback position and section
- Table contents for active section
- SunVox engine state

**How to use:**
1. Enable the toggle in settings
2. Start playback
3. Watch terminal for detailed logs every step
4. Look for the "ALL SECTIONS OVERVIEW" section to see gaps

### 2. Project ID Display ✅

**Location:** Sequencer Settings → Developer Settings → Project Information

**What it shows:**
- Project name
- Project ID (copyable)

**How to use:**
1. Load the problematic project
2. Open Sequencer Settings
3. Copy the Project ID
4. Use this ID to identify the project in bug reports

---

## Information Needed from User

To continue debugging, we need:

1. **Terminal logs after loading the problematic project**
   - Look for `[TABLE_RECOMPUTE]` messages
   - Check if recompute is being called
   - Check if the old → new start values show gaps being fixed

2. **Project ID of the problematic project**
   - Available in Sequencer Settings → Developer Settings

3. **Enhanced playback logs showing the section overview**
   - Enable enhanced logging in settings
   - Play through the transition
   - Share the section overview showing the gaps

4. **Steps to reproduce**
   - Which project has the issue?
   - Does it happen on every project or specific ones?
   - Does it happen immediately after load or after some operations?

---

## Possible Root Causes (Hypotheses)

### Hypothesis A: Recompute Not Called During Import ⚠️ Most Likely
- Import might use `table_apply_state()` or similar that bypasses section management functions
- Import might set section metadata directly without triggering recompute
- **Test:** Check terminal logs for `[TABLE_RECOMPUTE]` during project load

### Hypothesis B: Snapshot Contains Corrupted Data
- Projects saved with gaps preserve those gaps in snapshot
- Import faithfully restores the corrupted data
- Recompute might be called but overwritten later
- **Test:** Examine snapshot JSON for section start_step values

### Hypothesis C: Recompute Called Too Early
- Sections might be modified after recompute is called
- Import might do: recompute → modify sections → gaps reappear
- **Test:** Check order of operations in import flow

### Hypothesis D: SunVox Pattern Sync Issue
- Native section data might be correct but SunVox patterns misaligned
- Playback uses SunVox pattern indices which don't match section indices
- **Test:** Check SunVox pattern creation logs during import

---

## Files Modified So Far

### Native (C++)
- `/Users/romansmirnov/projects/fortuned/app/native/table.mm`
  - Added `table_recompute_section_starts()` helper (lines 53-71)
  - Updated 7 functions to call the helper after section modifications
  - Added verbose logging to track recompute operations

### Flutter (Dart)
- `/Users/romansmirnov/projects/fortuned/app/lib/screens/sequencer_settings_screen.dart`
  - Added Project Information section showing project ID and name
  - Added copy button for Project ID
  - Organized developer settings section

### Documentation
- `/Users/romansmirnov/projects/fortuned/app/docs/bugs/SECTION_GAP_BUG_ANALYSIS.md`
  - Complete root cause analysis
  - Updated status to reflect ongoing investigation

- `/Users/romansmirnov/projects/fortuned/app/docs/bugs/SECTION_GAP_CURRENT_STATE.md` (this file)
  - Current state and investigation plan

---

## Next Actions

1. **User:** Load problematic project and share terminal logs
2. **Dev:** Check if `[TABLE_RECOMPUTE]` appears in logs
3. **Dev:** If recompute is called, verify old → new values show fix being applied
4. **Dev:** If recompute is NOT called, investigate import flow to find where sections are set
5. **Dev:** If recompute IS called but gaps remain, check if sections are modified after recompute

---

**Last Updated:** November 16, 2025  
**Status:** Waiting for test results with verbose logging enabled

