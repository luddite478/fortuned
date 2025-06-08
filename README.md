# Niyya - Flutter FFI + Miniaudio Integration Project

A Flutter project demonstrating FFI (Foreign Function Interface) integration with native C code on iOS, specifically designed for audio applications. This project includes file picker functionality and a complete FFI chain setup with miniaudio integration.

## 🎯 **Project Overview**
- **🎵 Multi-slot audio mixing** - Play up to 8 audio samples simultaneously
- **⚡ Low latency audio playback** using miniaudio
- **🎚️ Memory vs Stream toggle** - Choose between memory-loaded (low latency) or streamed playback per slot
- **🔄 Instant restart capability** - Trigger samples from beginning on each play press
- **📱 Cross-platform support** (iOS focus)
- **🎛️ Real-time mixing** through native audio performance via FFI
- **📁 File picker** for audio files

## 📋 **Current Status**

✅ **WORKING:** Complete FFI chain (Flutter → Dart → C → Return)  
✅ **WORKING:** File picker for audio files  
✅ **WORKING:** iOS build and deployment (simulator and physical device)  
✅ **WORKING:** Miniaudio integration with CoreAudio backend  
✅ **WORKING:** Audio playback with proper lifecycle management  
✅ **WORKING:** **8-slot multi-track mixing system**  
✅ **WORKING:** **Memory vs streaming toggle per slot**  
✅ **WORKING:** **Instant sample triggering with restart capability**  
✅ **WORKING:** **Thread-safe slot operations**  
✅ **WORKING:** **Play All / Stop All global controls**  
✅ **WORKING:** **Bluetooth audio routing for AirPods/Bluetooth speakers**

## 🚀 **Key Features Added Since v8c01ef075**

### **🎛️ Multi-Slot Audio System**
- **8 Independent Audio Slots**: Load different samples into separate slots (0-7)
- **Simultaneous Playback**: All slots can play at the same time, mixed together seamlessly
- **Per-Slot Memory Control**: Toggle between memory-loaded (instant) vs streamed (disk) playback per slot
- **Individual Controls**: Each slot has its own Pick/Play/Stop controls
- **Real-time Status**: Visual feedback showing loaded/playing state per slot

### **⚡ Performance & Safety Improvements**
- **Thread-Safe Operations**: All slot operations use Grand Central Dispatch serial queue
- **Memory-Safe Design**: Proper resource cleanup and memory management
- **Symbol Export Fix**: Added proper `__attribute__((visibility("default")))` for iOS device compatibility
- **Instant Restart**: Samples restart from beginning when triggered while playing
- **Fast Triggering**: Safe to press play/stop rapidly without crashes

