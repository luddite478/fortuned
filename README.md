# Niyya - Flutter FFI Integration Project

A Flutter project demonstrating FFI (Foreign Function Interface) integration with native C code on iOS. This project replaces the default Flutter counter increment logic with a C function called through FFI.

## Project Overview

This project demonstrates how to:
- Integrate native C code into a Flutter iOS app
- Use FFI to call C functions from Dart
- Set up dynamic linking for iOS using static compilation
- Configure Xcode for native code integration

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

### Verification Steps

1. **Verify FFI Setup**:
   - Check that `lib/miniaudio_bindings_generated.dart` exists
   - Ensure all dependencies are in `pubspec.yaml`
   - Confirm C files are in `native/` directory

2. **Verify Xcode Integration**:
   - C files appear in Runner group
   - Build succeeds without errors
   - Strip Style is correctly configured

## Technical Notes

- **iOS Approach**: Static linking using `DynamicLibrary.executable()`
- **Symbol Visibility**: Uses `__attribute__((visibility("default")))` for iOS
- **Memory Management**: Automatic through Dart's garbage collector
- **Threading**: FFI calls are synchronous on the main thread

## Future Integration

This setup is prepared for integrating the actual miniaudio library. The placeholder functions can be replaced with real miniaudio calls while maintaining the same FFI interface structure.

## Resources

- [Flutter FFI Documentation](https://dart.dev/guides/libraries/c-interop)
- [iOS FFI Integration Guide](https://docs.flutter.dev/platform-integration/ios/c-interop)
- [package:ffigen Documentation](https://pub.dev/packages/ffigen)
