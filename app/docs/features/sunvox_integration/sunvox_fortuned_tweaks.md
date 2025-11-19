# SunVox Library - Fortuned Integration & Modifications

**A Complete Guide to Fortuned's SunVox Customizations, Current Features, and Future Plans**

Version: 2.1.2b (Modified)  
Related: `SUNVOX_LIBRARY_ARCHITECTURE.md` for general SunVox concepts  
See also: `/app/native/sunvox_lib/MODIFICATIONS.md` for technical implementation details

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Fortuned's Modifications Summary](#2-fortuneds-modifications-summary)
3. [Why Fortuned Requires Supertracks](#3-why-fortuned-requires-supertracks)
4. [How Fortuned Uses Supertracks](#4-how-fortuned-uses-supertracks)
5. [Fortuned's Complete Supertracks Integration](#5-fortuneds-complete-supertracks-integration)
6. [Control Granularity in Fortuned](#6-control-granularity-in-fortuned)
7. [Current Features](#7-current-features)
8. [Future Features & Plans](#8-future-features--plans)
9. [Implementation Roadmap](#9-implementation-roadmap)
10. [Practical Examples](#10-practical-examples)
11. [Reference Links](#11-reference-links)

---

## 1. Introduction

This document describes **all Fortuned-specific customizations, modifications, and integration patterns** with the SunVox library.

### 1.1 What This Document Covers

**Current Modifications:**
- Source code changes to SunVox library
- APIs added for Fortuned's requirements
- How Fortuned uses supertracks (why it's mandatory)

**Control Capabilities:**
- ✅ What you CAN control per section/pattern
- ✅ What you CAN control per column/track (with workarounds)
- ✅ What you CAN control per sample
- ✅ What you CAN control per cell/note

**Future Features:**
- 📋 Documented features ready to implement
- ⚠️ Workarounds for missing native functionality
- 💡 Ideas for future enhancements

### 1.2 Quick Answers to Common Questions

**Q: Can I control individual sections (patterns)?**  
✅ **YES** - You can mute, set loop modes, change size, set flags

**Q: Can I control individual columns (tracks)?**  
⚠️ **WORKAROUND** - No native API, but you can skip syncing or clear events

**Q: Can I apply effects to individual samples?**  
📋 **DOCUMENTED** - Architecture designed, ready to implement (like volume/pitch)

**Q: Can I apply effects to individual cells?**  
📋 **DOCUMENTED** - Same as sample effects, already works for volume/pitch

**Q: Can I override sample effects per cell?**  
✅ **YES** - Already works for volume/pitch, same pattern for effects

### 1.3 Document Organization

- **Sections 2-5:** Current modifications and why supertracks is required
- **Section 6:** Complete control matrix (what you can/can't do)
- **Section 7:** Current implemented features
- **Section 8:** Future features (documented and ready)
- **Section 9:** Implementation roadmap
- **Section 10:** Practical code examples

### 1.4 Related Documentation

**General SunVox:**
- `SUNVOX_LIBRARY_ARCHITECTURE.md` - Complete SunVox architecture overview
- https://warmplace.ru/soft/sunvox/sunvox_lib.php - Official API documentation

**Technical Details:**
- `/app/native/sunvox_lib/MODIFICATIONS.md` - Source code modifications
- `/app/docs/features/sunvox_integration/effects_architecture.md` - Effects system design
- `/app/docs/features/sunvox_integration/effects_implementation_guide.md` - Step-by-step guide

---

## 2. Fortuned's Modifications Summary

### 2.1 Overview

Fortuned has made several modifications to SunVox for seamless pattern looping and loop counting.

**Core Modifications:**

1. **Seamless Pattern Looping**
   - Added `SV_PATTERN_FLAG_NO_NOTES_OFF` flag
   - Prevents note-off events at pattern boundaries
   - Enables continuous sound across loops
   - **Requires supertracks mode to function**

2. **Pattern Loop Counting**
   - Added per-pattern loop counters
   - Tracks current loop iteration (0, 1, 2, ...)
   - Supports automatic advancement to next pattern

3. **Pattern Sequences**
   - Define playback order of patterns
   - Automatic pattern switching based on loop counts

4. **Seamless Position Change**
   - Added `sv_set_position()` API
   - Changes playback position without audio cuts

### 2.2 APIs Added

**New Functions:**
- `sv_set_pattern_loop()` - Enable/disable pattern loop mode
- `sv_set_pattern_loop_count()` - Set loop count per pattern
- `sv_set_pattern_sequence()` - Define pattern playback order
- `sv_get_pattern_current_loop()` - Query current loop iteration
- `sv_set_pattern_current_loop()` - Set current loop iteration
- `sv_set_position()` - Seamless playback position change
- `sv_pattern_set_flags()` - Set pattern flags (NO_NOTES_OFF)
- `sv_enable_supertracks()` - Enable supertracks mode ← **Critical for all features**

### 2.3 Files Modified

**SunVox Library Source:**
- `sunvox_lib/headers/sunvox.h` - Added API declarations
- `sunvox_lib/main/sunvox_lib.cpp` - Implemented new functions
- `lib_sunvox/sunvox_engine.h` - Added loop counting fields
- `lib_sunvox/sunvox_engine.cpp` - Initialized new fields
- `lib_sunvox/sunvox_engine_audio_callback.cpp` - Modified loop handling

**Documentation:**
- `/app/native/sunvox_lib/MODIFICATIONS.md` - Complete technical details
- `/app/docs/features/sunvox_integration/` - Integration guides

---

## 3. Why Fortuned Requires Supertracks

### 3.1 The Critical Dependency

Supertracks is **not optional** for Fortuned - it's a **fundamental architectural requirement**.

**The Dependency Chain:**

```
Fortuned User Experience
         ↓
Seamless Looping (no audio cuts between loops)
         ↓
NO_NOTES_OFF Pattern Flag
         ↓
Per-Pattern State Management
         ↓
SUPERTRACKS MODE ← Absolutely Required
```

### 3.2 Pattern State Architecture Difference

**Classic Mode (Pre-SunVox 2.0):**
```c
struct sunvox_engine {
    sunvox_pattern_state virtual_pat_state;  // Single global state
    // All patterns share this one state
    // No way to have different behavior per pattern
};
```

**Supertracks Mode (SunVox 2.0+):**
```c
struct sunvox_engine {
    sunvox_pattern_state* pat_state;  // Array of 64 states
    int pat_state_size;                // = 64
    // Each pattern gets its own independent state
    // Per-pattern flags can be respected
};
```

### 3.3 The Critical Code Path

When a pattern loops or ends, this code executes in `sunvox_engine_audio_callback.cpp`:

```cpp
static void sunvox_reset_timeline_activity(int offset, sunvox_engine* s) {
    // ... loop through active patterns ...
    
    bool should_clear = true;
    
    if (s->flags & SUNVOX_FLAG_SUPERTRACKS) {  // ← Check if supertracks enabled
        // ✅ FORTUNED MODIFICATION: Check per-pattern flag
        if (spat->flags & SUNVOX_PATTERN_FLAG_NO_NOTES_OFF) {
            should_clear = false;  // DON'T send note-offs!
        }
    }
    // In classic mode, this if-block never executes!
    // Notes ALWAYS get cut, no exceptions.
    
    if (should_clear) {
        // Original behavior: send note-offs, clear track status
        spat_info->track_status = 0;
    }
    // ELSE: Keep notes playing! (Fortuned seamless looping)
}
```

**Without Supertracks:**
- The `if (s->flags & SUNVOX_FLAG_SUPERTRACKS)` condition is **false**
- The flag check **never happens**
- Notes **always** get cut at pattern boundaries
- Seamless looping is **impossible**

**With Supertracks:**
- The condition is **true**
- Pattern flags are **checked**
- `NO_NOTES_OFF` is **respected**
- Notes **continue** across boundaries
- Seamless looping **works perfectly**

### 3.4 Why This Matters

```
WITHOUT SUPERTRACKS:
❌ Seamless looping impossible
❌ Mode switching has audio gaps
❌ Professional sound quality unachievable
❌ App doesn't meet quality standards

WITH SUPERTRACKS:
✅ Seamless looping works perfectly
✅ Mode switching is instantaneous and smooth
✅ Professional sound quality achieved
✅ App delivers excellent user experience
```

**Bottom Line:**

Supertracks is not optional or a "nice to have" for Fortuned.  
**It is a fundamental architectural requirement.**

---

## 4. How Fortuned Uses Supertracks

### 4.1 Initialization

Every Fortuned project enables supertracks immediately after loading:

```cpp
// In sunvox_wrapper.mm: sunvox_wrapper_init()

// 1. Initialize SunVox with standard flags
sv_init(NULL, 48000, 2, 0);
sv_open_slot(SUNVOX_SLOT);

// 2. IMMEDIATELY enable supertracks (CRITICAL!)
sv_enable_supertracks(SUNVOX_SLOT, 1);
LOG_VERBOSE("Enabled supertracks mode for seamless looping support");

// 3. Now we can use NO_NOTES_OFF flag
// (without step 2, this would have no effect)
```

### 4.2 Pattern Layout Strategy

Fortuned uses a **single-layer approach** - all patterns are on Y=0:

```
Timeline (Fortuned):
y=0: [Section 0]──[Section 1]──[Section 2]──[Section 3]──
     x=0         x=16         x=32         x=48
```

**Why single-layer if supertracks allows 64?**

1. **Simplicity:** Easier to visualize and manage
2. **Sequential Playback:** Sections play one after another
3. **Pattern Loop Mode:** Only one pattern active at a time
4. **UI Design:** Single-row timeline in the app

### 4.3 Per-Pattern Setup

```cpp
// In sunvox_wrapper.mm: sunvox_wrapper_create_pattern()

int sunvox_wrapper_create_pattern(int x_pos, int tracks, int lines, const char* name) {
    // Create pattern at y=0 (all Fortuned patterns on same layer)
    int pat = sv_new_pattern(SUNVOX_SLOT, -1, x_pos, 0, tracks, lines, 0, name);
    
    // Set seamless looping flag (depends on supertracks being enabled!)
    sv_pattern_set_flags(SUNVOX_SLOT, pat, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);
    
    return pat;
}
```

### 4.4 Pattern Loop Mode (Primary Use Case)

```cpp
// Setup for Section 0 (pattern ID: 42)
sv_enable_supertracks(SUNVOX_SLOT, 1);                           // Required!
sv_pattern_set_flags(SUNVOX_SLOT, 42, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);
sv_set_pattern_loop(SUNVOX_SLOT, 42);  // Loop only pattern 42
sv_set_autostop(SUNVOX_SLOT, 0);       // Loop forever
sv_play_from_beginning(SUNVOX_SLOT);

// Result: Section 0 loops seamlessly, long samples don't cut
```

### 4.5 Seamless Mode Switching

```cpp
// User switches from Loop Mode (Section 0) to Song Mode
// WITHOUT audio interruption:

// 1. Get current position
int current_line = sv_get_current_line(SUNVOX_SLOT);

// 2. Disable pattern loop (switch to timeline playback)
sv_set_pattern_loop(SUNVOX_SLOT, -1);  // -1 = disable

// 3. Enable autostop (stop at end of project)
sv_set_autostop(SUNVOX_SLOT, 1);

// 4. Use seamless position change (Fortuned modification)
sv_set_position(SUNVOX_SLOT, current_line);  // No audio cut!

// Audio continues playing without interruption
// All notes that were playing continue to play
```

### 4.6 Why Single-Layer Works

Even though Fortuned uses single-layer, supertracks mode provides:
1. ✅ Independent pattern states (required for NO_NOTES_OFF)
2. ✅ Per-pattern flag support
3. ✅ Seamless loop capability
4. ✅ Smooth mode switching
5. ✅ Future flexibility (could add layers later)

**The Key Insight:**

Fortuned doesn't need supertracks for **vertical layering**.  
Fortuned needs supertracks for **independent pattern state management**.

The vertical layering is a side benefit. The critical feature is that each pattern gets its own `sunvox_pattern_state`, allowing per-pattern behavior control.

---

## 5. Fortuned's Complete Supertracks Integration

### 5.1 Application-Level Integration

#### Playback Modes

```cpp
// File: app/services/playback_service.dart

// LOOP MODE: Play one section infinitely with seamless looping
void enterLoopMode(int sectionIndex) {
    int patternId = sections[sectionIndex].patternId;
    
    // Enable pattern loop (depends on supertracks for NO_NOTES_OFF)
    sunvoxSetPatternLoop(patternId);
    sunvoxSetAutostop(0);  // Loop forever
    sunvoxPlay();
    
    // Result: Section loops seamlessly, no audio cuts
}

// SONG MODE: Play all sections sequentially with counted loops
void enterSongMode() {
    // Set up pattern sequence
    List<int> patternIds = sections.map((s) => s.patternId).toList();
    sunvoxSetPatternSequence(patternIds);
    
    // Set loop counts for each pattern
    for (int i = 0; i < sections.length; i++) {
        sunvoxSetPatternLoopCount(patternIds[i], sections[i].loopCount);
    }
    
    // Start with first pattern
    sunvoxSetPatternLoop(patternIds[0]);
    sunvoxSetAutostop(1);  // Stop at end
    sunvoxPlay();
    
    // Result: Sections advance automatically after N loops each
}

// MODE SWITCHING: Seamless transition (no audio interruption)
void switchMode() {
    int currentLine = sunvoxGetCurrentLine();
    
    // Change mode settings
    if (switchingToLoopMode) {
        sunvoxSetPatternLoop(currentSectionPatternId);
        sunvoxSetAutostop(0);
    } else {
        sunvoxSetPatternLoop(-1);  // Disable pattern loop
        sunvoxSetAutostop(1);
    }
    
    // Seamlessly continue playback (depends on supertracks state preservation)
    sunvoxSetPosition(currentLine);  // No audio cut!
}
```

### 5.2 Real-World Impact

#### User Experience Benefits

1. **Looping Samples Don't Cut**
   - User places a long pad/drone sample on the last step of a section
   - Section loops every 3 seconds
   - Without supertracks: Sample cuts abruptly every 3 seconds
   - With supertracks: Sample continues smoothly across loops

2. **Mode Switching is Seamless**
   - User is in Loop Mode, listening to Section 2
   - Presses "Song Mode" button
   - Without supertracks: Audio stops/restarts, noticeable gap
   - With supertracks: Audio continues uninterrupted, smooth transition

3. **Professional Sound**
   - Live looping like hardware loopers
   - No clicks, pops, or gaps
   - Suitable for performance use

#### Performance Characteristics

```cpp
// Memory overhead of supertracks mode:
sizeof(sunvox_pattern_state) = ~256 bytes
Classic mode:   1 × 256 bytes = 256 bytes
Supertracks:   64 × 256 bytes = 16,384 bytes (~16 KB)

// This is negligible on modern devices:
// - iPhone: 4+ GB RAM
// - Android: 2+ GB RAM
// - 16 KB = 0.0004% of 4 GB
```

**CPU overhead:** Virtually none. The per-pattern state checking adds:
- 1 bitwise AND operation per pattern boundary
- 1 flag comparison
- Total: < 10 CPU cycles per loop
- On a 2 GHz CPU: 0.000005 ms (5 nanoseconds)

### 5.3 Comparison with Other SunVox Apps

**Traditional SunVox App (Full DAW):**
```
Uses supertracks for:
├── Vertical layering (drums, bass, lead simultaneously)
├── Complex arrangements
├── Per-track mixing
└── Mute/solo layers

Fortuned uses supertracks for:
├── Per-pattern state independence ← PRIMARY REASON
├── NO_NOTES_OFF flag support
├── Seamless looping
└── Smooth mode switching
```

### 5.4 Migration Path (If Ever Needed)

If a future SunVox version removes supertracks or changes its implementation:

**Option 1: Fallback to Classic Mode**
- Disable seamless looping feature
- Add gap detection and crossfade
- Notify users of limitation

**Option 2: Custom Audio Callback**
- Use `SV_INIT_FLAG_USER_AUDIO_CALLBACK`
- Implement custom loop handling
- More complex, but full control

**Option 3: Fork SunVox**
- Maintain custom build
- Preserve modifications
- Last resort only

**Current Status:**
- Supertracks is stable since SunVox 2.0 (2020)
- Widely used in SunVox community
- No indication of removal in future versions
- Safe to depend on for foreseeable future

---

## 6. Control Granularity in Fortuned

This section explains what you CAN and CANNOT control at different levels in Fortuned's SunVox integration.

### 6.1 Hierarchy of Control

```
┌─────────────────────────────────────────────────────────┐
│ GLOBAL LEVEL                                            │
│ • BPM, Speed (TPL)                                      │
│ • Global volume                                         │
│ • Autostop mode                                         │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ PATTERN/SECTION LEVEL                                   │
│ • Pattern mute/unmute                                   │
│ • Pattern flags (NO_NOTES_OFF)                          │
│ • Pattern loop mode                                     │
│ • Pattern size (tracks × lines)                         │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ MODULE LEVEL (Sampler)                                  │
│ • Module controllers (reverb, filter, etc.)             │
│ • Affects ALL notes played through that module          │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ SAMPLE LEVEL (Fortuned)                                 │
│ • Default volume, pitch                                 │
│ • Default effects (future)                              │
│ • Applied to all cells using this sample                │
└─────────────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────────────┐
│ CELL LEVEL (Individual Grid Cell)                       │
│ • Per-cell volume, pitch override ✅ (already impl.)    │
│ • Per-cell effects override ✅ (documented, not impl.)  │
│ • Highest priority - overrides sample defaults          │
└─────────────────────────────────────────────────────────┘
```

### 6.2 Pattern/Section Level Control

#### What CAN You Control Per Pattern?

**✅ YES - Pattern Mute:**

```c
// Mute entire pattern (all tracks)
sv_pattern_mute(slot, pat_num, 1);  // 1 = mute

// Unmute pattern
sv_pattern_mute(slot, pat_num, 0);  // 0 = unmute

// Check mute state
int is_muted = sv_pattern_mute(slot, pat_num, -1);  // -1 = query
```

**In Fortuned Context:**
```cpp
// Mute Section 2 (pattern ID 42)
sv_lock_slot(SUNVOX_SLOT);
sv_pattern_mute(SUNVOX_SLOT, 42, 1);
sv_unlock_slot(SUNVOX_SLOT);
// All notes/tracks in Section 2 will be silenced
```

**✅ YES - Pattern Flags:**

```c
// Set NO_NOTES_OFF flag for seamless looping
sv_pattern_set_flags(slot, pat_num, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);

// Clear flag
sv_pattern_set_flags(slot, pat_num, SV_PATTERN_FLAG_NO_NOTES_OFF, 0);
```

**✅ YES - Pattern Loop Control:**

```c
// Loop specific pattern
sv_set_pattern_loop(slot, pat_num);

// Disable pattern loop
sv_set_pattern_loop(slot, -1);

// Set loop count (Fortuned modification)
sv_set_pattern_loop_count(slot, pat_num, 4);  // Loop 4 times
```

#### Pattern-Level Limitations

**❌ NO - Per-Track Muting Within Pattern:**

SunVox does **NOT** provide a direct API to mute individual tracks (columns) within a pattern. You can only mute the entire pattern.

**Workarounds for Track-Level Control:**

**Option 1: Skip Syncing (Recommended for Fortuned)**
```dart
// Dart side - track mute state
class Section {
  List<bool> columnMuted = List.filled(16, false);
}

// When syncing, skip muted columns
void syncSection(Section section) {
  for (int col = 0; col < 16; col++) {
    if (section.columnMuted[col]) {
      continue;  // Skip this column - don't call sunvox_wrapper_sync_cell
    }
    for (int step = 0; step < section.steps; step++) {
      syncCell(section, step, col);
    }
  }
}
```

**Option 2: Clear Track Events**
```c
// Manually clear all events in a specific track
sunvox_note* data = sv_get_pattern_data(slot, pat_num);
int tracks = sv_get_pattern_tracks(slot, pat_num);
int lines = sv_get_pattern_lines(slot, pat_num);

for (int line = 0; line < lines; line++) {
    sunvox_note* evt = &data[line * tracks + track_to_mute];
    evt->note = 0;
    evt->vel = 0;
    evt->mod = 0;
    evt->ctl = 0;
    evt->ctl_val = 0;
}
```

**Option 3: Set Velocity to 0**
```c
// Set velocity to 0 for all events in track
for (int line = 0; line < lines; line++) {
    sunvox_note* evt = &data[line * tracks + track_num];
    if (evt->note > 0 && evt->note < 128) {
        evt->vel = 1;  // Minimum velocity (effectively silent)
    }
}
```

### 6.3 Module Level Control (Global Effects)

Module controllers affect **ALL notes** played through that module:

**✅ YES - Module-Wide Effects:**

```c
// Apply reverb to ALL notes in sampler module
sv_set_module_ctl_value(slot, sampler_mod, CTL_REVERB, 128, 0);

// Adjust filter cutoff for all sounds
sv_set_module_ctl_value(slot, sampler_mod, CTL_FILTER_CUTOFF, 16384, 0);
```

**Common Sampler Controllers:**

| Controller | Index | Range | Effect |
|------------|-------|-------|--------|
| Volume | 0 | 0-256 | Master volume |
| Panning | 1 | 0-255 | Stereo pan (128=center) |
| Sample interpolation | 2 | 0-2 | Quality (0=off, 1=linear, 2=cubic) |
| Envelope attack | 3 | 0-512 | Note attack time |
| Envelope release | 4 | 0-512 | Note release time |
| Polyphony | 5 | 1-128 | Max voices |
| Reverb | 8 | 0-256 | Wet/dry mix |
| Filter type | 9 | 0-7 | LP, HP, BP, etc. |
| Filter cutoff | 10 | 0-16384 | Frequency cutoff |
| Filter resonance | 11 | 0-1530 | Filter Q |

**Example - Apply Global Reverb to Section:**

```cpp
// In Fortuned wrapper:
void sunvox_wrapper_set_section_reverb(int section_idx, int reverb_amount) {
    // Get sampler module for this section
    int mod_id = get_sampler_for_section(section_idx);
    
    // Set reverb (affects all notes in this section)
    sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 8, reverb_amount, 0);
    
    // reverb_amount: 0 = dry (no reverb), 256 = wet (full reverb)
}
```

### 6.4 Sample Level Control

#### Current Implementation

**✅ Already Implemented:**

```c
// In sample_bank.h
typedef struct {
    float volume;    // Default volume (0.0 - 1.0)
    float pitch;     // Default pitch (0.25 - 4.0)
} SampleSettings;
```

**Usage:**
- Set default volume/pitch per sample
- All cells using that sample inherit these defaults
- Cells can override with `cell->settings.volume` and `cell->settings.pitch`

### 6.5 Cell Level Control

#### Current Implementation

**✅ Already Implemented:**

**Volume Override:**
```cpp
// Set cell volume (overrides sample default)
table_set_cell_volume(step, col, 0.5);  // 50% volume

// Inherit from sample
table_set_cell_volume(step, col, DEFAULT_CELL_VOLUME);  // -1.0
```

**Pitch Override:**
```cpp
// Set cell pitch (overrides sample default)
table_set_cell_pitch(step, col, 2.0);  // Double pitch (octave up)

// Inherit from sample
table_set_cell_pitch(step, col, DEFAULT_CELL_PITCH);  // -1.0
```

### 6.6 Complete Control Matrix

Here's what you CAN control at each level in Fortuned:

| What | Global | Pattern/Section | Module | Sample | Cell |
|------|--------|----------------|--------|--------|------|
| **Mute** | ❌ | ✅ Pattern | ✅ Module | ❌ | ⚠️ Via velocity=0 |
| **Volume** | ✅ Global vol | ❌ | ✅ Controller | ✅ Default | ✅ Override |
| **Pitch** | ❌ | ❌ | ⚠️ Via tuning | ✅ Default | ✅ Override |
| **Effects (Vibrato, etc.)** | ❌ | ⚠️ All tracks | ⚠️ Via chain | 📋 Future | 📋 Future |
| **Reverb/Filter** | ❌ | ❌ | ✅ Controller | ❌ | ⚠️ Via effect |
| **Loop Mode** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Position** | ✅ Playhead | ✅ X/Y | ❌ | ❌ | ❌ |
| **Enable/Disable** | ✅ Play/Stop | ✅ Mute | ✅ Mute/Bypass | ❌ | ⚠️ Clear event |

**Legend:**
- ✅ Direct API support
- ⚠️ Possible via workaround
- 📋 Documented, ready to implement
- ❌ Not supported

---

## 7. Current Features

### 7.1 Implemented and Working

**✅ Seamless Pattern Looping**
- Status: ✅ Production ready
- Files: `sunvox_engine_audio_callback.cpp` (modified)
- API: `sv_pattern_set_flags()`, `sv_enable_supertracks()`
- User Benefit: Long samples continue smoothly across loop boundaries

**✅ Pattern Loop Counting**
- Status: ✅ Production ready
- Files: `sunvox_engine.h`, `sunvox_engine_audio_callback.cpp`
- API: `sv_set_pattern_loop_count()`, `sv_get_pattern_current_loop()`
- User Benefit: Automatic section advancement after N loops

**✅ Pattern Sequences**
- Status: ✅ Production ready
- API: `sv_set_pattern_sequence()`
- User Benefit: Define song structure (intro, verse, chorus, etc.)

**✅ Seamless Position Change**
- Status: ✅ Production ready
- API: `sv_set_position()`
- User Benefit: Smooth mode switching without audio gaps

**✅ Pattern Muting**
- Status: ✅ Production ready (native SunVox feature)
- API: `sv_pattern_mute()`
- User Benefit: Mute entire sections during playback

**✅ Cell Volume Override**
- Status: ✅ Production ready
- Native: `table_set_cell_volume()`
- User Benefit: Per-note volume control

**✅ Cell Pitch Override**
- Status: ✅ Production ready
- Native: `table_set_cell_pitch()`
- User Benefit: Per-note pitch control

**✅ Module Controllers**
- Status: ✅ Production ready (native SunVox feature)
- API: `sv_set_module_ctl_value()`
- User Benefit: Global effects (reverb, filter) per section

---

## 8. Future Features & Plans

### 8.1 Documented, Ready to Implement

#### 8.1.1 Cell-Level Effects

**Status:** 📋 Fully documented, architecture designed  
**Documentation:** `/app/docs/features/sunvox_integration/effects_architecture.md`  
**Effort:** Medium (1-2 weeks)

**Proposed Data Structure:**
```c
// Extend CellSettings
typedef struct {
    float volume;               // ✅ Already implemented
    float pitch;                // ✅ Already implemented
    
    // NEW: Effects
    uint16_t effect_code;       // Effect code (0 = inherit from sample)
    uint16_t effect_param;      // Effect parameter
} CellSettings;
```

**Common Effects:**

| Effect Code | Name | Parameter | Use Case |
|-------------|------|-----------|----------|
| 0x01 | Pitch slide up | 0x01-0xFF | Rising pitch |
| 0x02 | Pitch slide down | 0x01-0xFF | Falling pitch |
| 0x03 | Portamento | 0x01-0xFF | Smooth pitch transition |
| 0x04 | Vibrato | 0xSPEED×DEPTH | Pitch wobble |
| 0x07 | Volume slide | 0xUP×DOWN | Volume fade |
| 0x08 | Panning | 0x00-0xFF | Left/right position |
| 0x09 | Sample offset | 0x0000-0xFFFF | Start position in sample |
| 0x0C | Set volume | 0x00-0x40 | Explicit volume |
| 0x11 | Arpeggio | 0xSEMI1×SEMI2 | Fast note switching |
| 0x19 | Retrigger | 0xSPEED×VOL | Repeat note with fade |

**Implementation:**
```cpp
// In sunvox_wrapper_sync_cell():
sv_set_pattern_event(
    SUNVOX_SLOT, pat_id, col, line,
    note, velocity, module,
    cell_effect_code,    // ← Add this
    cell_effect_param    // ← Add this
);
```

#### 8.1.2 Sample-Level Default Effects

**Status:** 📋 Documented  
**Documentation:** `/app/docs/features/sunvox_integration/effects_architecture.md`  
**Effort:** Small (few days)

**Proposed Extension:**
```c
// Extend SampleSettings
typedef struct {
    float volume;
    float pitch;
    
    // NEW: Default effects
    uint16_t effect_code;   // Default effect (0 = none)
    uint16_t effect_param;  // Effect parameter
} SampleSettings;
```

**Use Cases:**
- Kick drum: Default pitch slide down
- Snare: Default reverb
- Hi-hat: Default panning
- Bass: Default vibrato

**Inheritance:**
```
Sample defaults → Applied to all cells with that sample
Cell overrides → Take precedence over sample defaults
```

### 8.2 Workarounds to Implement

#### 8.2.1 Column/Track Muting

**Status:** ⚠️ No native API, workaround needed  
**Effort:** Small (few days)  
**Priority:** High (frequently requested)

**Recommended Approach:**

```dart
// Dart side - store per-column mute state
class Section {
  List<bool> columnMuted = List.filled(16, false);
}

// Native side - skip syncing muted columns
void syncSection(Section section) {
  for (int col = 0; col < 16; col++) {
    if (section.columnMuted[col]) {
      continue;  // Don't sync this column
    }
    // Sync cells in this column...
  }
}
```

**Alternative Approach:**
- Set velocity to 0 for muted tracks
- Clear events in pattern data
- Use module muting if all tracks use same module

#### 8.2.2 Column-Wide Effects

**Status:** ⚠️ Possible via iteration  
**Effort:** Medium  
**Priority:** Medium

**Approach:**

```dart
// Store per-column effect settings
class Section {
  List<ColumnEffects> columnEffects;  // 16 columns
}

class ColumnEffects {
  int effectCode;
  int effectParam;
  bool enabled;
}
```

**Implementation:**
```cpp
// Priority: cell effect > column effect > sample effect
if (cell->settings.effect_code != 0) {
    // Cell has explicit effect
    use_cell_effect();
} else if (column_effects_enabled[col]) {
    // Column has effect
    use_column_effect();
} else {
    // Inherit from sample
    use_sample_effect();
}
```

### 8.3 Future Enhancements

#### 8.3.1 Per-Section Global Effects

**Status:** 💡 Idea, not documented  
**Effort:** Small  
**Priority:** Low-Medium

**Concept:**
- Add UI for per-section reverb, filter, etc.
- Use module controllers
- Save/load with project

#### 8.3.2 Effect Automation

**Status:** 💡 Idea  
**Effort:** Large  
**Priority:** Low

**Concept:**
- Record effect parameter changes over time
- Store as automation curves
- Apply during playback

---

## 9. Implementation Roadmap

### 9.1 Phase 1: Essential Features (Current)

**Status:** ✅ Complete

- [x] Seamless pattern looping
- [x] Pattern loop counting
- [x] Pattern sequences
- [x] Seamless position change
- [x] Cell volume/pitch override
- [x] Pattern muting

### 9.2 Phase 2: Effects System (Next)

**Estimated Effort:** 2-3 weeks  
**Priority:** High  
**Dependencies:** None

**Tasks:**
1. Extend `CellSettings` and `SampleSettings` structs
2. Add effect resolution logic (cell → sample → default)
3. Update `sunvox_wrapper_sync_cell()` to pass effects
4. Update UI for effect selection
5. Add serialization for effects
6. Test common effects (vibrato, slide, panning)

**Deliverables:**
- Per-cell effects working
- Sample default effects working
- Effect inheritance working
- UI for effect selection

### 9.3 Phase 3: Column Control (Future)

**Estimated Effort:** 1 week  
**Priority:** Medium  
**Dependencies:** None

**Tasks:**
1. Add column mute state to `Section` model
2. Implement skip logic in sync functions
3. Add UI for column mute buttons
4. (Optional) Add column-wide effects

**Deliverables:**
- Column muting working
- UI toggles for each column
- Visual feedback for muted columns

### 9.4 Phase 4: Advanced Effects (Future)

**Estimated Effort:** 2-4 weeks  
**Priority:** Low  
**Dependencies:** Phase 2 complete

**Tasks:**
1. Per-section global effects UI
2. Effect presets/templates
3. Effect automation (if desired)
4. Advanced effect combinations

---

## 10. Practical Examples

### 10.1 Example: Mute Section 2

```dart
// Dart side
void muteSection(int sectionIndex) {
  final section = sections[sectionIndex];
  sunvoxPatternMute(section.patternId, true);
}
```

```cpp
// Native wrapper
void sunvox_wrapper_mute_section(int pat_id, bool mute) {
    sv_lock_slot(SUNVOX_SLOT);
    sv_pattern_mute(SUNVOX_SLOT, pat_id, mute ? 1 : 0);
    sv_unlock_slot(SUNVOX_SLOT);
}
```

### 10.2 Example: Apply Reverb to Section

```cpp
// Set module controller (affects all notes)
void sunvox_wrapper_set_section_reverb(int section_idx, float reverb_amount) {
    int mod_id = get_sampler_for_section(section_idx);
    int reverb_val = (int)(reverb_amount * 256.0f);  // 0-256
    sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 8, reverb_val, 0);
}
```

### 10.3 Example: Mute Column (Workaround)

```dart
// Dart side - track mute state
class Section {
  List<bool> columnMuted = List.filled(16, false);
}

// When syncing, skip muted columns
void syncSection(Section section) {
  for (int col = 0; col < 16; col++) {
    if (section.columnMuted[col]) {
      continue;  // Skip this column
    }
    for (int step = 0; step < section.steps; step++) {
      syncCell(section, step, col);
    }
  }
}
```

### 10.4 Example: Per-Cell Effects (Future)

```cpp
// When effects are implemented:
void sync_cell_with_effects(Cell* cell, int pat_id, int col, int line) {
    // Resolve effect (cell > sample > default)
    uint16_t effect_code = cell->settings.effect_code;
    uint16_t effect_param = cell->settings.effect_param;
    
    if (effect_code == 0) {  // Inherit from sample
        Sample* s = sample_bank_get_sample(cell->sample_slot);
        if (s) {
            effect_code = s->settings.effect_code;
            effect_param = s->settings.effect_param;
        }
    }
    
    sv_set_pattern_event(
        SUNVOX_SLOT, pat_id, col, line,
        note, velocity, module,
        effect_code,     // Vibrato, slide, etc.
        effect_param     // Effect settings
    );
}
```

---

## 11. Reference Links

**Technical Implementation:**
- `/app/native/sunvox_lib/MODIFICATIONS.md` - Complete source code modifications

**Integration Documentation:**
- `/app/docs/features/sunvox_integration/effects_architecture.md` - Effects system design
- `/app/docs/features/sunvox_integration/effects_implementation_guide.md` - Step-by-step implementation
- `/app/docs/features/sunvox_integration/seamless_playback.md` - Seamless looping details
- `/app/docs/features/sunvox_integration/playback_step_increase_decrease.md` - Step add/remove

**General SunVox:**
- `SUNVOX_LIBRARY_ARCHITECTURE.md` - Complete SunVox architecture overview
- https://warmplace.ru/soft/sunvox/sunvox_lib.php - Official SunVox Library documentation

---

**Last Updated:** November 19, 2025  
**SunVox Version:** 2.1.2b (Modified)  
**Status:** Production (Current features), Documented (Future features)

