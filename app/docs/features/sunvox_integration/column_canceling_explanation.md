# Column Canceling in SunVox - How It Works

## Summary

**Column canceling is AUTOMATIC in SunVox's pattern engine!** ✅

When a new note plays on a track/column, SunVox automatically sends NOTE_OFF to any previous note playing on that same track. This is built into the pattern playback engine and happens **before** the new note starts playing.

## The Mechanism

### Source Code (sunvox_engine_audio_callback.cpp, lines 564-569)

```cpp
// When playing a new note on a track:
if( ( state->track_status & track_bit ) &&
    state->track_module[ track_num ] != mod_num )
{
    // A note is already playing on this track from a different module
    int mod_num2 = state->track_module[ track_num ];
    module_evt.command = PS_CMD_NOTE_OFF;  // Send NOTE_OFF
    psynth_add_event( mod_num2, &module_evt, net );  // Stop previous note
}

// THEN play the new note
module_evt.command = PS_CMD_NOTE_ON;
psynth_add_event( mod_num, &module_evt, net );
```

### Track Status Tracking

SunVox maintains per-track state:
- `track_status`: Bitmask indicating which tracks have active notes
- `track_module[track_num]`: Which module is currently playing on each track

### Canceling Logic

```
Track 0 timeline:

Line 0: Kick plays (Module 5)
└─ track_status[0] = 1 (active)
└─ track_module[0] = 5

Line 5: Snare plays (Module 7)
├─ Check: track_status[0] = 1? YES (something playing)
├─ Check: track_module[0] (5) != new module (7)? YES (different)
├─ Send: NOTE_OFF to Module 5 ← AUTOMATIC CANCELING!
├─ Update: track_module[0] = 7
└─ Play: Snare (Module 7)

Result: Kick STOPS before Snare starts ✅
```

### Same Module Case

```
Track 0 timeline:

Line 0: Kick plays (Module 5)
└─ track_module[0] = 5

Line 5: Another Kick plays (SAME Module 5)
├─ Check: track_status[0] = 1? YES
├─ Check: track_module[0] (5) != new module (5)? NO (same!)
└─ Don't send NOTE_OFF (module handles retriggering internally)

Result: Module 5 retriggers (polyphony or voice stealing) ✅
```

## How This Works with Column-Based Effect Chains

### Architecture

```
Column 0:
├─ Sampler: Col0_Kick (Module 5) ──┐
├─ Sampler: Col0_Snare (Module 7) ─┼→ [Reverb] → [Delay] → [Filter] → Output
└─ Sampler: Col0_HiHat (Module 9) ─┘

Column 0 timeline:

Line 0: Kick (Module 5, reverb=20%)
├─ Set effect chain: reverb_wet=51
├─ Play: Module 5
├─ track_module[0] = 5
└─ Audio flows through: Module 5 → Reverb(20%) → Delay → Filter → Output

Line 5: Snare (Module 7, reverb=40%, delay=60%)
├─ Check: track_module[0] (5) != new (7)? YES
├─ **AUTOMATIC:** Send NOTE_OFF to Module 5 ← Kick STOPS!
├─ Set effect chain: reverb_wet=102, delay_wet=154
├─ Play: Module 7
├─ track_module[0] = 7
└─ Audio flows through: Module 7 → Reverb(40%) → Delay(60%) → Filter → Output

✅ Kick STOPS before we change effects!
✅ Safe to reconfigure effect chain!
✅ Snare plays with NEW effect settings!
```

### Critical Sequence

**The order is:**
1. **NOTE_OFF sent to previous module** (automatic by SunVox)
2. **Previous note stops** (module voice off)
3. **We configure effect chain** (safe, no audio playing)
4. **New note plays** (new module, through configured chain)

**Timing:**
- All happens within same audio callback (sample-accurate)
- No gap or glitch in audio
- Effect changes don't affect stopped note

## Why This is Perfect for Per-Cell Effects

### The Problem It Solves

**Without column canceling:**
```
❌ Line 0: Kick plays with reverb=20%
❌ Line 5: Change reverb to 40% for Snare
❌ Problem: Kick (still playing) ALSO gets 40% reverb!
```

