# LAME MP3 Encoder Library - Platform-Specific Implementations

This document describes the differences between the two LAME MP3 encoder implementations in this project and explains why they exist.

## Overview

We maintain two separate LAME library implementations:
- `native/lame_ios/` - Used for iOS builds
- `native/lame_android/` - Used for Android builds

The reason for this separation is the different approaches required for cross-platform compilation and the limitations of each platform's build system.

## Build System Integration

### iOS Implementation (`native/lame_ios/`)
- Uses `lame_prefix.h` as a precompiled header
- Configured in the Xcode project file (`ios/Runner.xcodeproj/project.pbxproj`) with:
  ```
  GCC_PREFIX_HEADER = "$(SRCROOT)/../native/lame_prefix.h";
  ```
- The prefix header automatically includes all necessary standard library headers for all LAME source files
- No modifications to original LAME source files required

### Android Implementation (`native/lame_android/`)
- Direct modifications to source files
- Explicit `#include` statements added to each C file that needs them
- Custom configuration and stub implementations for missing functionality
- No prefix header system available in Android NDK build

## Key Differences

### 1. Configuration Files

#### `config.h` Differences
**`native/lame_ios/config.h`** (64 lines):
- Enables NASM assembly optimizations on x86: `#define HAVE_NASM 1`
- Basic iOS/macOS compatibility definitions

**`native/lame_android/config.h`** (74 lines):
- **Disables** all assembly optimizations:
  ```c
  #undef HAVE_NASM
  #undef MMX_choose_table
  #define HAVE_NASM 0
  #undef HAVE_XMMINTRIN_H
  #undef HAVE_IMMINTRIN_H
  ```
- Additional Android-specific compatibility settings
- Comments out `bcopy` macro definition

### 2. Assembly Optimization Handling

#### NASM Stub Implementation
**`native/lame_android/nasm_stubs.c`** (35 lines) - **UNIQUE TO ANDROID**:
```c
/* Provides fallback implementations for x86 assembly functions */
void fht_3DN(FLOAT *fz, int n) { /* stub */ }
void fht_SSE(FLOAT *fz, int n) { /* stub */ }
int has_MMX_nasm(void) { return 0; }
int has_3DNow_nasm(void) { return 0; }
int has_SSE_nasm(void) { return 0; }
int has_SSE2_nasm(void) { return 0; }
void choose_table_MMX(const unsigned int *ix, const unsigned char *end_pos, int *s) { /* stub */ }
```

This file ensures that any references to x86 assembly-optimized functions have safe fallback implementations that return "feature not available."

### 3. Source File Modifications

#### Explicit Header Includes
Many C files in `lame_android` have explicit includes added at the top:
```c
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
```

**Modified files include:**
- `encoder.c` (+4 lines)
- `bitstream.c` (+2 lines) 
- `id3tag.c` (+6 lines, also includes `#undef memcpy`)
- `quantize_pvt.c`
- `vbrquantize.c`
- `util.c`
- `lame.c`
- `takehiro.c`
- `VbrTag.c`
- `quantize.c`
- And others...

#### Special Case: `id3tag.c`
The Android version includes a special handling for the `memcpy`/`bcopy` compatibility:
```c
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#undef memcpy  // Prevents macro conflicts
```

### 4. Platform-Specific Optimizations

#### iOS (`native/lame_ios/`)
- Retains all x86 assembly optimizations when available
- Uses prefix header for clean, non-intrusive builds
- Leverages Xcode's build system capabilities

#### Android (`native/lame_android/`)
- Disables all assembly optimizations for broader ARM compatibility
- Uses generic C implementations for all operations
- Prioritizes stability and compatibility over performance

## Maintenance Strategy

### When to Modify Each Version

#### iOS Version (`native/lame_ios/`)
- Only modify for iOS-specific bugs or optimizations
- Keep changes minimal to maintain compatibility with prefix header approach
- Test changes don't conflict with `lame_prefix.h`

#### Android Version (`native/lame_android/`)
- Modify for Android-specific issues
- Add explicit includes when adding new source files
- Ensure all assembly references have fallback implementations
- Test compilation without prefix headers

### Synchronization Guidelines

1. **Core Algorithm Updates**: Apply to both versions, but respect platform-specific modifications
2. **Bug Fixes**: Evaluate if the fix is platform-specific or universal
3. **New Features**: Implement in both, adapting for each platform's constraints
4. **Assembly Code**: Only add to iOS version, provide stubs in Android version

## Technical Rationale

### Why Two Separate Implementations?

1. **Build System Limitations**:
   - iOS/Xcode supports prefix headers elegantly
   - Android NDK doesn't have equivalent functionality

2. **Performance vs. Compatibility Trade-offs**:
   - iOS can leverage x86 optimizations when available
   - Android prioritizes ARM compatibility and stability

3. **Maintenance Overhead**:
   - Prefix header approach keeps iOS sources clean
   - Direct modification approach is more explicit for Android

4. **Cross-Platform Constraints**:
   - Assembly code is platform and architecture specific
   - Android targets diverse ARM architectures where assembly optimizations may not be available or beneficial

This dual-implementation strategy ensures optimal performance and compatibility for each platform while maintaining code clarity and build system integration. 