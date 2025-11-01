# SunVox Library Build Instructions

## Overview

This document explains how to build the SunVox library for iOS (both simulator and physical devices).

## The Problem

iOS requires different library builds for:
- **Simulator**: x86_64 (Intel Macs) + arm64 (Apple Silicon Macs) with simulator platform
- **Physical Device**: arm64 with device platform

You cannot create a single `.a` file containing both because `lipo` treats arm64 simulator and arm64 device as the same architecture even though they target different platforms.

## The Solution

We use **automatic library selection** that switches between simulator and device libraries based on the build target.

### Build Scripts

#### 1. Build for Simulator Only
```bash
cd sunvox_lib/make
./MAKE_IOS
```
Creates: `sunvox.a` (universal simulator: x86_64 + arm64 simulator)

#### 2. Build for Device Only
```bash
cd sunvox_lib/make
./MAKE_IOS_DEVICE
```
Creates: `sunvox_arm64_device.a` (arm64 device)

#### 3. Build for Both (Recommended)
```bash
cd sunvox_lib/make
./MAKE_IOS_UNIVERSAL
```
Creates all libraries:
- `sunvox_x86_64_simulator.a` - Intel Mac simulator
- `sunvox_arm64_simulator.a` - Apple Silicon simulator
- `sunvox_arm64_device.a` - Physical iPhone/iPad
- `sunvox.a` - Universal simulator (x86_64 + arm64)

### Automatic Library Selection

The `run-ios.sh` script automatically selects the correct library before building:

```bash
# For simulator
./run-ios.sh stage simulator "iPhone 15"

# For physical device
./run-ios.sh stage physical
```

The selection happens via `select_library.sh` which:
- Copies `sunvox.a` → `libsunvox.a` for simulator builds
- Copies `sunvox_arm64_device.a` → `libsunvox.a` for device builds

### Manual Library Selection

If you need to manually switch libraries:

```bash
cd sunvox_lib/ios

# Select simulator library
./select_library.sh simulator

# Select device library
./select_library.sh device
```

## Files

- `MAKE_IOS` - Build simulator library
- `MAKE_IOS_DEVICE` - Build device library
- `MAKE_IOS_UNIVERSAL` - Build all libraries
- `select_library.sh` - Switch between libraries

## Verification

Check which library is currently selected:
```bash
cd sunvox_lib/ios
ls -lh libsunvox.a
```

- **7.9M** = Simulator library (universal)
- **3.8M** = Device library (arm64 only)

## Notes

- Always run `./MAKE_IOS_UNIVERSAL` after pulling changes to ensure you have both libraries
- The library is automatically selected during the build process
- No manual intervention needed when using `run-ios.sh`