**With column canceling:**
```
✅ Line 0: Kick plays with reverb=20%
✅ Line 5: Kick AUTO-CANCELLED by SunVox
✅ Change reverb to 40% (safe, kick stopped)
✅ Snare plays with reverb=40%
✅ No bleed! Each cell independent!
```

### Polyphony Across Columns

```
Same time (Line 5):

Column 0: Kick (Module 5, reverb=20%)
└─ Uses Column 0's effect chain
└─ Audio: Module 5 → Col0_Reverb(20%) → Output

Column 1: Snare (Module 37, reverb=40%)
└─ Uses Column 1's effect chain
└─ Audio: Module 37 → Col1_Revered(40%) → Output

Column 2: HiHat (Module 69, reverb=10%)
└─ Uses Column 2's effect chain  
└─ Audio: Module 69 → Col2_Reverb(10%) → Output

✅ All play SIMULTANEOUSLY with DIFFERENT reverb!
✅ Each column independent!
✅ No conflicts!
```

## Implementation in Fortuned

### Current Implementation (sunvox_wrapper.mm)

```cpp
// Fortuned currently just sets pattern events
void sunvox_wrapper_sync_cell(int step, int col) {
    // ...
    sv_set_pattern_event(
        SUNVOX_SLOT,
        pat_id,
        col,           // Track number
        local_line,
        final_note,
        velocity,
        mod_id + 1,    // Module (Sampler)
        0, 0           // No effects yet
    );
    // ...
}
```

**Column canceling happens automatically when pattern plays!**

SunVox pattern engine sees:
- Line 0, Track 0: Play Module 5
- Line 5, Track 0: Play Module 7
- Engine: "Track 0 already has Module 5? Send NOTE_OFF first!"

### With Effect Chains (Future)

```cpp
void play_cell(int step, int col) {
    Cell* cell = get_cell(step, col);
    int sampler_mod = col * NUM_SAMPLES + cell->sample_id;
    
    // Configure effect chain BEFORE playing
    // (Safe because SunVox will auto-cancel previous note)
    ColumnEffects* fx = &g_column_effects[col];
    sv_set_module_ctl_value(SUNVOX_SLOT, fx->reverb, 0, cell->reverb_wet, 0);
    sv_set_module_ctl_value(SUNVOX_SLOT, fx->delay, 2, cell->delay_wet, 0);
    
    // Play note (SunVox auto-cancels previous if needed)
    sv_send_event(SUNVOX_SLOT, col, note, velocity, sampler_mod + 1, 0, 0);
    
    // Order of operations (all in same audio callback):
    // 1. SunVox checks: track_status[col] active? YES
    // 2. SunVox sends: NOTE_OFF to previous module
    // 3. Previous note: STOPS
    // 4. Effect changes: Applied to chain
    // 5. New note: Plays through configured chain
}
```

## Edge Cases

### Empty Cell After Note

```
Line 0: Kick plays (Module 5)
Line 5: Empty cell (no event)

SunVox behavior:
- No new note event on Line 5
- Previous note (Kick) continues playing
- No NOTE_OFF sent

✅ Expected behavior for sustained notes
```

### Pattern Looping

```
With NO_NOTES_OFF flag (Fortuned uses this):
- Pattern loops back to Line 0
- Notes DON'T get cancelled at loop boundary
- Allows seamless looping

Without NO_NOTES_OFF flag:
- All notes get NOTE_OFF at pattern end
- Pattern loop starts fresh
```

### Multiple Columns Same Sample

```
Line 5:
├─ Column 0: Kick (Module 5, reverb=20%)
└─ Column 1: Kick (Module 37, reverb=40%)

✅ Works! Different modules (5 vs 37)
✅ Different columns (0 vs 1)
✅ Different effect chains
✅ Both play simultaneously
```

## Conclusion

**Column canceling is built-in and automatic!** ✅

- Happens in SunVox's pattern playback engine
- Sends NOTE_OFF to previous note on same track
- Happens BEFORE new note plays
- Perfect for column-based effect chains
- Allows safe effect reconfiguration per-cell
- No additional code needed in Fortuned!

**This is why the column-based effect chain architecture works!** 🎯



