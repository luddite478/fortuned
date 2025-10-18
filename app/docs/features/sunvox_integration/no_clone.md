
# SunVox No-Clone Sequencer Implementation

**Date:** October 15, 2025  
**Status:** ✅ Complete and Verified

## 1. Overview

This document provides a comprehensive guide to the "no-clone" sequencer implementation in Fortuned. This approach eliminates the need for creating duplicate (cloned) patterns for looping, instead managing playback via sample-accurate loop counting and sequence management directly within the SunVox audio engine.

This new system is simpler, more memory-efficient, and provides sample-accurate transitions, resolving previous issues with audio glitches and complex timeline management.

---

## 2. The Problem with Pattern Clones

The previous implementation relied on creating a new pattern clone on the timeline for every loop of a section. For example, a section that looped 4 times would create the original pattern plus 3 clones.

This caused several problems:
-   **High Memory Usage:** Each clone consumed memory, leading to a large footprint for projects with many loops.
-   **Complex Timeline Management:** Adding, deleting, or reordering sections required complex logic to manage and rebuild the clone structure.
-   **Bugs in Playback:** Loop modes and seamless switching were difficult to implement correctly due to the proliferation of clone patterns with different IDs.
-   **Slow Operations:** Rebuilding the timeline with many clones was slow.

---

## 3. The "No-Clone" Solution

The new architecture is based on a simple principle: **one section = one pattern**. Loop counting is handled entirely within a modified SunVox engine, not by manipulating the timeline.

### How It Works

1.  **Engine Modifications:** We added new arrays to the SunVox engine struct (`sunvox_engine.h`) to track loop counts and playback sequences for patterns.
2.  **Sample-Accurate Loop Counting:** The audio callback (`sunvox_engine_audio_callback.cpp`) was modified to check these new arrays. When a pattern reaches its end, the engine decides whether to loop again or advance to the next pattern in the sequence, all within the same audio buffer.
3.  **New APIs:** We exposed new functions (`sv_set_pattern_loop_count`, `sv_set_pattern_sequence`) to control this behavior from the application layer.
4.  **Simplified Wrapper:** The `sunvox_wrapper.mm` no longer creates clones. It simply lays out the single pattern for each section sequentially and uses the new APIs to configure the playback behavior.

### System Architecture

#### Engine-Level (SunVox Library)

-   **Modified Files:**
    -   `lib_sunvox/sunvox_engine.h`: Added loop tracking arrays.
    -   `lib_sunvox/sunvox_engine_audio_callback.cpp`: Core loop counting logic.
    -   `sunvox_lib/headers/sunvox.h`: New API declarations.
    -   `sunvox_lib/main/sunvox_lib.cpp`: New API implementations.
-   **Key Data Structures:**
    ```c
    int pattern_loop_counts[256];    // Loop count per pattern (0 = infinite)
    int pattern_current_loop[256];   // Current loop iteration
    int pattern_sequence[64];        // Pattern playback order for song mode
    int pattern_sequence_count;      // Number of patterns in sequence
    ```
    These arrays use a conservative size of 256 to provide a safety buffer beyond the app's 64-section limit, preventing the need for bounds checking in the audio callback. The total memory overhead is negligible (~2.3 KB).

#### Application-Level (Playback System)

-   **Modified Files:**
    -   `app/native/playback_sunvox.mm`: Manages playback state and detects when the song has stopped.
    -   `app/native/sunvox_wrapper.mm`: Implements mode switching logic using the new APIs.

---

## 4. Behavior Specification

### Song Mode (Counted Loops)

-   **Flow:** Sections play in the defined sequence. Each section loops its configured number of times before advancing to the next. Playback stops after the last loop of the last section.
-   **Counter:** The UI correctly displays the current loop (e.g., "1/4", "2/4") and preserves the final count (e.g., "4/4") when playback stops, preventing a jarring jump back to "1/4".

### Loop Mode (Infinite Loop)

-   **Flow:** A single section is selected and loops indefinitely.
-   **Behavior:** The engine is configured with a loop count of `0` (infinite) for the active pattern. The UI counter remains frozen (e.g., "1/4") as the section repeats.

---

## 5. API Reference

### `sv_set_pattern_loop_count(slot, pat_num, loops)`
Sets how many times a pattern should loop before advancing. Also resets the pattern's current loop counter.
-   `loops`: Number of loops. `0` means infinite.

### `sv_get_pattern_current_loop(slot, pat_num)`
Gets the current loop iteration for a pattern (0-indexed).

### `sv_set_pattern_sequence(slot, pattern_ids, count)`
Defines the order of patterns for song mode playback.

---

## 6. Build Instructions

To use the no-clone solution, the modified SunVox static library must be rebuilt.

### iOS
```bash
cd /Users/romansmirnov/projects/fortuned/app/native/sunvox_lib/sunvox_lib/make
bash MAKE_IOS
```
**Output:** `/Users/romansmirnov/projects/fortuned/app/native/sunvox_lib/sunvox_lib/ios/libsunvox.a`

### Android
```bash
cd /Users/romansmirnov/projects/fortuned/app/native/sunvox_lib/sunvox_lib/make
bash MAKE_ANDROID
```
**Output:** `../android/lib_*/libsunvox.so`

After rebuilding the library, clean and rebuild the Flutter application:
```bash
cd /Users/romansmirnov/projects/fortuned/app
flutter clean
flutter pub get
flutter run
```

---

## 7. Implementation Questions & Safety

-   **Can I set values from the wrapper?** Yes, the new API functions (`sv_set_pattern_loop_count`, etc.) are designed for this purpose and are thread-safe.
-   **Can patterns be resized during playback?** Yes. Growing a pattern is seamless. Shrinking a pattern may cause the playhead to wrap if it's outside the new bounds, so it's best to stop playback before shrinking. All resizing operations must be protected with `sv_lock_slot()`.
-   **Is the modification safe?** Yes. The changes are isolated and backward-compatible.
    -   If loop counts are not set (`0`), patterns loop infinitely as before.
    -   The logic only affects pattern loop mode (`single_pattern_play`), leaving timeline playback unaffected.
    -   It reuses SunVox's existing `next_single_pattern_play` mechanism, ensuring it integrates cleanly with the engine's internal logic.
    -   It gracefully handles edge cases like empty sequences or deleted patterns.

The implementation is considered low-risk and production-ready.



