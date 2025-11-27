# Section Gap Bug Investigation - Quick Reference

**Last Updated:** November 16, 2025  
**Status:** 🟡 Awaiting test logs with diagnostic output

---

## 📋 Quick Links

| Document | Purpose |
|----------|---------|
| **[DIAGNOSTIC GUIDE](./SECTION_GAP_DIAGNOSTIC_GUIDE.md)** | ⭐ **START HERE** - How to test and what logs to capture |
| **[FINDINGS SUMMARY](./SECTION_GAP_FINDINGS_SUMMARY.md)** | What we've found so far and possible causes |
| **[DEEP ANALYSIS](./SECTION_GAP_DEEP_ANALYSIS.md)** | Technical deep dive into the codebase |
| **[BUG ANALYSIS](./SECTION_GAP_BUG_ANALYSIS.md)** | Original bug analysis and fix attempt |
| **[CURRENT STATE](./SECTION_GAP_CURRENT_STATE.md)** | Investigation progress tracking |

---

## 🎯 The Bug

**Symptom:** When playing in song mode and transitioning from section 9 to section 10, the playback doesn't start at the first step of section 10. It jumps ahead by several steps.

**Example:**
- Section 10 starts at step 204 (should play steps 204-219)
- But playback actually starts at step 209 (skipping steps 204-208)
- Result: First 5 notes of section 10 are never played

---

## ✅ What's Fixed

The `table_recompute_section_starts()` fix IS working:
- Sections are perfectly contiguous in the table
- No gaps between section ranges
- Import correctly computes section start steps

---

## ❓ What's Unknown

We need to determine:
1. Are SunVox pattern X positions correctly aligned with section start steps?
2. When transitioning to section 10, what SunVox line does playback jump to?
3. Is the bug in timeline layout, playback calculation, or SunVox's pattern advancement?

---

## 🔧 What's Changed

### New Logging Added

1. **Timeline layout logging** - Shows pattern X positions after import
2. **Playback position logging** - Shows SunVox line → section → step mapping
3. **Boundary detection** - Warns if playback goes past timeline end

### Files Modified

- `app/native/sunvox_wrapper.mm` - Timeline logging
- `app/native/playback_sunvox.mm` - Position tracking logging

---

## 🚀 What You Need to Do

### 1. Rebuild
```bash
cd /Users/romansmirnov/projects/fortuned
./run.sh
```

### 2. Load Project
Open project ID: `69162e4ed22c469f10ad2d97`

### 3. Reproduce Bug
- Start playback from section 9
- Let it play through section 9's loops
- Watch as it transitions to section 10
- Observe that section 10 doesn't start from step 0

### 4. Capture Logs
Save terminal output and share:
```bash
./run.sh 2>&1 | tee section-bug-logs.txt
```

---

## 📊 What We'll Look For In The Logs

### After Import
```
🗺️ [SUNVOX TIMELINE] === UPDATING PATTERN LAYOUT (seamless) ===
  Section 0: Pattern 10 at x=0 (16 lines, ends at 16)
  ...
  Section 9: Pattern 8 at x=188 (16 lines, ends at 204)
  Section 10: Pattern 9 at x=204 (16 lines, ends at 220)  ← Should be x=204!
🗺️ [SUNVOX TIMELINE] =============================
```

### During Transition
```
🎯 [PLAYBACK POS] SunVox line 203 → Section 9, local_line 15, ...
🎯 [PLAYBACK POS] SunVox line ??? → Section 10, local_line ???, ...
                              ↑            ↑
                        Should be 204  Should be 0
```

---

## 🎯 Expected Results

| Metric | Expected | If Bug Exists |
|--------|----------|---------------|
| Section 10 pattern X position | 204 | Might be wrong |
| SunVox line when section 10 starts | 204 | Might be > 204 |
| Local line in section 10 | 0 | Might be > 0 |
| Global step | 204 | Might be > 204 |

---

## 📞 Contact

Once you have the logs:
1. Share the complete terminal output
2. Include a screenshot of the UI showing the bug
3. Note which step number is displayed when section 10 "starts"

---

## ⏱️ Time Estimate

- **Your time:** 5-10 minutes (rebuild + test + capture logs)
- **Analysis time:** 30-60 minutes (analyze logs + identify root cause)
- **Fix time:** 30-60 minutes (implement + test)
- **Total:** ~2 hours from logs to verified fix

---

**Ready? Go to [DIAGNOSTIC GUIDE](./SECTION_GAP_DIAGNOSTIC_GUIDE.md) for detailed instructions!**






