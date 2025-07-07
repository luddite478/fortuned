## 🚨 **Issues & Solutions**

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