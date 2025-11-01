# Seamless Step Add/Remove During Playback - Final Solution

**Date:** October 22, 2025  
**Status:** ✅ RESOLVED  
**Files Modified:** `app/native/sunvox_wrapper.mm`, SunVox library APIs

---

## Problem

When adding or removing steps from a pattern during playback:
1. ❌ Song mode: Playback stops at old boundary instead of continuing through new steps
2. ❌ Loop counter: Jumps from "3/4" back to "1/4" when adding steps

## Root Cause

**Pattern size vs. project length mismatch:**
- `sv_set_pattern_size()` updates `pat->lines` (logical pattern size) ✅
- But `s->proj_lines` (global project length) is NOT auto-updated ❌
- Audio callback checks: `if (line_counter >= s->proj_lines) { STOP }` ❌
- Result: Uses stale `proj_lines`, stops at old boundary

**Why loop mode worked but song mode failed:**

Loop mode reads `pat->lines` directly:
```cpp
// Line ~2313 in sunvox_engine_audio_callback.cpp
if( new_line_counter >= s->pats_info[pnum].x + s->pats[pnum]->lines ) {
    // ↑ Reads fresh pat->lines on every check ✅
```

Song mode reads cached `proj_lines`:
```cpp
// Line ~2378 in sunvox_engine_audio_callback.cpp
if( new_line_counter >= s->proj_lines ) {
    // ↑ Uses stale cached value ❌
    if( s->stop_at_the_end_of_proj ) {
        // STOP command sent
```

## Solution

### Key Discovery

`sv_set_position()` internally calls `sunvox_sort_patterns()` which recalculates `proj_lines`:

```cpp
// From sunvox_engine.cpp lines 746-750
void sunvox_set_position( int pos, sunvox_engine* s ) {
    s->line_counter = pos;
    sunvox_sort_patterns( s );  // ← Recalculates proj_lines!
    sunvox_select_current_playing_patterns( 0, s );
}
```

### Implementation

**Created:** `sunvox_wrapper_update_timeline_seamless()` in `app/native/sunvox_wrapper.mm`

**Critical fix for race condition:** The pattern resize and `proj_lines` recalculation must be **atomic** (within the same lock). Without this, the audio callback can run between these operations and see inconsistent state.

**Race condition prevented:**
```cpp
// BAD (race condition):
sv_lock_slot();
sv_set_pattern_size();     // Updates pat->lines
sv_unlock_slot();          // ← Audio callback can run here!
sv_set_position();         // Updates proj_lines (too late!)

// GOOD (atomic):
sv_lock_slot();
sv_set_pattern_size();     // Updates pat->lines
sv_set_pattern_xy();       // Updates positions
sv_set_position();         // Updates proj_lines (still locked!)
sv_unlock_slot();          // ← Now safe, everything updated
```

**Core logic:**
```cpp
void sunvox_wrapper_update_timeline_seamless(int section_index) {
    // 1. Find current section and offset (before positions change)
    int target_section = /* find by current line */;
    int section_local_offset = current_line - pattern_x;
    
    // 2. Save loop counter (song mode only)
    int saved_loop_counter = sv_get_pattern_current_loop(SUNVOX_SLOT, current_pattern);
    
    // 3. ATOMIC UPDATE (within single lock):
    sv_lock_slot(SUNVOX_SLOT);
    {
        // Update pattern X positions
        for (all sections) {
            sv_set_pattern_xy(SUNVOX_SLOT, pat_id, new_x, y);
        }
        
        // CRITICAL: Force proj_lines recalculation while still locked
        // This prevents audio callback from seeing stale proj_lines
        sv_set_position(SUNVOX_SLOT, new_line);
    }
    sv_unlock_slot(SUNVOX_SLOT);
    
    // 4. Refresh mode settings (outside lock, safe)
    if (song_mode) {
        // Refresh loop counts
        sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, loops);
        // Restore loop counter
        sv_set_pattern_current_loop(SUNVOX_SLOT, current_pat, saved_loop_counter);
        sv_set_pattern_loop(SUNVOX_SLOT, current_pat);
        } else {
        // Refresh infinite loop
        sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, 0);
        sv_set_pattern_loop(SUNVOX_SLOT, pat_id);
    }
}
```

### SunVox Library Modification

**Added API:** `sv_set_pattern_current_loop()` to preserve loop state

**Files modified:**
- `sunvox_lib/headers/sunvox.h` - API declaration
- `sunvox_lib/main/sunvox_lib.cpp` - Implementation

```c
int sv_set_pattern_current_loop( int slot, int pat_num, int loop_num );
```

**Why needed:** `sv_set_pattern_loop_count()` always resets the current loop counter to 0. This new API allows restoring the counter after refreshing loop counts.

## Results

✅ **Song mode:** Playback continues through new steps (no stop at old boundary)  
✅ **Loop mode:** New steps play immediately  
✅ **Loop counter:** Preserved (stays at "3/4", doesn't jump to "1/4")  
✅ **No audio glitches:** Completely seamless during playback  
✅ **Both playing/stopped:** Works correctly in all states

## Technical Details

### Before Fix
```
User adds step: 16 → 17 lines
pat->lines = 17 ✅
proj_lines = 16 ❌ (stale)
Audio callback: if (line_counter >= 16) → STOP at line 16 ❌
```

### After Fix
```
User adds step: 16 → 17 lines
pat->lines = 17 ✅
sv_set_position() → sunvox_sort_patterns() → proj_lines = 17 ✅
Audio callback: if (line_counter >= 17) → Continues to line 17 ✅
```

### Call Chain

```
sunvox_wrapper_create_section_pattern()
  → sv_set_pattern_size()              # Updates pat->lines
  → sunvox_wrapper_update_timeline_seamless()
    → sv_set_pattern_xy()              # Updates pattern positions
    → sv_set_position()                # ← CRITICAL CALL
      → sunvox_set_position()
        → sunvox_sort_patterns()       # ← Recalculates proj_lines
```

## Key Insights

1. **`pat->lines`** = Per-pattern logical size (always fresh after resize)
2. **`s->proj_lines`** = Cached global project length (must be recalculated)
3. **`sunvox_sort_patterns()`** = Function that recalculates `proj_lines` from all patterns
4. **`sv_set_position()`** = Public API that triggers `sunvox_sort_patterns()`
5. **Must call `sv_set_position()` even if line number doesn't change** to force recalculation
6. **⚠️ CRITICAL: All updates must be atomic (within same lock)** to prevent race conditions with audio callback

## Files Modified

### Application Code
- `app/native/sunvox_wrapper.mm` - Added `sunvox_wrapper_update_timeline_seamless()`
- `app/native/sunvox_wrapper.h` - Added function declaration

### SunVox Library
- `app/native/sunvox_lib/sunvox_lib/headers/sunvox.h` - Added `sv_set_pattern_current_loop()` API
- `app/native/sunvox_lib/sunvox_lib/main/sunvox_lib.cpp` - Implemented `sv_set_pattern_current_loop()`

---

**Fixed by:** Roman Smirnov + AI Assistant  
**Date:** October 22, 2025  
**Status:** ✅ Production Ready
