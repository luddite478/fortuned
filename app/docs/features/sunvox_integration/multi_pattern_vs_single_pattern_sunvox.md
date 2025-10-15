# Multi-Pattern vs Single-Pattern SunVox Architecture

## Context

When integrating SunVox into the sequencer, we need to decide how to map our table/section system to SunVox patterns.

**Our System:**
- **Table** = One continuous grid (full song, max 2048 steps)
- **Sections** = Variable-length subdivisions (logical/UI divisions)
- **Requirements:**
  - Start playback from arbitrary step
  - Seamless playback across section boundaries
  - Section rearranging (rarely used, but must work)

**SunVox:**
- **Pattern** = Grid of note events (tracks × lines)
- **Timeline** = Sequence of patterns played in order

---

## Option 1: Single Pattern (Current Implementation)

### Architecture
```
┌─────────────────────────────────┐
│  SunVox Pattern (2048 lines)    │
│                                  │
│  Lines 0-15:   Section A        │
│  Lines 16-31:  Section B        │
│  Lines 32-47:  Section C        │
└─────────────────────────────────┘

Sections are logical divisions only
```

### Pros ✅
- **Simple 1:1 mapping**: table cell → SunVox pattern event
- **Trivial arbitrary start**: `sv_rewind(0, step)` works directly
- **Easy sync**: Just update one pattern
- **Seamless section boundaries**: No pattern switch needed
- **Matches UI model**: One continuous grid
- **Less code complexity**

### Cons ⚠️
- **Section rearranging requires data copy**: Must physically move table data
- **Fixed max length**: Limited by `MAX_SEQUENCER_STEPS`
- **Manual loop handling**: Must call `sv_rewind()` for region loops

### Section Rearrange Implementation
```cpp
void table_rearrange_sections(int* new_order, int count) {
    // 1. Copy table data to temp buffer
    // 2. Rewrite table in new section order
    // 3. Update section metadata
    // 4. Resync entire pattern to SunVox
    
    // Heavy operation, but acceptable for rare use
}
```

---

## Option 2: Multi-Pattern (Alternative)

### Architecture
```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Pattern 0   │  │  Pattern 1   │  │  Pattern 2   │
│  (Section A) │  │  (Section B) │  │  (Section C) │
│  16 lines    │  │  16 lines    │  │  16 lines    │
└──────────────┘  └──────────────┘  └──────────────┘

Timeline: [0, 1, 2]
Rearrange: [0, 2, 1] (just change order!)
```

### Pros ✅
- **Trivial section rearranging**: Just update timeline order (non-destructive)
- **Natural section independence**: Each section is separate entity
- **SunVox handles transitions**: Automatic pattern switching
- **Variable section lengths**: Each pattern has its own length

### Cons ⚠️
- **Complex arbitrary start**:
  ```cpp
  playback_start(bpm, step=73) {
      // 1. Find which section contains step 73
      // 2. Calculate local line within that section
      // 3. Set SunVox timeline position to that section
      // 4. Rewind to local line
  }
  ```
- **Complex cell sync**: Must translate global step → (pattern, line)
- **More code complexity**: Pattern management, timeline handling
- **Harder to edit across section boundaries**

---

## SunVox Pattern Transitions

**Question:** Are pattern transitions seamless?

**Answer:** ✅ **Yes, absolutely.**

SunVox is a tracker - seamless pattern transitions are fundamental. When timeline plays Pattern 0 → Pattern 1 → Pattern 2, there are **no gaps or glitches**. Audio is continuous.

---

## Decision: Single Pattern (Recommended)

### Reasoning

1. **Arbitrary start is core feature** (frequently used)
   - Single pattern: trivial implementation
   - Multi-pattern: complex translation logic

2. **Section rearranging is rare** (infrequently used)
   - Single pattern: heavier operation (acceptable)
   - Multi-pattern: elegant but overkill

3. **Simplicity wins** when both approaches work
   - Single pattern: less code, less complexity
   - Already partially implemented

4. **Seamless boundaries guaranteed**
   - Single pattern: no pattern switch needed (inherently seamless)
   - Multi-pattern: relies on SunVox transitions (also seamless)

### When to Reconsider

Consider multi-pattern if:
- Section rearranging becomes **frequent** (live performance, arrangement UI)
- Need **pattern pool** / "clip launcher" type interface
- Want **independent section loop counts** handled by SunVox
- `MAX_SEQUENCER_STEPS` limit becomes problematic

---

## Implementation Status

**Current:** Single pattern implementation in `playback_sunvox.mm`
- ✅ Basic playback works
- ✅ Arbitrary start via `sv_rewind(0, step)`
- ✅ Manual region looping (lines 393-403)
- ⏳ Section rearranging not yet implemented

**Next Steps:**
1. Complete single-pattern implementation
2. Test arbitrary start positions
3. Implement section rearranging (when needed)
4. Re-evaluate if requirements change

