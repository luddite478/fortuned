# iOS Build Fix Documentation

## Problem Summary

The iOS app was experiencing crashes on physical devices, resulting in a gray screen on the Projects screen. Investigation revealed multiple interrelated issues with the build configuration and SunVox initialization.

---

## Root Cause Analysis

### Issue 1: Architecture Mismatch (Physical Device Build Failure)

**Problem:**
- Building for physical iOS devices failed with error:
  ```
  Building for 'iOS', but linking in object file (...) built for 'iOS-simulator'
  ```

**Root Cause:**
- The `libsunvox.a` library contained arm64 slices built for iOS Simulator (platform 7) instead of iOS Device (platform 2)
- Both simulator and physical devices use arm64 architecture, but they are **incompatible** due to different build targets
- The original `MAKE_IOS` script only built for simulator

**Technical Details:**
- iOS uses the `-target` compiler flag with different suffixes:
  - Simulator: `arm64-apple-ios11.0-simulator`
  - Device: `arm64-apple-ios11.0` (no suffix)
- This is controlled by `IOS_TARGET_SUFFIX` in the makefile
- `lipo -info` shows architecture but `platform` command reveals the actual target

### Issue 2: SunVox Initialization Crash (Config File Permissions)

**Problem:**
- App crashed on startup (before UI could render), showing gray screen
- Crash occurred even when native subsystem initialization was disabled in Projects screen

**Root Cause:**
- `PlaybackState` is initialized at app startup via Provider in `main.dart` (line 57)
- `PlaybackState` constructor calls `_initializePlayback()` → `playbackInit()` → `sunvox_wrapper_init()`
- `sunvox_wrapper_init()` tried to create config file in `NSDocumentDirectory`
- File creation failed silently (error ignored with `error:nil`)
- SunVox's `sv_init()` then crashed when trying to access the missing config file

**Crash Sequence:**
1. App launches → `main.dart` initializes Providers
2. `PlaybackState` Provider created → constructor runs
3. `playbackInit()` called → `sunvox_wrapper_init()` runs
4. Config file creation fails in Documents directory
5. `sv_init()` crashes accessing missing config → **Gray screen**

### Issue 3: **CRITICAL** - NULL Termination Bug in g_app_config Array

> **🔴 CRITICAL BUG**: This issue caused crashes on physical iOS devices even after the config file fix.
> 
> **See**: [CRITICAL_FIX_NULL_TERMINATION.md](../native/sunvox_lib/CRITICAL_FIX_NULL_TERMINATION.md) for complete investigation.

**Problem:**
- App crashed during `sconfig_load()` when iterating over config file paths
- Crash only occurred on **physical iOS devices**, not on simulator
- Array bounds violation causing access to garbage memory

**Root Cause:**
```cpp
// ❌ INCORRECT - Not NULL-terminated
const char* g_app_config[] = { 
    "1:/sunvox_dll_config.ini", 
    "2:/sunvox_dll_config.ini", 
    "0"  // This is a string "0", NOT NULL!
};
```

The loop expects a NULL-terminated array but `"0"` is a non-NULL pointer. Loop continued reading garbage memory until crash at index 8.

**Why Simulator Worked:**
- Intel Mac simulator had different memory layout
- Garbage memory at index 8 happened to be `0x0000000000000000` (NULL)
- Worked by **pure luck**, not by design

**Fix:**
```cpp
// ✅ CORRECT - Properly NULL-terminated
const char* g_app_config[] = { 
    "1:/sunvox_dll_config.ini", 
    "2:/sunvox_dll_config.ini", 
    NULL  // Proper NULL terminator
};
```

**File**: `app/native/sunvox_lib/sunvox_lib/main/sunvox_lib.cpp` (line 46)

**Impact**: This fix is **required for all platforms** - simulator worked by accident, device crashed reliably.

---

## Solution Overview

### 1. Build System Changes

Created a dual-build system to support both iOS Simulator and Physical Devices:

#### Files Modified/Created:

**Created: `/app/native/sunvox_lib/sunvox_lib/make/MAKE_IOS_DEVICE`**
- Builds SunVox library specifically for physical iOS devices
- Sets `IOS_TARGET_SUFFIX=""` to build for device platform
- Uses `iPhoneOS.sdk` instead of `iPhoneSimulator.sdk`
- Outputs: `sunvox_arm64_device.a`

**Modified: `/app/native/sunvox_lib/sunvox_lib/make/MAKE_IOS`**
- Already existed, builds for iOS Simulator
- Creates universal simulator library (x86_64 + arm64 simulator)
- Outputs: `sunvox.a` (universal simulator library)

