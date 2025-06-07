# Niyya - Flutter FFI + Miniaudio Integration Project

A comprehensive Flutter project demonstrating FFI (Foreign Function Interface) integration with native C code on iOS, specifically designed for audio applications. This project includes file picker functionality and a complete FFI chain setup for future miniaudio integration.

## 🎯 **Project Goal**
Create a mini-DAW (Digital Audio Workstation) with:
- Low latency audio playback
- Multiple simultaneous sound playback
- Cross-platform support (iOS focus)
- Native audio performance through FFI

## 📋 **Current Status**

✅ **WORKING:** Complete FFI chain (Flutter → Dart → C → Return)  
✅ **WORKING:** File picker for audio files  
✅ **WORKING:** iOS build and deployment  
🔄 **IN PROGRESS:** Real miniaudio integration (currently using test implementation)  

## 🔄 **Complete Step-by-Step Setup Guide**

### 1. **Initial Flutter Setup**
```bash
flutter create your_project_name
cd your_project_name
```

### 2. **Add Dependencies**
Update `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  path: ^1.9.0
  file_picker: ^8.0.7

dev_dependencies:
  flutter_test:
    sdk: flutter
  ffigen: ^13.0.0
  flutter_lints: ^3.0.0
```

### 3. **Create Native Code Structure**
```bash
mkdir native
# Add your .h and .c files in native/
```

### 4. **FFI Configuration**
Create `ffigen.yaml`:
```yaml
name: 'MiniaudioBindings'
description: 'Bindings for miniaudio library'
output: 'lib/miniaudio_bindings_generated.dart'
headers:
  entry-points:
    - 'native/miniaudio_wrapper.h'
```

### 5. **Generate FFI Bindings**
```bash
dart run ffigen
```

