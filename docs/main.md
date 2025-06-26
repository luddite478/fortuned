# Niyya - Flutter FFI + Miniaudio Integration Project

A Flutter project demonstrating FFI (Foreign Function Interface) integration with native C code on iOS, specifically designed for audio applications. This project showcases a complete FFI chain setup with miniaudio integration for low-latency audio mixing and playback.


### 🎛️ Node Graph Based Mixing
The simple-mixing callback works but limits us when we want many independent voices that can keep playing while others are replaced.  Miniaudio's *node-graph* API solves this by giving every sound its own node whose output is automatically mixed by the graph.

**What changed natively**
1. A global `ma_node_graph` is created during `miniaudio_init()`.
2. Every slot (now up to **1024** instead of 8) receives its own `ma_data_source_node` that wraps the slot's decoder.
3. The device callback became one line – it just calls `ma_node_graph_read_pcm_frames()` which reads the mixed result from the graph's endpoint (it also keeps the same capture logic for recording).
4. Play/stop now just **un-mute / mute** the node (volume 1.0 ↔ 0.0).  That means:
   • A sound keeps playing across steps until explicitly stopped or naturally ends.  
   • Re-triggering a slot simply rewinds the decoder and unmutes the node – perfectly sample-accurate restarts with no clicks.
5. All slots' resources (decoder, memory, node) are cleaned up in the correct order.  The graph itself is torn down in `miniaudio_cleanup()`.

**Dart / Flutter API impact**
• `MiniaudioLibrary.slotCount` now returns 1024, giving head-room for much larger grids (e.g. 16×48 = 768 cells) and future features.

**Benefits achieved**
• Unlimited simultaneous voices (practically 1024) with individual volume control.
• Built-in clipping prevention and high-quality mixing handled by miniaudio.
• Cleaner, shorter data callback and easier future DSP insertions (filters, delays, etc.) – just insert more nodes!