### **🎵 Audio Engineering Features**
- **Based on Official Miniaudio Examples**: Implements the "simple mixing" pattern from [miniaudio docs](https://miniaud.io/docs/examples/simple_mixing.html)
- **Single Device Architecture**: Uses one `ma_engine` for optimal performance, no multiple device overhead
- **Automatic Mixing**: Samples are naturally mixed by the audio engine
- **Low-Latency Path**: Memory-loaded samples bypass file I/O for instant triggering

### **🎧 Bluetooth Audio Routing**
- **iOS AVFoundation Integration**: Proper Bluetooth audio session configuration
- **Automatic Bluetooth Routing**: Audio automatically routes to connected AirPods/Bluetooth speakers
- **No User Intervention Required**: Works seamlessly without manual audio route selection
- **Background Compatibility**: Audio session persists across app lifecycle changes
- **CoreAudio + AVFoundation**: Combines miniaudio's performance with iOS audio routing

### **🖥️ Enhanced UI**
- **Slot-Based Interface**: Card layout showing all 8 slots
- **Per-Slot Controls**: Memory toggle, file picker, play/stop per slot
- **Global Controls**: "Play All" and "Stop All" buttons in app bar
- **Status Indicators**: Shows file names, loading status, and playing state
- **Responsive Design**: Scrollable list accommodates all slots

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

**Step 2: Add Test Audio Files to Simulator**
```bash
# Replace DEVICE_ID with your actual device ID
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/path/to/your/audio.wav
```

**Step 3: Verify File Access**
Files will be accessible in:
- **Files app → On My iPhone → [Your App Name]**
- **Files app → iCloud Drive** (if iCloud is enabled)
- **Documents directory** of your app

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

## 🎵 **How to Use the Multi-Slot System**

### **Loading Samples**
1. **Pick Audio Files**: Tap "Pick" button for each slot to select different audio files
2. **Memory Toggle**: Turn on "Memory" switch for instant triggering (loads entire file into RAM)
3. **Auto-Loading**: Files are automatically loaded when you first press play

### **Playing & Mixing**
1. **Individual Playback**: Press "Play" on any slot to start that sample
2. **Instant Restart**: Press "Play" again while playing to restart from beginning
3. **Mixing**: Play multiple slots simultaneously - they mix together automatically
4. **Global Controls**: 
   - **Play All**: Starts all loaded slots at once
   - **Stop All**: Stops all currently playing slots

### **Performance Tips**
- **Use Memory Mode** for short samples you'll trigger frequently (drums, FX)
- **Use Stream Mode** for longer audio files to save RAM
- **Preload Samples** by toggling memory on before playing for instant response

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
- Miniaudio with CoreAudio backend doesn't automatically handle iOS audio session routing
- `MA_NO_AVFOUNDATION` flag prevents proper Bluetooth audio routing
- Default audio session configuration doesn't enable Bluetooth options

**Solution**: **Hybrid iOS Audio Session Configuration**

**Step 1**: Enable AVFoundation alongside CoreAudio
```objective-c
// In miniaudio_wrapper.mm
#import <AVFoundation/AVFoundation.h>
// Keep miniaudio configured for CoreAudio only
#define MA_NO_AVFOUNDATION          // Still avoid direct AVFoundation in miniaudio
#define MA_ENABLE_COREAUDIO         // Use CoreAudio backend for performance
```

**Step 2**: Configure iOS Audio Session for Bluetooth
```objective-c
static int configure_ios_audio_session(void) {
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
        // Configure for Bluetooth with fallback
        BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                                           AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                           AVAudioSessionCategoryOptionDefaultToSpeaker
                                       error:&error];
        
        if (!success) {
            // Fallback to basic playback category
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

**Step 3**: Framework Linking
Add AVFoundation framework to iOS project via Xcode:
- Open `ios/Runner.xcworkspace` in Xcode
- Select Runner target → Build Phases → Link Binary With Libraries
- Add `AVFoundation.framework`

**Step 4**: Initialize on Engine Startup
```objective-c
int miniaudio_init(void) {
    // Configure iOS audio session first
    if (configure_ios_audio_session() != 0) {
        // Continue anyway - don't fail initialization
        os_log_error(OS_LOG_DEFAULT, "Audio session config failed, using defaults");
    }
    
    // Then initialize miniaudio engine as usual
    // ...
}
```

**Result**: ✅ Audio now automatically routes to Bluetooth devices when connected

#### **🔧 Technical Details: Why This Works**

**Dual-Backend Approach**:
- **AVFoundation**: Handles iOS-specific audio routing and session management
- **Miniaudio (CoreAudio)**: Provides low-latency audio mixing and playback performance
- **No Conflict**: AVFoundation configures the session, miniaudio uses the configured audio path

**Audio Session Categories**:
- `AVAudioSessionCategoryPlayback`: Enables background audio and proper routing
- `AVAudioSessionCategoryOptionAllowBluetooth`: Allows basic Bluetooth audio
- `AVAudioSessionCategoryOptionAllowBluetoothA2DP`: Enables high-quality stereo Bluetooth
- `AVAudioSessionCategoryOptionDefaultToSpeaker`: Fallback to speaker when no Bluetooth

**iOS Audio Architecture**:
```
Flutter App → Miniaudio (CoreAudio) → iOS Audio Session (AVFoundation) → Bluetooth/Speaker
```

### 4. **Build Issues**

#### **Podfile Configuration**
**Problem**: CocoaPods not installing Flutter plugins properly.

**Solution**: Updated `ios/Podfile` with proper Flutter configuration:
```ruby
platform :ios, '12.0'
# ... full Flutter podfile setup
flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
```

## 🛠️ **Technical Architecture**

### **🎛️ Multi-Slot Design Pattern**
Based on the official miniaudio "simple mixing" example, the architecture uses:

**Native Layer (C++):**
- **Single `ma_engine`** for optimal performance
- **8 `ma_sound` objects** for individual sample playback
- **Resource manager** for memory vs streaming control
- **Serial dispatch queue** for thread-safe operations
- **Automatic mixing** by the miniaudio engine

**FFI Layer (Dart):**
- **Slot-based API** with indexed operations
- **Memory-safe string conversion** for file paths
- **Error handling** with proper return codes
- **Helper functions** for batch operations

**UI Layer (Flutter):**
- **Per-slot state management** using Lists
- **Card-based interface** for clear separation
- **Real-time status updates** with setState
- **Responsive design** with ListView builder

### **FFI Type Mapping**
- Dart `int` → C `int`
- Dart `bool` → C `int` (0=false, 1=true)
- String conversion requires manual memory management

### **🎧 Bluetooth Audio Integration**
**Hybrid Framework Approach:**
- **AVFoundation** (iOS audio session management)
- **CoreAudio** (miniaudio backend for performance)
- **No conflicts** - AVFoundation configures, CoreAudio executes

**iOS Audio Session Configuration:**
```objective-c
// Configure session with Bluetooth support
[session setCategory:AVAudioSessionCategoryPlayback
         withOptions:AVAudioSessionCategoryOptionAllowBluetooth |
                   AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                   AVAudioSessionCategoryOptionDefaultToSpeaker
               error:&error];
```

**Automatic Routing:**
- Detects connected Bluetooth devices
- Routes audio automatically without user intervention
- Maintains performance benefits of miniaudio

### **Symbol Visibility**
C functions must be declared with proper visibility attributes for iOS:
```c
__attribute__((visibility("default"))) __attribute__((used))
int your_function_name() {
    // implementation
}
```

### **Memory Management**
Always free allocated memory for string conversions:
```dart
final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
try {
  // Use cString
} finally {
  free(cString.cast());
}
```

### **🔄 Thread Safety**
All slot operations are serialized through GCD:
```c
dispatch_sync(g_audio_queue, ^{
    // Thread-safe slot operations
});
```

## 📊 **API Reference**

### **Core Functions**
- `miniaudio_init()` - Initialize audio engine
- `miniaudio_cleanup()` - Cleanup all resources

### **Multi-Slot Functions**
- `miniaudio_get_slot_count()` - Returns 8 (max slots)
- `miniaudio_load_sound_to_slot(slot, path, useMemory)` - Load audio to slot
- `miniaudio_play_slot(slot)` - Play/restart slot sample
- `miniaudio_stop_slot(slot)` - Stop slot playback
- `miniaudio_unload_slot(slot)` - Free slot resources
- `miniaudio_is_slot_loaded(slot)` - Check if slot has audio

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