### 6. **iOS Configuration**
- Update `ios/Podfile` with Flutter CocoaPods setup
- Add files to Xcode project (native/*.c and native/*.h)  
- Configure Build Settings: Strip Style → "Non-Global Symbols"
- Add permissions to `ios/Runner/Info.plist`

### 7. **Create Dart Wrapper**
- Create `lib/miniaudio_library.dart` with singleton pattern
- Handle string conversion and memory management
- Add proper error handling

### 8. **Update UI**
- Replace counter logic in `lib/main.dart`
- Add file picker integration
- Add audio control buttons

### 9. **Testing Setup & Simulator Configuration**

#### **Basic Setup**
```bash
# Install pods
cd ios && pod install && cd ..

# Run on simulator
flutter run
```

#### **Complete Simulator Testing Guide**

**Step 1: Find Your Simulator Device ID**
```bash
xcrun simctl list devices
```
Look for your running simulator (e.g., "iPhone 15 (E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF) (Booted)")

**Step 2: Add Test Audio Files to Simulator**
```bash
# Replace DEVICE_ID with your actual device ID
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/path/to/your/audio.wav

# Example with our test file:
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/Downloads/Ouch-6.wav
```

**Step 3: Verify File Access**
Files will be accessible in:
- **Files app → On My iPhone → [Your App Name]**
- **Files app → iCloud Drive** (if iCloud is enabled)
- **Documents directory** of your app

**Step 4: Test the Complete FFI Chain**
1. Launch your Flutter app on simulator
2. Tap "Pick Audio File" button
3. Navigate to Files app and select your test audio file
4. Tap "Play" button  
5. **Expected Console Output**:
   ```
   flutter: Attempting to play: /var/mobile/Containers/Data/Application/.../Documents/Ouch-6.wav
   flutter: 🎵 FFI RESULT: 1 (1=success, 0=failure)
   flutter: ✅ DART: Audio command sent successfully via FFI!
   ```

**Step 5: Alternative File Placement**
If file picker doesn't show your files, try placing them directly in app sandbox:
```bash
# Get app sandbox path (run this in your Flutter app debug console)
print(Directory.systemTemp.parent.path);

# Copy file to Documents directory
xcrun simctl spawn E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF cp /path/to/your/audio.wav /var/mobile/Containers/Data/Application/YOUR_APP_ID/Documents/
```

## 📋 **Next Steps for Real Miniaudio Integration**

### Option 1: Fix iOS Compilation Issues
1. Configure miniaudio with iOS-specific backends
2. Properly isolate Foundation framework includes
3. Use conditional compilation for iOS-specific code

### Option 2: Alternative Audio Libraries
Consider other low-latency audio libraries that are iOS-friendly:
- OpenAL (deprecated but stable)
- Custom Core Audio wrapper
- Platform-specific implementations

### Option 3: Miniaudio Backend Selection
Configure miniaudio to use only iOS Core Audio backend:
```c
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_COREAUDIO
```

## Project Overview

This project demonstrates how to:
- Integrate native C code into a Flutter iOS app
- Use FFI to call C functions from Dart
- Set up dynamic linking for iOS using static compilation
- Configure Xcode for native code integration
- Handle file picker integration for audio files
- Manage string conversion between Dart and C
- Solve iOS-specific compilation challenges

## Prerequisites

- Flutter SDK (3.8.1 or higher)
- Xcode 14.0 or higher
- iOS Simulator or physical iOS device
- macOS development environment
- CocoaPods

## FFI Integration Setup

### Step 1: Project Dependencies

Update `pubspec.yaml` to include FFI dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  path: ^1.9.0
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  ffigen: ^13.0.0
  flutter_lints: ^5.0.0
```

Run `flutter pub get` to install dependencies.

### Step 2: Create Native C Code

Create a `native/` directory in your project root and add the following files:

**`native/miniaudio.h`** - Header file with function declarations:
```c
#ifndef MINIAUDIO_H
#define MINIAUDIO_H

#ifdef __cplusplus
extern "C" {
#endif

// Simple counter function to replace the Flutter increment logic
__attribute__((visibility("default"))) __attribute__((used))
int increment_counter(int current_value);

// Initialize function (placeholder for future miniaudio integration)
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_init(void);

// Cleanup function (placeholder for future miniaudio integration)
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // MINIAUDIO_H
```

**`native/miniaudio.c`** - Implementation file:
```c
#include "miniaudio.h"
#include <stdio.h>

// Implementation of the increment counter function
int increment_counter(int current_value) {
    return current_value + 1;
}

// Initialize function (placeholder for future miniaudio integration)
void miniaudio_init(void) {
    printf("Miniaudio initialized\n");
}

// Cleanup function (placeholder for future miniaudio integration)
void miniaudio_cleanup(void) {
    printf("Miniaudio cleaned up\n");
}
```

### Step 3: FFI Bindings Generation

Create `ffigen.yaml` configuration file:
```yaml
name: 'MiniaudioBindings'
output: 'lib/miniaudio_bindings_generated.dart'
headers:
  entry-points:
    - 'native/miniaudio.h'
preamble: |
  // Generated bindings for miniaudio.
  // ignore_for_file: always_specify_types
  // ignore_for_file: camel_case_types
  // ignore_for_file: comment_references
  // ignore_for_file: file_names
  // ignore_for_file: library_private_types_in_public_api
  // ignore_for_file: non_constant_identifier_names
  // ignore_for_file: prefer_single_quotes
  // ignore_for_file: type_literal_in_constant_pattern
  // ignore_for_file: unnecessary_import
comments:
  style: any
  length: full
```

Generate the bindings:
```bash
dart run ffigen --config ffigen.yaml
```

### Step 4: Create Dart Wrapper Library

Create `lib/miniaudio_library.dart`:
```dart
import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'miniaudio_bindings_generated.dart';

class MiniaudioLibrary {
  static MiniaudioLibrary? _instance;
  late final DynamicLibrary _dylib;
  late final MiniaudioBindings _bindings;

  MiniaudioLibrary._() {
    _dylib = _loadLibrary();
    _bindings = MiniaudioBindings(_dylib);
  }

  static MiniaudioLibrary get instance {
    _instance ??= MiniaudioLibrary._();
    return _instance!;
  }

  DynamicLibrary _loadLibrary() {
    try {
      if (Platform.isIOS) {
        // On iOS, the library is statically linked into the app bundle
        return DynamicLibrary.executable();
      } else if (Platform.isAndroid) {
        return DynamicLibrary.open('libminiaudio.so');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libminiaudio.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('miniaudio.dll');
      } else {
        throw UnsupportedError('Platform not supported');
      }
    } catch (e) {
      throw Exception('Failed to load native library: $e. '
          'Make sure the C files are properly added to your iOS project.');
    }
  }

  // Wrapper methods for easier access
  int incrementCounter(int currentValue) {
    return _bindings.increment_counter(currentValue);
  }

  void initialize() {
    _bindings.miniaudio_init();
  }

  void cleanup() {
    _bindings.miniaudio_cleanup();
  }
}
```

### Step 5: Update Flutter App

Update `lib/main.dart` to use the FFI functions:
```dart
import 'package:flutter/material.dart';
import 'miniaudio_library.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter FFI Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter FFI Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  late final MiniaudioLibrary _miniaudioLibrary;

  @override
  void initState() {
    super.initState();
    _miniaudioLibrary = MiniaudioLibrary.instance;
    _miniaudioLibrary.initialize();
  }

  @override
  void dispose() {
    _miniaudioLibrary.cleanup();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      // Now using FFI to call the C function for incrementing
      _counter = _miniaudioLibrary.incrementCounter(_counter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            const Text(
              '(Using FFI C Function)',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

## Xcode Configuration (Critical Step)

### Step 1: Generate Xcode Workspace

If you don't have a `Runner.xcworkspace` file, generate it:
```bash
cd ios && pod install && cd ..
```

### Step 2: Open Xcode Project

Open the workspace (not the .xcodeproj):
```bash
open ios/Runner.xcworkspace
```

### Step 3: Add Native Source Files (Xcode UI Actions)

**Important**: These steps must be done in Xcode's UI:

1. **Add C Files to Project**:
   - In Xcode's Project Navigator (left sidebar), right-click on the "Runner" group
   - Select "Add Files to Runner..."
   - Navigate to your project's `native` folder
   - Select both `miniaudio.h` and `miniaudio.c` files
   - **Make sure "Add to target: Runner" checkbox is checked**
   - Click "Add"

2. **Verify File Addition**:
   - Both files should now appear in the Runner group
   - They should have proper file icons (not red/missing)
   - Files should be visible in the project navigator

### Step 4: Configure Build Settings

1. **Access Build Settings**:
   - Select the "Runner" project (blue icon) in the project navigator
   - Select the "Runner" target (under TARGETS)
   - Click the "Build Settings" tab

2. **Update Strip Style**:
   - In the search bar, type "Strip Style"
   - Find "Strip Style" under "Deployment" section
   - Change from "All Symbols" to "Non-Global Symbols"
   - This prevents iOS from stripping our C function symbols

### Step 5: Test Build in Xcode

1. **Build Project**:
   - Press `⌘+B` or go to Product → Build
   - Ensure there are no compilation errors
   - The C files should compile successfully

## Building and Running

### Build for Simulator
```bash
flutter build ios --simulator
```

### Run on Simulator
First, check available devices:
```bash
flutter devices
```

Then run with the appropriate device ID:
```bash
flutter run -d [DEVICE_ID]
```

### Build for Physical Device
```bash
flutter build ios --release
```

### Deploy to Physical iOS Device

1. **Install ios-deploy** (if not already installed):
```bash
npm install -g ios-deploy
```

2. **List Connected Devices**:
```bash
ios-deploy -c
```
This will show your connected iPhone with its ID (e.g., `00008110-000251422E02601E`)

3. **Deploy the Release Build**:
```bash
ios-deploy --bundle build/ios/iphoneos/Runner.app --id <YOUR_DEVICE_ID>
```
Replace `<YOUR_DEVICE_ID>` with your actual device ID from step 2.

**Note**: Make sure your iPhone is:
- Connected via USB
- Unlocked
- Trusts your development computer
- Has developer mode enabled in Settings → Privacy & Security → Developer Mode

## 🚨 **Problems Encountered & Solutions**

### Major iOS Integration Challenges

#### 1. **Miniaudio + iOS Foundation Framework Conflicts**
**Problem**: When integrating full miniaudio library, iOS Foundation framework conflicts:
```
Parse Issue (Xcode): Could not build module 'Foundation'
Parse Issue (Xcode): Could not build module 'AVFoundation'
```

**Root Cause**: Miniaudio's iOS backend tries to include AVFoundation, creating circular dependencies.

**Solutions Attempted**:
- ✅ Disabling AVFoundation: `#define MA_NO_AVFOUNDATION`
- ✅ Disabling runtime linking: `#define MA_NO_RUNTIME_LINKING`
- ✅ Disabling Core Audio: `#define MA_NO_COREAUDIO`
- ❌ Still failed with Foundation conflicts

**Current Workaround**: Using test implementation to verify FFI chain works perfectly.

#### 2. **Duplicate Symbol Errors**
**Problem**: 1168 duplicate symbols when including miniaudio in multiple files.

**Solution**: 
- Only define `MINIAUDIO_IMPLEMENTATION` in one file (`miniaudio.c`)
- Use forward declarations in wrapper files
- Separate compilation units properly

#### 3. **String Conversion Dart ↔ C**
**Problem**: Converting Dart strings to C char* pointers for file paths.

**Solution**:
```dart
// Convert Dart string to C string
final utf8Bytes = utf8.encode(filePath);
final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
// Copy bytes and add null terminator
// Always free memory in finally block
free(cString.cast());
```

#### 4. **File Picker iOS Permissions**
**Problem**: File picker not working without proper iOS permissions.

**Solution**: Added to `ios/Runner/Info.plist`:
```xml
<key>NSDocumentPickerUsageDescription</key>
<string>This app needs access to files to select audio files for playback.</string>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

#### 5. **Podfile Configuration**
**Problem**: CocoaPods not installing Flutter plugins properly.

**Solution**: Updated `ios/Podfile` with proper Flutter configuration:
```ruby
platform :ios, '12.0'
# ... full Flutter podfile setup
flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
```

### Current Working Architecture

#### **File Structure**:
```
native/
├── miniaudio.h              # Real miniaudio library (3.8MB)
├── miniaudio.c              # Currently: placeholder
├── miniaudio_wrapper.h      # Our FFI interface
└── miniaudio_wrapper.c      # Test implementation (working)

lib/
├── miniaudio_bindings_generated.dart  # Auto-generated FFI bindings
├── miniaudio_library.dart             # Dart wrapper with string conversion
└── main.dart                          # UI with file picker + audio controls
```

#### **FFI Chain (VERIFIED WORKING)**:
```
Flutter UI → File Picker → Dart String → 
UTF8 Conversion → C malloc → Native Function Call → 
Return Value → Free Memory → Dart Bool → UI Update
```

## Troubleshooting

### Common Issues

1. **"Failed to load native library" Error**:
   - Ensure C files are properly added to Xcode project
   - Verify "Add to target: Runner" was checked
   - Check that Strip Style is set to "Non-Global Symbols"

2. **Symbol Not Found Errors**:
   - Verify the C functions have proper visibility attributes
   - Ensure the C files are being compiled (check Xcode build log)
   - Make sure you're using `DynamicLibrary.executable()` for iOS

3. **Build Errors in Xcode**:
   - Clean build folder: Product → Clean Build Folder
   - Ensure both .h and .c files are in the same target
   - Check for any syntax errors in C code

4. **Pod Install Issues**:
   - Delete `Podfile.lock` and `Pods/` directory
   - Run `flutter clean` then `cd ios && pod install`

5. **Miniaudio Compilation Issues**:
   - If you get Foundation/AVFoundation conflicts, use test implementation first
   - Verify FFI chain works before attempting real miniaudio integration
   - Consider iOS-specific miniaudio backend configuration

### Testing FFI Integration

**To verify FFI works**:
1. Run app on iOS simulator
2. Pick an audio file using "Pick Audio File" button
3. Tap "Play" button
4. **Expected log output**:
   ```
   flutter: Attempting to play: /path/to/your/file.wav
   flutter: 🎵 FFI RESULT: 1 (1=success, 0=failure)
   flutter: ✅ DART: Audio command sent successfully via FFI!
   ```

### Verification Steps

1. **Verify FFI Setup**:
   - Check that `lib/miniaudio_bindings_generated.dart` exists
   - Ensure all dependencies are in `pubspec.yaml`
   - Confirm C files are in `native/` directory

2. **Verify Xcode Integration**:
   - C files appear in Runner group
   - Build succeeds without errors
   - Strip Style is correctly configured

3. **Verify File Access**:
   - Audio files placed in simulator accessible locations
   - File picker shows available files
   - File paths are passed correctly to C functions

## Technical Notes

### Why Static Linking on iOS

iOS apps must use static linking for native libraries. The `DynamicLibrary.executable()` approach loads symbols that are already linked into the main executable at compile time.

### FFI Type Mapping

- Dart `int` → C `int`
- Dart `bool` → C `int` (0=false, 1=true)
- String conversion requires manual memory management

### Symbol Visibility

C functions must be declared with proper visibility attributes for iOS:

```c
__attribute__((visibility("default"))) __attribute__((used))
int your_function_name() {
    // implementation
}
```

### Memory Management

Always free allocated memory for string conversions:
```dart
final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
try {
  // Use cString
} finally {
  free(cString.cast());
}
```

### FFI Best Practices
- **Error Handling**: Always wrap FFI calls in try-catch blocks
- **Type Safety**: Use specific types (`Int8` vs generic `Int`)
- **Resource Management**: Use try-finally blocks for cleanup
- **Logging**: Add comprehensive logging for debugging FFI chains

## 🎯 **Key Learnings & Tips**

### What We Learned
1. **FFI Chain Verification**: Always test the complete chain before adding complexity
2. **iOS Symbol Visibility**: Requires special attributes for functions to be accessible
3. **String Conversion**: Manual UTF-8 handling is required between Dart and C
4. **Build Configuration**: Xcode settings (Strip Style) can break FFI symbol linking
5. **Framework Conflicts**: Some libraries (like miniaudio) have iOS-specific challenges
6. **Memory Management**: C memory must be manually managed from Dart side

### Pro Tips
- Start with simple test functions before integrating complex libraries
- Always verify FFI chain works end-to-end before debugging library-specific issues
- Use comprehensive logging at each step of the FFI chain
- Test on both simulator and physical device
- Keep native code in separate compilation units to avoid symbol conflicts

## ⚠️ **Known Issues & Workarounds**

### 1. **Hot Reload with FFI**
- **Issue**: FFI functions may not update with hot reload
- **Workaround**: Use hot restart (`flutter run`) instead of hot reload

### 2. **iOS Simulator vs Physical Device**
- **Issue**: Different behaviors between simulator and device
- **Solution**: Always test on both platforms

### 3. **File Access Permissions**
- **Issue**: File picker may fail without proper iOS permissions
- **Solution**: Add all necessary permissions to Info.plist upfront

### 4. **Xcode Project Changes**
- **Issue**: Adding/removing native files requires Xcode UI actions
- **Solution**: Always use Xcode's "Add Files to Runner..." option

## 🚀 **Performance Considerations**

For the intended DAW (Digital Audio Workstation) use case:
- **FFI Overhead**: FFI calls have minimal overhead but should be batched when possible
- **String Conversion**: Expensive - cache converted strings when possible
- **Memory Allocation**: Use memory pools for frequent allocations
- **Threading**: Consider moving audio processing to separate native threads

## Future Integration

This setup is prepared for integrating the actual miniaudio library. The placeholder functions can be replaced with real miniaudio calls while maintaining the same FFI interface structure.

## Resources

- [Flutter FFI Documentation](https://dart.dev/guides/libraries/c-interop)
- [iOS FFI Integration Guide](https://docs.flutter.dev/platform-integration/ios/c-interop)
- [package:ffigen Documentation](https://pub.dev/packages/ffigen)
- [Miniaudio Library](https://github.com/mackron/miniaudio)

## 🛠️ Final Miniaudio Integration on iOS (2024-06)

The original guide stopped at a stub implementation.  The following steps reflect the **working** configuration that plays real audio via Miniaudio's CoreAudio backend.

1. **Add the Miniaudio implementation**
   •  Copy `native/miniaudio.h` into your project (already present).
   •  Create `native/miniaudio_wrapper.mm` (Objective-C++) and paste the code that contains `MINIAUDIO_IMPLEMENTATION`, backend macros and the FFI entry-points (`miniaudio_init`, `miniaudio_play_sound`, …).  We moved the implementation into this single file so there is no separate `miniaudio.c` anymore.

2. **Remove / stub old files**
   •  Delete `native/miniaudio_wrapper.c` (renamed to `.mm`).
   •  Leave an *empty* `native/miniaudio.c` stub or remove it from Xcode to avoid duplicate symbols.

3. **Xcode project changes**
   1. Open `ios/Runner.xcworkspace`.
   2. In **Runner → Build Phases → Compile Sources**
      – Add `native/miniaudio_wrapper.mm` to the list (make sure its target checkbox is on).
      – Delete the old `.c` wrapper entry if it is still present.
   3. In **Runner → Build Phases → Link Binary With Libraries** add the system frameworks
      `CoreAudio.framework` and `AudioToolbox.framework` (AVFoundation is *not* needed because we compile with `MA_NO_AVFOUNDATION`).
   4. Verify **Build Settings → Strip Style** is **Non-Global Symbols** so FFI symbols remain visible.

4. **Dart side stays the same**
   The bindings generated by `ffigen` (`lib/miniaudio_bindings_generated.dart`) and the convenience wrapper (`lib/miniaudio_library.dart`) do not change; they call the same C symbols.

5. **Clean & build**
   ```bash
   flutter clean           # remove previous objects that were built for .c file
   cd ios && pod install && cd ..  # ensure Podfile is up-to-date
   flutter run -d <device>  # or flutter build ios --simulator
   ```
   Xcode console should print:
   ```
   ✅ miniaudio engine initialised (CoreAudio)
   ```

6. **Troubleshooting checklist**
   •  If you still see `Could not build module 'Foundation'`, confirm the wrapper file **has a .mm extension** so it is compiled in Objective-C++ mode.
   •  Make sure only one translation unit (`miniaudio_wrapper.mm`) defines `MINIAUDIO_IMPLEMENTATION` to prevent duplicate symbols.
   •  Always clean (`flutter clean` or **Product → Clean Build Folder**) after switching file extensions.

These steps replace the old "test implementation" instructions earlier in this README and reflect the configuration currently committed to the repository.