### **🎙️ Output Recording & Rendering**
**Based on Simple Capture Example**: Implements [miniaudio's simple_capture pattern](https://miniaud.io/docs/examples/simple_capture.html) to record the mixed output from our single device architecture.

**Recording Approach:**
- **Relies on Simple Mixing**: Uses the same single `ma_device` that handles playback mixing
- **Data Callback Extension**: Adds recording to the existing mixing callback
- **Zero-Copy Recording**: Mixed output is captured directly without additional processing
- **WAV Format Output**: Records to standard WAV files for maximum compatibility

**Recording Implementation:**
```c
// In the same data_callback that handles mixing:
// 1. Mix all samples first (simple_mixing pattern)
// 2. Then optionally record the mixed result
if (g_is_output_recording) {
    ma_encoder_write_pcm_frames(&g_output_encoder, pOutputF32, frameCount, NULL);
}
```

**Recording Controls:**
- **Record Button** (red dot): Start capturing grid output to WAV file
- **Live Duration Display**: Shows MM:SS recording time with red pulsing indicator
- **Stop Recording**: Saves file to device Documents folder
- **Automatic Naming**: Files named `niyya_recording_YYYYMMDD_HHMMSS.wav`

**Usage Workflow:**
1. Create your beat/pattern in the 16-step grid sequencer
2. Press record button (red dot) to start capturing
3. Press play to start sequencer - everything is recorded live
4. Stop recording when finished - file automatically saved
5. Share or export your recorded creations

### **📊 Memory Usage Tracking**
**Real-time Memory Monitoring:**
- **Per-slot tracking** - Shows memory usage for each loaded sample
- **Total memory display** - Aggregate memory consumption across all slots
- **Memory-only counting** - Only samples loaded in memory mode are tracked
- **Automatic updates** - Memory display refreshes when samples are loaded/unloaded

**Native Implementation:**
- **Precise calculation** - Uses miniaudio's PCM frame data to calculate exact memory usage
- **Format awareness** - Accounts for sample rate, channels, and bit depth
- **Efficient tracking** - Minimal overhead with static memory counters
- **Memory safety** - Proper cleanup and tracking when samples are unloaded

**UI Display:**
- **Slot counter**: Shows "X/8 slots" with samples in memory
- **Total usage**: Displays aggregate memory (B/KB/MB format)
- **Per-sample size**: Shows individual sample memory consumption
- **Color-coded**: Orange for memory stats, cyan for sample details

### **🎛️ DAW-Style Step Sequencer**
**Grid Layout:**
- **4 columns × 16 rows** = 64 cells total (will be configurable in feature)
- **Column = Track**: Each column represents an independent audio track
- **Row = Step**: Each row represents a 1/16 note timing step
- **Visual feedback**: Current playing step highlighted with yellow border

**Timing & BPM:**
- **120 BPM default** with precise timing calculation (wil lbe configurable)
- **1/16 note resolution**: Each step = 125ms at 120 BPM
- **Formula**: `stepDuration = (60 * 1000) / (bpm * 4)` milliseconds
- **Automatic looping**: Continuously cycles through steps 1-16

**Sound Management:**
- **Simultaneous playback**: All sounds on current step play together
- **Column-based replacement**: Sound in column only stops when new sound appears in same column
- **Cross-step sustain**: Sounds continue playing until explicitly replaced
- **Loop continuation**: Sounds from step 16 continue into step 1 if no replacement

**Sequencer Controls:**
- **Play button** (green): Starts sequencer from step 1
- **Stop button** (red): Stops sequencer and all sounds completely
- **Real-time display**: Shows current step (X/16) and BPM
- **Status indicator**: "PLAYING" vs "STOPPED"

**Example Workflow:**
1. Load samples into slots A-H (memory-loaded instantly)
2. Select sample → tap grid cells to place in sequence
3. Press Play → sequencer loops through 16 steps at BPM tempo
4. Each step plays all placed samples simultaneously
5. Column sounds sustain until replaced by new sound in same column

**Native Implementation:**
- **UI Grid Merging**: Multiple UI sound grids are merged into a single unified table in native code
- **Grid Abstraction**: The Flutter UI manages multiple visual grids (e.g., 3 stacked cards), but the native audio engine sees one consolidated sequencer table
- **Simplified Audio Logic**: Native sequencer code operates on a single grid data structure, regardless of UI complexity
- **Efficient Data Transfer**: FFI calls pass the merged grid state to avoid multiple native calls per UI grid
- **Single Audio Timeline**: All UI grids contribute to one unified audio playback sequence in the native mixer

### **🎧 Bluetooth Audio Integration**
**Hybrid Framework Approach:**
- **AVFoundation** (iOS audio session management) 
- **CoreAudio** (miniaudio backend for performance)
- **No conflicts** - AVFoundation configures first, miniaudio respects the session

**Critical Configuration:**
```objective-c
// Prevent miniaudio from overriding our Bluetooth config
#define MA_NO_AVFOUNDATIONR

// Configure session with Bluetooth support (WITHOUT DefaultToSpeaker)
[session setCategory:AVAudioSessionCategoryPlayback
         withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                   AVAudioSessionCategoryOptionAllowBluetoothA2DP
               error:&error];
```

**Why This Works:**
- **Prevents Override**: `MA_NO_AVFOUNDATION` stops miniaudio from forcing `DefaultToSpeaker`
- **External Control**: Our AVFoundation setup configures Bluetooth routing before miniaudio init
- **Automatic Routing**: iOS handles device switching based on our session configuration

### **🎵 MP3 320kbps Audio Conversion**
**High-Quality MP3 Export**: Convert recorded WAV files to professional-grade 320kbps MP3 format using native LAME encoder integration.

**LAME Implementation Architecture:**
- **Manual Native Integration**: LAME 3.100 source code manually integrated alongside miniaudio
- **No Package Dependencies**: Avoids discontinued Flutter packages and licensing issues
- **Commercial-Friendly**: Uses LGPL-licensed LAME for commercial app compatibility
- **Cross-Platform Ready**: Native integration works on both iOS and Android

**Technical Implementation:**

**Native Integration Pattern:**
```c
// LAME wrapper follows same pattern as miniaudio integration
native/
├── lame_wrapper.h          // FFI function definitions
├── lame_wrapper.mm         // Implementation with proper format conversion
├── lame_prefix.h           // System headers for all LAME sources
└── lame/                   // LAME 3.100 source files
    ├── lame.c, bitstream.c, encoder.c, etc.
    └── config.h            // Platform-specific configuration
```

**Smart WAV Format Detection:**
```c
// Properly parses WAV headers instead of assuming format
typedef struct {
    char riff[4];           // "RIFF"
    uint32_t chunk_size;    // File size - 8
    char wave[4];           // "WAVE"
    // ... complete WAV header structure
    uint16_t audio_format;   // 1 = PCM, 3 = IEEE float
    uint16_t num_channels;   // 1 = mono, 2 = stereo
    uint32_t sample_rate;    // Actual sample rate
    uint16_t bits_per_sample; // 16-bit or 32-bit
} wav_header_t;
```

**Audio Format Conversion:**
```c
// Handles miniaudio's 32-bit float output correctly
if (header.audio_format == 3 && header.bits_per_sample == 32) {
    // IEEE float (32-bit) - what miniaudio outputs
    float* float_samples = (float*)wav_buffer;
    for (int i = 0; i < read_frames * header.num_channels; i++) {
        // Convert float (-1.0 to 1.0) to 16-bit signed int (-32768 to 32767)
        float sample = float_samples[i];
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;
        pcm_buffer[i] = (short int)(sample * 32767.0f);
    }
}
```

**iOS Build Configuration:**
```
// Added to all iOS build configurations (Debug/Release/Profile)
GCC_PREFIX_HEADER = "$(SRCROOT)/../native/lame_prefix.h";
HEADER_SEARCH_PATHS = (
    "$(SRCROOT)/../native",
    "$(SRCROOT)/../native/lame",
);
OTHER_CFLAGS = (
    "-DHAVE_CONFIG_H",  // Enable LAME configuration
);
```

**Android Build Configuration:**
```cmake
# native/CMakeLists.txt
set(SOURCES
  miniaudio_wrapper.mm
  lame_wrapper.mm
  # All LAME source files included
  lame/lame.c lame/bitstream.c lame/encoder.c
  # ... (19 total LAME source files)
)

add_definitions(-DHAVE_CONFIG_H)
include_directories(lame)
```

**FFI Integration:**
```dart
// lib/lame_library.dart - Same pattern as MiniaudioLibrary
class LameLibrary {
  static LameLibrary? _instance;
  late final LameBindingsGenerated _bindings;
  
  // Convert WAV to MP3 with error handling
  Future<ConversionResult> convertWavToMp3({
    required String wavPath,
    required String mp3Path,
    int bitrate = 320,
  }) async {
    // Run conversion in isolate to prevent UI blocking
    return await compute(_convertInIsolate, {
      'wavPath': wavPath,
      'mp3Path': mp3Path,
      'bitrate': bitrate,
    });
  }
}
```

**Conversion Service Integration:**
```dart
// lib/services/audio_conversion_service.dart
class AudioConversionService {
  static final _lameLibrary = LameLibrary.instance;
  
  static Future<String?> convertToMp3({
    required String wavFilePath,
    int bitrate = 320,
  }) async {
    // Initialize LAME if not already done
    if (!_lameLibrary.checkAvailability()) {
      await _lameLibrary.initialize();
    }
    
    // Convert with progress tracking
    final result = await _lameLibrary.convertWavToMp3(
      wavPath: wavFilePath,
      mp3Path: mp3FilePath,
      bitrate: bitrate,
    );
    
    return result.success ? mp3FilePath : null;
  }
}
```

**Usage Workflow:**
1. **Record Audio**: Create beats using the step sequencer and record to WAV
2. **Convert**: Tap MP3 export button to convert WAV to 320kbps MP3
3. **Share**: Export high-quality MP3 files for professional use
4. **Quality**: Maintains full dynamic range and frequency response of original recording

**Technical Resolution:**
✅ **Fixed Audio Noise**: Proper 32-bit float to 16-bit signed integer conversion  
✅ **No Build Issues**: Manual LAME integration with prefix headers  
✅ **Cross-Platform**: Works on both iOS and Android builds  
✅ **Commercial Ready**: LGPL licensing suitable for app store distribution

## 🔄 **Complete Step-by-Step Setup Guide**

### 1. **Project Setup**
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

### 3. **iOS Configuration**
- Update `ios/Podfile` with Flutter CocoaPods setup
- Add files to Xcode project (native/*.c and native/*.h)  
- Configure Build Settings: Strip Style → "Non-Global Symbols"
- Add permissions to `ios/Runner/Info.plist`:
```xml
<key>NSDocumentPickerUsageDescription</key>
<string>This app needs access to files to select audio files for playback.</string>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

### 4. **Building and Running**

---

### **Android: Building and Running**

**1. Build the APK (Debug):**
```bash
cd android
./gradlew assembleDebug
```

**2. Install on Emulator or Device:**
```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```
- The `-r` flag reinstalls the app if it already exists.
- Make sure your emulator or device is running and visible to `adb devices`.

### **Important Notes on CMake and Gradle Configuration (Android Native Builds)**

- **CMake Configuration:**
  - The main CMake file is at `native/CMakeLists.txt`.
  - It configures the native build, sets up sources (e.g., `miniaudio_wrapper.mm`), and applies C++ flags for Objective-C++ files.
  - For Android, it links against `OpenSLES` and `log` libraries for audio and logging support.
  - Edit this file to add or remove native sources or change build flags.

- **Gradle Configuration:**
  - The Android Gradle config is in `android/app/build.gradle.kts`.
  - Uses `externalNativeBuild` to point to the CMake file (`../../native/CMakeLists.txt`).
  - Sets the NDK version (`ndkVersion`), ABI filters (armeabi-v7a, arm64-v8a, x86, x86_64), and JNI source directory.
  - Requires the Android NDK and CMake to be installed (install via Android Studio > SDK Manager > SDK Tools).

- **gradle.properties and local.properties:**
  - `local.properties` must have `sdk.dir` (Android SDK path) and `flutter.sdk` (Flutter SDK path).
  - `gradle.properties` can be tuned for JVM memory and other Gradle options.

- **Gradle Wrapper:**
  - The project uses Gradle 8.12 (see `android/gradle/wrapper/gradle-wrapper.properties`).
  - The wrapper ensures consistent Gradle version for all developers.

- **Native Header/Sources:**
  - Native APIs are defined in `native/miniaudio_wrapper.h` and implemented in `native/miniaudio_wrapper.mm`.
  - Platform-specific flags and logging are handled in the source files for Android/iOS/other.

---

### **iOS: Building and Running**

#### **Simulator Setup**
```bash
# Install pods
cd ios && pod install && cd ..

# Run on simulator
flutter run
```

#### **Simulator Testing Guide**

**Step 1: Find Your Simulator Device ID**
```bash
xcrun simctl list devices
```
Look for your running simulator (e.g., "iPhone 15 (E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF) (Booted)")

**Step 2: Launch Simulator**
```bash
rm -rf ~/Library/Developer/CoreSimulator/Caches/*
xcrun simctl boot "iPhone 15" 
open -a Simulator
cd ios && flutter run --debug
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/path/to/your/audio.wav
```

#### **Physical Device Deployment**

1. **Build Release Version**:
```bash
flutter build ios --release
```

2. **Install ios-deploy** (if not already installed):
```bash
npm install -g ios-deploy
```

3. **List Connected Devices**:
```bash
ios-deploy -c
```
This will show your connected iPhone with its ID (e.g., `00008110-000251422E02601E`)

4. **Deploy the Release Build**:
```bash
ios-deploy --bundle build/ios/iphoneos/Runner.app --id <YOUR_DEVICE_ID>
```
Replace `<YOUR_DEVICE_ID>` with your actual device ID from step 3.

**Note**: Make sure your iPhone is:
- Connected via USB
- Unlocked
- Trusts your development computer
- Has developer mode enabled in Settings → Privacy & Security → Developer Mode

## 🎵 **Multi-Slot Audio Usage**

### **Loading Samples**
1. **Pick Audio Files**: Select different audio files for each slot
2. **Automatic Loading**: Samples are immediately loaded into memory when selected
3. **Instant Access**: All loaded samples are ready for immediate triggering

### **DAW Sequencer Mode**
1. **Sample Selection**: Tap loaded sample slot to select it for placement (yellow highlight)
2. **Grid Placement**: Tap any cell in the 4×16 grid to place selected sample
3. **Visual Organization**: Placed samples show with their unique colors and letters (A-H)
4. **Sequencer Playback**: Press Play to start BPM-based step sequencing
5. **Real-time Control**: Stop button halts all playback immediately

### **Manual Playback Mode**
1. **Individual Playback**: Tap grid cell to instantly play placed sample
2. **Simultaneous Mixing**: Multiple samples can play together naturally
3. **Direct Triggering**: Perfect for live performance and beat making

### **Performance Tips**
- **Choose Files Wisely**: Since all samples load into memory, consider file sizes
- **Memory Monitoring**: Check memory usage in the status display to manage resources
- **Instant Triggering**: Perfect for drums, FX, loops, and any samples requiring zero latency
- **Hot-Swapping**: Replace samples anytime - new files load immediately
- **Sequencer Patterns**: Create complex rhythms using the 16-step grid
- **Layering**: Use multiple columns for polyrhythmic patterns

## 🎯 **Grid Gesture System**

### **🖱️ Gesture Modes**
The grid supports two distinct interaction modes with intelligent gesture detection:

#### **Normal Mode (Default)**
- **Tap**: Play individual samples instantly
- **Vertical Drag**: Scroll through the grid
- **Horizontal Drag**: Multi-select cells for batch operations

#### **Selection Mode (Toggle Button)**
- **Visual Indicator**: Cyan border around grid when active
- **All Gestures**: Force selection behavior (no scrolling)
- **Toggle Button**: Check box icon switches between modes

### **🎯 Selection Logic**

#### **Single Cell Selection**
- **No cells selected** → Tap cell → Select it
- **1 cell selected** → Tap same cell → Deselect it
- **1 cell selected** → Tap different cell → Unselect previous, select new
- **Multiple cells selected** → Tap any cell → Clear all selections

#### **Multi-Cell Selection**
**Drag Selection:**
- **Start**: Touch down on any cell immediately selects it
- **Continue**: Drag to adjacent cells to extend selection
- **Visual Feedback**: Yellow borders and glow effects on selected cells
- **Real-time**: Selection updates continuously during drag

**Auto-Scroll During Selection:**
- **Edge Detection**: When dragging within 50px of top/bottom edges
- **Auto-Scroll Speed**: 8.0 pixels per tick at 12ms intervals (~83fps)
- **Continuous Selection**: Cells are selected while scrolling
- **Smart Limits**: Auto-scroll stops at grid boundaries

### **🎮 Gesture Detection Algorithm**

#### **Intelligent Direction Detection**
```dart
// 15px movement threshold to determine intent
if (delta.distance > 15.0) {
  final isVertical = delta.dy.abs() > delta.dx.abs();
  
  if (inSelectionMode) {
    // ALWAYS select when selection mode is active
    gestureMode = GestureMode.selecting;
  } else if (isVertical) {
    // Vertical movement in normal mode = scroll
    gestureMode = GestureMode.scrolling;
  } else {
    // Horizontal movement = select
    gestureMode = GestureMode.selecting;
  }
}
```

#### **Physics Management**
- **Selection Mode**: `NeverScrollableScrollPhysics` - Prevents all scrolling
- **Normal Mode**: `AlwaysScrollableScrollPhysics` - Allows natural scrolling
- **Dynamic Switching**: Physics change based on gesture detection

### **🔧 Technical Implementation**

#### **Grid Cell Detection**
```dart
// Precise cell calculation with scroll offset
int? getCellIndexFromPosition(Offset position, BuildContext context, {double scrollOffset = 0.0}) {
  // Account for container padding (16px)
  final adjustedX = position.dx - 16.0;
  final adjustedY = position.dy - 16.0 + scrollOffset;
  
  // 2px edge margin for forgiving selection
  final cellWidth = (containerWidth - 32.0) / gridColumns;
  final cellHeight = (containerHeight - 32.0) / gridRows;
  
  // Boundary checking with edge tolerance
  if (adjustedX >= -2.0 && adjustedX <= containerWidth - 32.0 + 2.0 &&
      adjustedY >= -2.0 && adjustedY <= containerHeight - 32.0 + 2.0) {
    final col = (adjustedX / cellWidth).floor().clamp(0, gridColumns - 1);
    final row = (adjustedY / cellHeight).floor().clamp(0, gridRows - 1);
    return row * gridColumns + col;
  }
  return null;
}
```

#### **Auto-Scroll Implementation**
```dart
void _startAutoScroll(double direction, Offset position, TrackerState tracker) {
  _autoScrollTimer = Timer.periodic(Duration(milliseconds: 12), (timer) {
    final currentOffset = _scrollController.offset;
    final newOffset = currentOffset + (direction * 8.0); // 8px per tick
    final clampedOffset = newOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
    
    if (clampedOffset != currentOffset) {
      _scrollController.jumpTo(clampedOffset);
      // Continue selection at current position
      final cellIndex = tracker.getCellIndexFromPosition(position, context, scrollOffset: clampedOffset);
      if (cellIndex != null) {
        tracker.handleGridCellSelection(cellIndex, true);
      }
    } else {
      timer.cancel(); // Stop when reaching limits
    }
  });
}
```

### **📱 User Experience Features**

#### **Visual Feedback**
- **Selection Mode**: Cyan border around entire grid
- **Selected Cells**: Yellow borders with glow shadow effects
- **Current Step**: Yellow border during sequencer playback
- **Drag Hover**: Green highlight when dragging samples

#### **Gesture Conflicts Resolution**
- **Priority System**: Selection mode overrides all other gestures
- **Clear Intent**: 15px threshold prevents accidental mode switching
- **Smooth Transitions**: Physics changes don't interrupt ongoing gestures
- **Edge Cases**: Proper handling of simultaneous touch events

#### **Performance Optimizations**
- **Efficient Detection**: Minimal calculations during gesture recognition
- **Smooth Auto-Scroll**: 83fps update rate for fluid scrolling
- **Memory Efficient**: No gesture history storage beyond current session
- **Responsive UI**: Immediate visual feedback on touch events

### **🎯 Usage Patterns**

#### **Quick Selection (Normal Mode)**
1. **Horizontal Drag**: Select multiple cells in a row quickly
2. **Tap Individual**: Select single cells for precise control
3. **Natural Scrolling**: Vertical drag scrolls through long grids

#### **Precise Selection (Selection Mode)**
1. **Toggle Mode**: Activate selection mode with button
2. **Any Direction**: Drag in any direction to select cells
3. **Auto-Scroll**: Drag to edges to continue selection beyond visible area
4. **Batch Operations**: Select large areas for bulk sample placement

#### **Best Practices**
- **Use Selection Mode**: For complex multi-cell operations
- **Normal Mode**: For quick single-cell interactions and scrolling
- **Edge Dragging**: Utilize auto-scroll for selecting across many rows
- **Visual Cues**: Watch for cyan border to confirm selection mode is active

## 🚨 **Common Issues & Solutions**

### 1. **iOS Integration Challenges**

#### **Foundation Framework Conflicts**
**Problem**: When integrating miniaudio library, iOS Foundation framework conflicts:
```
Parse Issue (Xcode): Could not build module 'Foundation'
Parse Issue (Xcode): Could not build module 'AVFoundation'
```

**Solution**: 
- Use `.mm` extension for Objective-C++ files
- Define `MA_NO_AVFOUNDATION` to disable AVFoundation
- Define `MA_NO_RUNTIME_LINKING` to disable runtime linking
- Use CoreAudio backend only

#### **Duplicate Symbol Errors**
**Problem**: Duplicate symbols when including miniaudio in multiple files.

**Solution**: 
- Only define `MINIAUDIO_IMPLEMENTATION` in one file (`miniaudio_wrapper.mm`)
- Use forward declarations in wrapper files
- Separate compilation units properly

#### **⚠️ Symbol Export Issues (iOS Device)**
**Problem**: App works in simulator but crashes on real device with symbol lookup errors:
```
Failed to lookup symbol 'miniaudio_init': dlsym(RTLD_DEFAULT, miniaudio_init): symbol not found
```

**Solution**: 
Added proper export attributes to ALL native functions:
```c
__attribute__((visibility("default"))) __attribute__((used))
int miniaudio_init(void) { ... }
```

### 2. **File Access Issues**

#### **File Picker iOS Permissions**
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

### 3. **Bluetooth Audio Routing Issues**

#### **⚠️ Audio Routes to Phone Speaker Instead of Bluetooth**
**Problem**: App works correctly but audio plays through phone speakers instead of connected Bluetooth headphones/speakers, even when Bluetooth audio is working in other apps.

**Root Cause**: 
Based on [miniaudio GitHub issue #101](https://github.com/mackron/miniaudio/issues/101), miniaudio automatically adds `AVAudioSessionCategoryOptionDefaultToSpeaker` when using the default session category, which **overrides any Bluetooth routing configuration**.

**Solution**: **Prevent Miniaudio's DefaultToSpeaker Override**

**The Key Fix**: Properly configure `MA_NO_AVFOUNDATION` to prevent miniaudio from setting its own audio session:

```objective-c
// In miniaudio_wrapper.mm
#import <AVFoundation/AVFoundation.h>

// CRITICAL: Prevent miniaudio from setting DefaultToSpeaker
#define MA_NO_AVFOUNDATION          
#define MA_ENABLE_COREAUDIO         // Use CoreAudio backend for performance
```

**Step 1**: External AVFoundation Configuration
```objective-c
static int configure_ios_audio_session(void) {
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        // Configure for Bluetooth WITHOUT DefaultToSpeaker
        BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                           AVAudioSessionCategoryOptionAllowBluetoothA2DP
                                       error:&error];
        
        if (!success) {
            success = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
        }
        
        [session setMode:AVAudioSessionModeDefault error:&error];
        [session setActive:YES error:&error];
        
        return success ? 0 : -1;
    } @catch (NSException *exception) {
        return -1;
    }
}
```

**Step 2**: Initialize Before Miniaudio
```objective-c
int miniaudio_init(void) {
    // Configure iOS audio session BEFORE miniaudio init
    if (configure_ios_audio_session() != 0) {
        os_log_error(OS_LOG_DEFAULT, "Audio session config failed, using defaults");
    }
    
    // Initialize miniaudio with MA_NO_AVFOUNDATION
    ma_engine_config engine_config = ma_engine_config_init();
    // ... rest of initialization
}
```

**Step 3**: App Lifecycle Management
```dart
// In Flutter (main.dart)
class _TrackerPageState extends State<TrackerPage> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _miniaudioLibrary.reconfigureAudioSession(); // Re-activate Bluetooth routing
    }
  }
}
```

**Result**: ✅ Audio automatically routes to Bluetooth devices when connected

#### **🔧 Technical Details: Why This Works**

**The Problem**: 
From [miniaudio source code](https://github.com/mackron/miniaudio/issues/101), when `sessionCategory == ma_ios_session_category_default`:
```c
#if !defined(MA_APPLE_TV) && !defined(MA_APPLE_WATCH)
    options |= AVAudioSessionCategoryOptionDefaultToSpeaker;  // Forces speaker output!
#endif
```

**The Solution**:
- **`MA_NO_AVFOUNDATION`**: Prevents miniaudio from calling its internal audio session setup
- **External AVFoundation**: Our configuration runs first and sets proper Bluetooth routing
- **No Override**: Miniaudio uses our pre-configured session instead of forcing speakers

**Audio Session Flow**:
```
1. Our AVFoundation config → Bluetooth routing enabled
2. Miniaudio init (MA_NO_AVFOUNDATION) → Uses existing session  
3. Audio playback → Routes to Bluetooth automatically
```

**Why Previous Approaches Failed**:
- Configuring session AFTER miniaudio init → Gets overridden by DefaultToSpeaker
- Complex context configuration → Broke basic audio functionality
- Missing `MA_NO_AVFOUNDATION` → Miniaudio still forced speaker routing

#### **✅ Resolution Summary**
**Issue**: Bluetooth audio routing stopped working after UI changes in commit `2e1be7e`, despite working in commit `ba089a3`.

**Root Cause**: [Miniaudio GitHub issue #101](https://github.com/mackron/miniaudio/issues/101) - miniaudio automatically forces `AVAudioSessionCategoryOptionDefaultToSpeaker` which overrides Bluetooth routing.

**Solution**: 
1. **`MA_NO_AVFOUNDATION`** prevents miniaudio from setting its own audio session
2. **External AVFoundation configuration** sets up Bluetooth routing before miniaudio init  
3. **App lifecycle management** re-configures session when app resumes

**Status**: ✅ **FIXED** - Audio now routes to Bluetooth devices automatically while maintaining all existing functionality.

## 🛠️ **Technical Architecture**

### **🎛️ Multi-Slot Design Pattern**
Based on the official miniaudio "simple mixing" example, the architecture uses:

**Native Layer (C++):**
- **Single `ma_engine`** for optimal performance
- **8 `ma_sound` objects** for individual sample playback
- **Resource manager** for memory-loaded samples
- **Serial dispatch queue** for thread-safe operations
- **Automatic mixing** by the miniaudio engine

**FFI Layer (Dart):**
- **Slot-based API** with indexed operations
- **Memory-safe string conversion** for file paths
- **Error handling** with proper return codes
- **Helper functions** for batch operations

**Sequencer Layer (Flutter):**
- **4×16 grid state** tracking sample placement
- **BPM-based timing** using Dart `Timer` for precise step control
- **Column-specific sound management** for proper audio replacement
- **Real-time UI updates** with step highlighting and status display

### **FFI Type Mapping**
- Dart `int` → C `int`
- Dart `bool` → C `int` (0=false, 1=true)
- String conversion requires manual memory management

### **🎧 Bluetooth Audio Integration**
**Hybrid Framework Approach:**
- **AVFoundation** (iOS audio session management) 
- **CoreAudio** (miniaudio backend for performance)
- **No conflicts** - AVFoundation configures first, miniaudio respects the session

**Critical Configuration:**
```objective-c
// Prevent miniaudio from overriding our Bluetooth config
#define MA_NO_AVFOUNDATION

// Configure session with Bluetooth support (WITHOUT DefaultToSpeaker)
[session setCategory:AVAudioSessionCategoryPlayback
         withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                   AVAudioSessionCategoryOptionAllowBluetoothA2DP
               error:&error];
```

**Why This Works:**
- **Prevents Override**: `MA_NO_AVFOUNDATION` stops miniaudio from forcing `DefaultToSpeaker`
- **External Control**: Our AVFoundation setup configures Bluetooth routing before miniaudio init
- **Automatic Routing**: iOS handles device switching based on our session configuration

## 📊 **API Reference**

### **Core Functions**
- `miniaudio_init()` - Initialize audio engine
- `miniaudio_cleanup()` - Cleanup all resources

### **Multi-Slot Functions**
- `miniaudio_get_slot_count()` - Returns 8 (max slots)
- `miniaudio_load_sound_to_slot(slot, path)` - Load audio to slot (always in memory)
- `miniaudio_play_slot(slot)` - Play/restart slot sample
- `miniaudio_stop_slot(slot)` - Stop slot playback
- `miniaudio_unload_slot(slot)` - Free slot resources
- `miniaudio_is_slot_loaded(slot)` - Check if slot has audio

### **Memory Tracking Functions**
- `miniaudio_get_total_memory_usage()` - Get total memory used by all samples (bytes)
- `miniaudio_get_slot_memory_usage(slot)` - Get memory used by specific slot (bytes)
- `miniaudio_get_memory_slot_count()` - Get count of slots loaded in memory mode

### **Legacy Functions (Still Supported)**
- `miniaudio_play_sound(path)` - Direct file playback
- `miniaudio_load_sound(path)` - Load to legacy single buffer
- `miniaudio_play_loaded_sound()` - Play legacy buffer
- `miniaudio_stop_all_sounds()` - Stop everything (slots + legacy)

## Resources

- [Flutter FFI Documentation](https://dart.dev/guides/libraries/c-interop)
- [iOS FFI Integration Guide](https://docs.flutter.dev/platform-integration/ios/c-interop)
- [package:ffigen Documentation](https://pub.dev/packages/ffigen)
- [Miniaudio Library](https://github.com/mackron/miniaudio)
- [Miniaudio Simple Mixing Example](https://miniaud.io/docs/examples/simple_mixing.html)