**Created: `/app/native/sunvox_lib/sunvox_lib/make/MAKE_IOS_UNIVERSAL`**
- Orchestrates building for both simulator and device
- Runs `MAKE_IOS` then `MAKE_IOS_DEVICE`
- Produces all necessary library variants

**Created: `/app/native/sunvox_lib/sunvox_lib/ios/select_library.sh`**
- Helper script to select correct library based on build target
- Accepts argument: `simulator` or `device`
- Copies appropriate library to `libsunvox.a` which Xcode links against

**Modified: `/app/run-ios.sh`**
- Added automatic library selection before Flutter build
- Detects build target (simulator vs device) from script arguments
- Calls `select_library.sh` to ensure correct `libsunvox.a` is in place

### 2. SunVox Initialization Fix

**Modified: `/app/native/sunvox_wrapper.mm`**

Changed config file creation strategy:

**Before:**
```objective-c
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
NSString *docsDir = [paths firstObject];
NSString *configPath = [docsDir stringByAppendingPathComponent:@"sunvox_dll_config.ini"];

if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
    [@"" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; // ❌ Errors ignored!
    prnt("🔧 [SUNVOX] Created empty config file at: %s", [configPath UTF8String]);
}
```

**After:**
```objective-c
// Use NSTemporaryDirectory() - always writable, no permissions needed
NSString *tempDir = NSTemporaryDirectory();
NSString *configPath = [tempDir stringByAppendingPathComponent:@"sunvox_dll_config.ini"];

BOOL configExists = [[NSFileManager defaultManager] fileExistsAtPath:configPath];
if (!configExists) {
    NSError *error = nil;
    BOOL success = [@"" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (success) {
        prnt("✅ [SUNVOX] Created empty config file at: %s", [configPath UTF8String]);
    } else {
        prnt_err("❌ [SUNVOX] Failed to create config file at %s: %s", 
                 [configPath UTF8String], 
                 [[error localizedDescription] UTF8String]);
        prnt("⚠️ [SUNVOX] Will try sv_init() anyway...");
    }
} else {
    prnt("✓ [SUNVOX] Config file already exists at: %s", [configPath UTF8String]);
}

prnt("🔧 [SUNVOX] Calling sv_init() with flags: 0x%X", flags);
```

**Key Improvements:**
1. **Use `NSTemporaryDirectory()`** instead of `NSDocumentDirectory`
   - Always writable without special permissions
   - Appropriate for temporary/cache files
2. **Proper error handling** with `NSError*` capture
3. **Detailed logging** showing exact failure reasons
4. **Non-fatal** - continues even if config creation fails

---

## Build Instructions

### Prerequisites

Ensure you have the SunVox libraries built for both targets:

```bash
cd app/native/sunvox_lib/sunvox_lib/make
./MAKE_IOS_UNIVERSAL
```

This creates:
- `sunvox.a` - Universal simulator library (x86_64 + arm64-simulator)
- `sunvox_arm64_device.a` - Physical device library (arm64-device)

### Building for Simulator

```bash
cd app
./run-ios.sh stage simulator
```

The script automatically:
1. Detects `simulator` argument
2. Calls `select_library.sh simulator`
3. Copies `sunvox.a` → `libsunvox.a`
4. Runs Flutter build for simulator

### Building for Physical Device

```bash
cd app
./run-ios.sh stage physical
```

The script automatically:
1. Detects `physical` argument
2. Calls `select_library.sh device`
3. Copies `sunvox_arm64_device.a` → `libsunvox.a`
4. Runs Flutter build for device

### Manual Library Selection (if needed)

If you need to manually switch libraries:

```bash
cd app/native/sunvox_lib/sunvox_lib/ios

# For simulator
./select_library.sh simulator

# For physical device
./select_library.sh device
```

Then verify:
```bash
lipo -info libsunvox.a
```

Expected output:
- **Simulator**: `Architectures in the fat file: libsunvox.a are: x86_64 arm64`
- **Device**: `Non-fat file: libsunvox.a is architecture: arm64`

---

## Technical Details

### Why Two Separate Libraries?

Both iOS Simulator and physical devices can use arm64 architecture (on Apple Silicon Macs), but they are **binary incompatible**:

- **Simulator arm64**: Built with `-target arm64-apple-ios11.0-simulator`
  - Platform ID: 7 (iOS Simulator)
  - Runs in macOS process space
  - Uses macOS system libraries

- **Device arm64**: Built with `-target arm64-apple-ios11.0`
  - Platform ID: 2 (iOS Device)
  - Runs directly on iPhone/iPad hardware
  - Uses iOS system libraries

