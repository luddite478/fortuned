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

