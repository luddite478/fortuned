# Enhanced Playback Logging

**Date:** November 16, 2025  
**Status:** ✅ Complete and Ready for Use

## Overview

The Enhanced Playback Logging feature provides comprehensive, human-readable debug output for the sequencer playback system. This tool is invaluable for diagnosing discrepancies between what you see in the UI and what you hear in the audio output.

## Purpose

When debugging playback issues, it's often difficult to understand exactly what's happening inside the native playback engine. This feature logs detailed state information at critical moments:

- **On Playback Start**: Shows complete initial state
- **On Playback Stop**: Shows final state before stopping
- **On Every Step**: Shows state changes as playback progresses

## How to Enable

1. Open the app and navigate to the Sequencer screen
2. Tap the settings icon (⚙️) in the top-right corner
3. Scroll to the "Developer Settings" section
4. Toggle "Enhanced Playback Logging" ON
5. Return to the sequencer and start playback
6. Check your console/terminal for detailed logs

## What Gets Logged

Each log entry includes:

### 📊 Playback State
- **Is Playing**: Current play/pause state
- **Mode**: Song mode (linear) or Loop mode (infinite repeat)
- **BPM**: Current tempo
- **Current Step**: Global step position in the table
- **Current Section**: Which section is playing (e.g., "2 / 3" means section 2 out of 4 total)
- **Section Loop**: Current loop iteration and total (e.g., "2/4" means 2nd loop out of 4)
- **Region**: Playback region bounds [start, end)

### 🎹 SunVox Engine State
- **Current Line**: Absolute timeline position in SunVox
- **Pattern Loop**: Loop counter from SunVox's internal state
- **Pattern X Pos**: X position of the pattern on the timeline

### 📑 Current Section Details
- **Start Step**: First step of the current section
- **Step Count**: Number of steps in the section
- **Total Loops**: How many times this section will loop

### 🎼 Table Contents
A visual grid showing which cells contain samples:
```
   Step   0:  --  --  [2]  --  --  [5]  --  --  ...  👉 CURRENT
   Step   1:  --  --  --  [3]  --  --  --  --  ...
   Step   2: [1]  --  --  --  [4]  --  --  --  ...
```
- `[N]` = Sample slot N is placed at this cell
- `--` = Empty cell
- `👉 CURRENT` = Current playback position

### 📚 All Sections Overview
A summary of all sections in the project:
```
    Section 0: Steps [0-15] (16 steps), Loops: 4
 👉 Section 1: Steps [16-31] (16 steps), Loops: 2  (currently playing)
    Section 2: Steps [32-47] (16 steps), Loops: 1
```

## Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐛 [ENHANCED PLAYBACK LOG] PLAYBACK STARTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 PLAYBACK STATE:
   Is Playing:       YES ▶️
   Mode:             SONG 🎵
   BPM:              120
   Current Step:     0
   Current Section:  0 / 1
   Section Loop:     0 / 3 (display: 1/4)
   Region:           [0, 16)

🎹 SUNVOX ENGINE STATE:
   Current Line:     0
   Pattern Loop:     0
   Pattern X Pos:    0

📑 CURRENT SECTION [0] DETAILS:
   Start Step:       0
   Step Count:       16
   Total Loops:      4

🎼 TABLE CONTENTS (Section 0, Steps 0-15):
   Step   0:  --  --  [0]  --  --  --  --  --  --  --  --  --  --  --  --  --  👉 CURRENT
   Step   4:  --  --  [1]  --  --  --  --  --  --  --  --  --  --  --  --  -- 
   Step   8:  --  --  [2]  --  --  --  --  --  --  --  --  --  --  --  --  -- 
   Step  12:  --  --  [0]  --  --  --  --  --  --  --  --  --  --  --  --  -- 

📚 ALL SECTIONS OVERVIEW:
 👉 Section 0: Steps [0-15] (16 steps), Loops: 4
    Section 1: Steps [16-31] (16 steps), Loops: 2
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Use Cases

### Debugging Playback Issues
**Symptom**: "I hear a note playing but I don't see it in the UI"
**Solution**: Enable enhanced logging and check:
- Current Step vs. SunVox Current Line (should match)
- Table Contents grid (shows which cells actually have samples)
- Section Loop counter (might be in a different loop than UI shows)

