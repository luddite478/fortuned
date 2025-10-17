
# SunVox Seamless Playback and Looping

**Date:** October 15, 2025  
**Status:** ✅ Complete and Verified

## 1. Overview

This document explains the two key modifications made to the SunVox engine to achieve seamless audio playback:
1.  **Seamless Pattern Looping:** Allowing samples to play continuously across loop boundaries without being cut off.
2.  **Seamless Mode Switching:** Allowing the user to switch between "Song" and "Loop" modes during playback without any audio interruption.

These changes are critical for a fluid and professional user experience.

---

## 2. Seamless Pattern Looping

### The Problem
In the original SunVox engine, even without an explicit "note off" event, any playing sample would be immediately silenced when a pattern looped. This was unacceptable for long, sustained notes, pads, or samples that were meant to bleed over the loop point.

### The Solution: `NO_NOTES_OFF` Flag

The solution involved modifying the SunVox engine's audio callback to conditionally preserve the `track_status` bitmask, which tracks active notes.

#### Engine Modifications
1.  **New Pattern Flag:** A custom flag, `SV_PATTERN_FLAG_NO_NOTES_OFF`, was added.
2.  **New APIs:** Functions `sv_pattern_set_flags()` and `sv_enable_supertracks()` were added to control this feature. Supertracks mode is a prerequisite for the flag to work.
3.  **Modified Callback Logic:** The audio callback (`sunvox_engine_audio_callback.cpp`) was updated. When a pattern has the `NO_NOTES_OFF` flag, the engine now skips the code that would normally send note-off events and clear the `track_status` when the pattern wraps.

### How It Works
When enabled, the engine "forgets" to send the NOTE OFF command at the pattern boundary. The note continues to sustain into the next loop until it either fades out naturally or a NOTE OFF event for that specific note is encountered later in the pattern.

### Usage
```cpp
// 1. Enable supertracks mode after initialization
sv_enable_supertracks(SUNVOX_SLOT, 1);

// 2. Set the flag on the desired pattern
sv_pattern_set_flags(SUNVOX_SLOT, pattern_id, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);
```

---

## 3. Seamless Mode Switching

### The Problem
Switching from "Song" mode to "Loop" mode would cause an audio dropout. This happened because if the song playhead was at a line number outside the bounds of the single pattern being looped, SunVox would stop playback.

**Example:**
- Song is playing at line 37.
- User enables loop mode on a pattern that occupies lines 0-15.
- SunVox sees the playhead (37) is "beyond bounds" for the active pattern (0-15) and stops the audio.

### The Solution: Seamless Position Jumps

The solution was to make the mode switch atomic by using a newly exposed, non-destructive position-setting function.

#### How It Works: The `sv_set_position` API

We exposed an internal SunVox function, `sunvox_set_position()`, as a new public API `sv_set_position()`. Unlike `sv_rewind()`, this function changes the engine's internal `line_counter` **without stopping the audio thread**.

The mode switching logic is now a two-step, seamless process:

1.  **Calculate Target Position:** Before enabling loop mode, we calculate the musically equivalent position within the target pattern.
    ```cpp
    // Example: current_line = 37, pattern is at X=0 with 16 lines
    int local_offset = (37 - 0) % 16; // -> 5
    int target_line = 0 + local_offset; // -> 5
    ```
2.  **Set Position, Then Switch Mode:** Crucially, we perform the operations in the correct order.
    ```cpp
    // In sunvox_wrapper.mm
    
    // CRITICAL: First, move the playhead to a valid position within the target pattern.
    sv_set_position(SUNVOX_SLOT, target_line);
    
    // SECOND: Enable pattern loop mode. The playhead is now in a valid range.
    sv_set_pattern_loop(SUNVOX_SLOT, pattern_id);
    ```

Because `sv_set_position` does not interrupt the audio, and the subsequent call to `sv_set_pattern_loop` happens before the next audio frame, the transition is seamless to the listener.

### Why It's Seamless
The entire switch happens between audio callbacks. SunVox's internal logic is designed for this:
1.  A jump occurs (via `sv_set_position`).
2.  The engine sends note-offs for patterns that are no longer active (unless `NO_NOTES_OFF` is set).
3.  The engine selects the new patterns at the new `line_counter` position.
4.  The engine processes notes for the newly activated patterns.

This all happens atomically within a single audio buffer (~5ms), resulting in a perfectly seamless transition.


