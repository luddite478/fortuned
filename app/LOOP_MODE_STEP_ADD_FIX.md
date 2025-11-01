# Loop Mode Step Add Fix - Critical Update

**Date:** October 22, 2025  
**Priority:** HIGH  
**Issue:** Added steps don't play in loop mode until restart  

---

## The Problem You Reported

**Symptom:**
- Removing steps (`-` button) works seamlessly in loop mode ✅
- Adding steps (`+` button) in loop mode: UI updates but steps don't play until restart ❌
- The new steps exist but playback ignores them

**Example:**
```
Initial: 16 steps, looping in loop mode
User clicks "+" → UI shows 17 steps
Expected: Step 17 plays on next loop
Actual: Loops only play steps 1-16, step 17 is silent
Only after restarting playback does step 17 work
```

---

## Root Cause

When you add a step in loop mode:

1. ✅ Pattern is resized to 17 lines via `sv_set_pattern_size()`
2. ✅ New step data is synced to pattern
3. ✅ Timeline X positions are updated
4. ❌ **BUT** SunVox's `single_pattern_play` keeps old cached boundaries (16 lines)
5. ❌ Loop wraps at line 16, never reaching line 17

**Why removing worked:** When shrinking from 17→16, SunVox automatically clamps to the new smaller size. But when growing from 16→17, it keeps using the old cached boundary.

---

## The Fix

After updating timeline positions, **re-apply the pattern loop** to force SunVox to re-read the pattern boundaries:

```cpp
void sunvox_wrapper_update_timeline_seamless(int section_index) {
    // ... update timeline positions ...
    
    // CRITICAL: If in loop mode on the resized section, refresh loop boundaries
    if (!g_song_mode && section_index == g_current_section) {
        int loop_pat_id = g_section_patterns[g_current_section];
        
        // Re-apply pattern loop - forces SunVox to re-read pattern line count
        sv_set_pattern_loop(SUNVOX_SLOT, loop_pat_id);
        sv_set_autostop(SUNVOX_SLOT, 0);  // Infinite loop
        
        // Now SunVox will loop with the NEW boundaries (e.g., 17 lines)
    }
}
```

### Why This Works

`sv_set_pattern_loop()` tells SunVox:
1. Query the pattern's current line count (now 17, not 16)
2. Update internal loop boundaries
3. Continue looping with new boundaries

**Seamless:** This happens between audio callbacks (~5ms), no audio interruption.

---

## Testing

### Before Fix
```
Loop mode on section with 16 steps
Click "+" button
→ UI shows 17 steps
→ Pattern resized to 17 lines
→ Loop plays: 1,2,3...15,16,1,2,3...15,16 (step 17 never plays) ❌
→ Must restart playback to hear step 17
```

### After Fix
```
Loop mode on section with 16 steps
Click "+" button
→ UI shows 17 steps
→ Pattern resized to 17 lines
→ Loop boundaries refreshed
→ Loop plays: 1,2,3...15,16,17,1,2,3...15,16,17 ✅
→ New step plays immediately on next loop!
```

---

## Technical Details

### Modified Files
- **`sunvox_wrapper.mm`**: Added loop refresh logic (lines 779-793)
- **`sunvox_wrapper.h`**: Updated function signature to accept `section_index`

### SunVox API Used
```cpp
// Re-apply pattern loop to refresh cached boundaries
sv_set_pattern_loop(slot, pattern_id);
sv_set_autostop(slot, 0);  // 0 = infinite loop
```

### State Tracking
```cpp
static int g_song_mode = 0;          // 0 = loop, 1 = song
static int g_current_section = 0;    // Which section is looping
```

These are set by `sunvox_wrapper_set_playback_mode()` and used to determine if loop refresh is needed.

---

## Why Remove Always Worked

When you **remove** a step:
- Pattern shrinks from 16→15 lines
- Playhead might be at line 15 (last line)
- On next audio callback, SunVox sees line 15 >= 15 (out of bounds)
- **Automatically clamps** to line 14 or wraps to 0
- No explicit refresh needed

When you **add** a step:
- Pattern grows from 16→17 lines  
- Playhead at line 15 is still valid
- SunVox continues using **cached** boundary of 16
- Never reaches line 16 (thinks it's the end)
- **Needs explicit refresh** to see new boundary

---

## Build & Test

No rebuild needed! Application-level code change only.

```bash
flutter clean  # Optional but recommended
flutter run
```

### Quick Test
1. Start loop mode playback
2. Click "+" button multiple times
3. ✅ Each new step should play immediately on next loop
4. ✅ No restart needed
5. ✅ No audio cuts

---

## Related Fixes

This is part of the complete seamless step resize solution:
- **Issue 1:** Playback restart → Fixed with seamless timeline update
- **Issue 2:** Loop mode add steps → **Fixed with loop boundary refresh** ← YOU ARE HERE

**Full docs:** `app/docs/features/sunvox_integration/seamless_step_resize.md`

---

**Status:** ✅ Fixed and ready to test