You can verify platform with:
```bash
platform -i libsunvox.a
```

### Makefile Variables

The key variable controlling the build target:

**File**: `app/native/sunvox_lib/lib_sundog/sundog_makefile.inc`

```makefile
IOS_TARGET_SUFFIX ?= -simulator  # Line 60

# Used in compiler flags:
-target $(TARGET_ARCH)-apple-ios11.0$(IOS_TARGET_SUFFIX)  # Line 206
```

- `MAKE_IOS`: Uses default `-simulator` suffix
- `MAKE_IOS_DEVICE`: Overrides with `IOS_TARGET_SUFFIX=""`

### Library Selection in Xcode

The Xcode project references:
```
path = ../native/sunvox_lib/sunvox_lib/ios/libsunvox.a
```

This single file (`libsunvox.a`) is swapped by the `select_library.sh` script before each build.

**Alternative Considered**: XCFramework
- Could package both variants into a single `.xcframework`
- More "modern" approach
- Decided against for simplicity (single script vs framework generation)

---

## Debugging

### Check Current Library

```bash
cd app/native/sunvox_lib/sunvox_lib/ios

# Architecture
lipo -info libsunvox.a

# Platform (macOS only)
platform -i libsunvox.a
```

### View SunVox Initialization Logs

Run app with Xcode console open and filter for `SUNVOX`:

Expected logs on successful init:
```
🎵 [SUNVOX] Initializing SunVox wrapper (NEW LIBRARY - Oct 14 2025)
✅ [SUNVOX] Created empty config file at: /var/.../tmp/sunvox_dll_config.ini
🔧 [SUNVOX] Calling sv_init() with flags: 0x...
✅ [SUNVOX] sv_init succeeded in OFFLINE mode (USER_AUDIO_CALLBACK)
✅ [SUNVOX] sv_open_slot succeeded
✅ [SUNVOX] Supertracks mode enabled (required for seamless looping)
```

### Common Errors

**Error: "Building for 'iOS', but linking in object file built for 'iOS-simulator'"**
- Solution: Run `./run-ios.sh stage physical` or manually select device library

**Error: "Undefined symbol: _sv_..."**
- Solution: Run `./run-ios.sh stage simulator` or manually select simulator library

**Gray screen on app launch**
- Check Xcode console for SunVox errors
- Look for file permission errors
- Verify config file creation succeeded

---

## Current Status

### ✅ Completed
- [x] Created dual-build system (simulator + device)
- [x] Implemented automatic library selection in `run-ios.sh`
- [x] Fixed SunVox config file creation to use temp directory
- [x] Added proper error handling and logging
- [x] **CRITICAL**: Fixed NULL termination bug in g_app_config array
- [x] Added symbol export attributes for recording functions
- [x] Verified physical device build works without crashes
- [x] Confirmed SunVox initializes successfully on device
- [x] Documented build process

### 🎉 Verified Working
- ✅ App launches successfully on physical iOS devices
- ✅ SunVox initializes without crashes
- ✅ All native subsystems (Table, Playback, SampleBank) initialize properly
- ✅ No gray screen issues

### 📋 Optional Cleanup
1. Remove extensive debug logging added during investigation
2. Re-enable auto-initialization in state providers if desired
3. Remove manual debug test button from Projects screen

---

## Files Changed Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `native/sunvox_lib/sunvox_lib/make/MAKE_IOS_DEVICE` | **Created** | Builds SunVox for physical devices |
| `native/sunvox_lib/sunvox_lib/make/MAKE_IOS_UNIVERSAL` | **Created** | Orchestrates both builds |
| `native/sunvox_lib/sunvox_lib/ios/select_library.sh` | **Created** | Helper to swap libraries |
| `run-ios.sh` | **Modified** | Added auto library selection |
| `native/sunvox_wrapper.mm` | **Modified** | Fixed config file creation |
| `lib/screens/projects_screen.dart` | **Tested** | Confirmed issue not in UI layer |

---

## Related Documentation

- **[CRITICAL_FIX_NULL_TERMINATION.md](../native/sunvox_lib/CRITICAL_FIX_NULL_TERMINATION.md)** - ⚠️ Critical NULL termination bug investigation and fix
- [README_BUILD.md](../native/sunvox_lib/README_BUILD.md) - SunVox library build instructions
- [MODIFICATIONS.md](../native/sunvox_lib/MODIFICATIONS.md) - SunVox library modifications

---

**Last Updated**: October 16, 2025  
**Status**: ✅ All issues resolved - Working on physical devices