### Debugging Loop Counter Issues
**Symptom**: "Loop counter shows wrong value"
**Solution**: Compare:
- Section Loop (our state) vs. Pattern Loop (SunVox's state)
- These should match in song mode, but differ in loop mode

### Debugging Section Transitions
**Symptom**: "Sections don't transition correctly"
**Solution**: Watch the logs during transition:
- Current Section changes
- Current Step jumps to new section's start
- SunVox Current Line should follow

### Debugging Mode Switches
**Symptom**: "Switching between song/loop mode causes issues"
**Solution**: Enable logging before switching and watch:
- Mode changes
- Section Loop counter behavior (freezes in loop mode, updates in song mode)
- Pattern Loop counter synchronization

## Performance Considerations

⚠️ **Important**: Enhanced logging generates a LOT of output:
- Logs on every step change (potentially 120 times per minute at 120 BPM)
- Each log is ~50+ lines of output
- **Only enable when actively debugging**

The logging has minimal performance impact on audio because:
- All logging happens in the polling thread, not the audio thread
- Logging only occurs when state changes (not on every poll)
- The audio callback is never blocked by logging

## Implementation Details

### Files Modified

#### Flutter Side
- `lib/screens/sequencer_settings_screen.dart`: UI toggle
- `lib/state/sequencer/playback.dart`: State management
- `lib/ffi/playback_bindings.dart`: FFI bindings

#### Native Side
- `native/playback.h`: Function declaration
- `native/playback_sunvox.mm`: Implementation
  - `g_enhanced_playback_logging`: Global flag
  - `playback_set_enhanced_logging()`: Enable/disable function
  - `log_enhanced_playback_state()`: Comprehensive logging function
  - Hooks in `playback_start()`, `playback_stop()`, and `update_current_step_from_sunvox()`

### Architecture

```
┌─────────────────┐
│   UI Toggle     │ (Settings Screen)
└────────┬────────┘
         │ setEnhancedPlaybackLogging(true)
         ▼
┌─────────────────┐
│  PlaybackState  │ (Flutter State Management)
└────────┬────────┘
         │ FFI Call
         ▼
┌─────────────────┐
│  Native Code    │ (playback_sunvox.mm)
│                 │
│  g_enhanced_    │ ◄─── Set by playback_set_enhanced_logging()
│  playback_      │
│  logging = 1    │
└─────────────────┘
         │
         │ On playback events:
         ├─► playback_start() ──► log_enhanced_playback_state("PLAYBACK STARTED")
         ├─► playback_stop()  ──► log_enhanced_playback_state("PLAYBACK STOPPING")
         └─► Step changes     ──► log_enhanced_playback_state("STEP UPDATE")
```

## Future Enhancements

Possible improvements for the future:
- [ ] Log to file instead of console for easier analysis
- [ ] Add filtering options (only log on section changes, not every step)
- [ ] Include sample names instead of just slot numbers
- [ ] Add timing information (timestamps, delta between steps)
- [ ] Show audio buffer state and latency
- [ ] Visualize playback in a separate debug window

## Troubleshooting

**Q: I enabled logging but don't see any output**
- Make sure you're looking at the correct console/terminal
- iOS: Use Xcode's console
- Android: Use `adb logcat`
- Verify the toggle is actually ON in settings

**Q: Logs are overwhelming the console**
- This is expected! Enhanced logging is very verbose
- Consider using terminal filtering: `adb logcat | grep "ENHANCED PLAYBACK"`
- Only enable when you need to diagnose a specific issue

**Q: Logs show different values than UI**
- This is the point! The logs show the ground truth from native code
- If they differ from UI, the bug is likely in the UI update logic or state sync

---

**Created by:** Roman Smirnov + AI Assistant  
**Date:** November 16, 2025  
**Status:** ✅ Production Ready

# Log Level System

This document describes the log level filtering system implemented in the Fortuned app to reduce log spam and improve debugging experience.

## Overview

The app now has a configurable log level system that works on both Flutter (Dart) and Native (C++/Objective-C) sides. You can control the verbosity of logs via the `.env` file.

## Configuration

### Environment Variable

Add `LOG_LEVEL` to your `.env` file:

```env
# Log Levels: none, error, warning, info, debug
LOG_LEVEL=info
```

### Available Log Levels

| Level   | Value | Description                                          |
|---------|-------|------------------------------------------------------|
| `none`    | 0     | No logs at all                                       |
| `error`   | 1     | Only critical errors                                 |
| `warning` | 2     | Errors and warnings                                  |
| `info`    | 3     | Errors, warnings, and important info (recommended)   |
| `debug`   | 4     | All logs including verbose debug info (development)  |

### Recommended Settings

- **Development**: `LOG_LEVEL=debug` or `LOG_LEVEL=info`
- **Staging**: `LOG_LEVEL=info` (default in `.stage.env`)
- **Production**: `LOG_LEVEL=warning` or `LOG_LEVEL=error` (set in `.prod.env`)

## Usage

### Flutter/Dart Code

Use the `Log` utility class from `lib/utils/log.dart`:

```dart
import 'package:fortuned/utils/log.dart';

// Debug logs (only shown at debug level)
Log.d('Detailed debug information', 'TAG');

// Info logs (shown at info and debug levels)
Log.i('Important information', 'TAG');

// Warning logs (shown at warning, info, and debug levels)
Log.w('Something might be wrong', 'TAG');

// Error logs (always shown except at none level)
Log.e('Critical error occurred', 'TAG', error);

// Success logs (shown at info level)
Log.s('Operation completed successfully', 'TAG');
```

The tag parameter is optional but recommended for filtering logs by component.

### Native C++/Objective-C Code

Use the macros from `native/log.h`:

```cpp
#include "log.h"

// Define your log tag
#undef LOG_TAG
#define LOG_TAG "MY_MODULE"

// Debug logs (only shown at debug level)
prnt_debug("🔍 Detailed debug info: %d", value);

// Info logs (shown at info and debug levels)
prnt_info("ℹ️ Important info: %s", message);

// Warning logs (shown at warning, info, and debug levels)
prnt_warn("Something might be wrong: %d", code);

// Error logs (always shown except at none level)
prnt_err("❌ Critical error: %s", error);

// Legacy: prnt() maps to prnt_info()
prnt("This is an info log");
```

### Compile-Time Configuration (Native)

For native code, you can also set the log level at compile time by defining `NATIVE_LOG_LEVEL`:

```cmake
# In CMakeLists.txt
add_definitions(-DNATIVE_LOG_LEVEL=3)  # INFO level
```

Default is `3` (INFO) if not specified.

## Migration Guide

### Converting Existing Logs

**Before:**
```dart
debugPrint('🎵 [TABLE_STATE] Initializing table');
debugPrint('❌ [TABLE_STATE] Failed to load: $e');
```

**After:**
```dart
Log.d('Initializing table', 'TABLE_STATE');
Log.e('Failed to load', 'TABLE_STATE', e);
```

**Native Before:**
```cpp
prnt("🎵 [TABLE] Set cell [%d, %d]", row, col);
prnt_err("❌ [TABLE] Invalid cell: %d", cell);
```

**Native After:**
```cpp
prnt_debug("🎵 [TABLE] Set cell [%d, %d]", row, col);
prnt_err("❌ [TABLE] Invalid cell: %d", cell);
```

## Log Level Guidelines

### When to Use Each Level

- **Debug (`prnt_debug` / `Log.d`)**: 
  - Verbose operational logs
  - State changes during normal operation
  - Function entry/exit traces
  - Data dumps

- **Info (`prnt_info` / `Log.i` / `Log.s`)**:
  - Initialization completion
  - Configuration changes
  - Major state transitions
  - Connection status

- **Warning (`prnt_warn` / `Log.w`)**:
  - Recoverable errors
  - Deprecated API usage
  - Performance issues
  - Unexpected but handled conditions

- **Error (`prnt_err` / `Log.e`)**:
  - Unrecoverable errors
  - Failed operations
  - Invalid parameters
  - System failures

## Examples

### Reduced Log Output

With `LOG_LEVEL=info`, verbose logs are hidden:

**Before (all logs shown):**
```
TABLE: 🎵 [TABLE] Set cell [0, 0]: slot=0
TABLE: 🎵 [TABLE] Set cell [0, 1]: slot=1
TABLE: 🎵 [TABLE] Set cell [0, 2]: slot=2
SUNVOX: 📝 [SUNVOX] Set pattern event [section=0, line=0, col=0]
SUNVOX: 📝 [SUNVOX] Set pattern event [section=0, line=1, col=0]
...
```

**After (only info+ shown):**
```
TABLE: ✅ [TABLE] Table initialized successfully
SUNVOX: ✅ [SUNVOX] Created pattern 0 for section 0
PLAYBACK: ✅ [PLAYBACK] Playback system initialized
```

### Debug Mode

With `LOG_LEVEL=debug`, all logs are shown including verbose operational details.

## Benefits

1. **Reduced Noise**: Production builds can hide verbose logs
2. **Better Performance**: Fewer logs = less overhead
3. **Easier Debugging**: Focus on relevant logs by adjusting level
4. **Consistent Filtering**: Same system works across Flutter and Native code
5. **Easy Configuration**: Change one variable to control all logs

## Implementation Details

- **Flutter**: Uses `flutter_dotenv` to read `LOG_LEVEL` from `.env`
- **Native**: Uses preprocessor macros with compile-time level checking
- **Backward Compatible**: Old `prnt()` calls still work (mapped to info level)
- **Zero Overhead**: Disabled logs are compile-time removed in native code

