# SunVox Recording Architecture

## Overview

This document explains how audio recording works in the Fortuned sequencer using the SunVox library, miniaudio for audio device management, and a custom WAV encoder.

## Architecture Diagram

```
┌─────────────────────────────────────┐
│         SunVox Engine               │
│  (Audio synthesis & sequencing)     │
│  - Generates audio samples          │
│  - OFFLINE mode (no output device)  │
│  - Float32 stereo @ 48kHz           │
└──────────────┬──────────────────────┘
               │
               │ sv_audio_callback(buffer, frames)
               │ Pulls audio when requested
               │ SINGLE CALL PER BUFFER (no double consumption!)
               ▼
┌─────────────────────────────────────┐
│  miniaudio audio callback           │
│  (playback_sunvox.mm)               │
│  Gets ONE buffer of audio           │
│  Called by audio thread @ 48kHz     │
└──────────────┬──────────────────────┘
               │
               │ Same buffer splits to 2 destinations:
               │
       ┌───────┴────────┐
       ▼                ▼
┌─────────────┐  ┌──────────────────┐
│  miniaudio  │  │   wav_writer     │
│   device    │  │ (recording.mm)   │
│  (speakers) │  │  (WAV file)      │
└─────────────┘  └──────────────────┘
       │                │
       ▼                ▼
    🔊 Audio       📁 recording.wav
```

## Components

### 1. SunVox Engine (Audio Generator)

**Files:** `sunvox_wrapper.mm`, `sunvox_lib/`

**Initialization Flags:**
```objective-c
uint32_t flags = SV_INIT_FLAG_USER_AUDIO_CALLBACK |  // We manage audio output
                 SV_INIT_FLAG_AUDIO_FLOAT32 |        // Float32 format
                 SV_INIT_FLAG_ONE_THREAD;            // Simplified threading
```

**Purpose:**
- Generates audio samples from sequencer data
- Operates in OFFLINE mode (no built-in audio output)
- Audio is pulled on-demand via `sv_audio_callback()`

**Key Function:**
```objective-c
int sv_audio_callback(void* buf, int frames, int latency, uint32_t out_time);
```

### 2. miniaudio (Audio Device Manager)

**Files:** `playback_sunvox.mm`, `miniaudio/miniaudio.h`

**Purpose:**
- Manages hardware audio output (speakers/headphones)
- Provides audio callback at regular intervals
- Handles audio device lifecycle (init, start, stop, cleanup)

**Configuration:**
```objective-c
ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
deviceConfig.playback.format = ma_format_f32;      // Float32 (matches SunVox)
deviceConfig.playback.channels = 2;                 // Stereo
deviceConfig.sampleRate = 48000;                    // 48kHz (matches SunVox)
deviceConfig.dataCallback = audio_callback;
```

**Audio Callback (The Heart of the System):**
```objective-c
static void audio_callback(ma_device* device, void* output, 
                          const void* input, ma_uint32 frameCount) {
    float* pOutput = (float*)output;
    
    // Step 1: Get audio from SunVox (SINGLE CALL!)
    int result = sv_audio_callback(pOutput, frameCount, 0, sv_get_ticks());
    
    if (result < 0) {
        // SunVox failed, output silence
        memset(pOutput, 0, frameCount * 2 * sizeof(float));
        return;
    }
    
    // Step 2: If recording is active, write the same buffer to WAV file
    recording_write_frames_from_callback(pOutput, frameCount);
    
    // Step 3: miniaudio automatically sends pOutput to speakers
}
```

### 3. wav_writer (WAV File Encoder)

**Files:** `wav_writer.h`, `wav_writer.mm`

**Purpose:**
- Custom, zero-dependency WAV file encoder
- Writes float32 stereo audio to PCM WAV format
- Thread-safe via mutex (called from audio thread)

**API:**
```objective-c
// Open WAV file for writing
int wav_open(wav_writer* writer, const char* path, int sample_rate, int channels);

// Write frames (called from audio callback)
int wav_write_frames(wav_writer* writer, const float* buffer, int frame_count);

// Close WAV file (updates header with final size)
void wav_close(wav_writer* writer);
```

**Why Custom WAV Writer?**
- ✅ Zero dependencies (no miniaudio encoder needed)
- ✅ Smaller binary size
- ✅ Full control over WAV format
- ✅ Simple, auditable code (~100 lines)

### 4. Recording Module

**Files:** `recording.h`, `recording.mm`

**Purpose:**
- High-level recording API
- Manages WAV writer lifecycle
- Thread-safe buffer writing via mutex
- Handles recording state

**API:**
```objective-c
// Start recording to WAV file
int recording_start(const char* output_path);

// Write frames from audio callback (thread-safe)
void recording_write_frames_from_callback(const float* buffer, int frame_count);

// Stop recording and finalize WAV file
void recording_stop(void);

// Check if recording is active
int recording_is_active(void);
```

**Thread Safety:**
```objective-c
static pthread_mutex_t g_writer_mutex = PTHREAD_MUTEX_INITIALIZER;

void recording_write_frames_from_callback(const float* buffer, int frame_count) {
    if (!g_is_output_recording || !g_output_writer_initialized) {
        return;
    }
    
    pthread_mutex_lock(&g_writer_mutex);
    int frames_written = wav_write_frames(&g_output_writer, buffer, frame_count);
    pthread_mutex_unlock(&g_writer_mutex);
    
    // ... error handling ...
}
```

## Audio Flow

### 1. Initialization (playback_init)

```
1. Initialize SunVox in OFFLINE mode (USER_AUDIO_CALLBACK)
   └→ No built-in audio output
   └→ Audio pulled on-demand

2. Initialize miniaudio device
   └→ Registers audio_callback
   └→ Creates audio output device

3. Start miniaudio device
   └→ Begins calling audio_callback at 48kHz intervals
```

### 2. Real-time Playback (audio_callback)

```
Audio Thread (miniaudio):
1. Callback triggered (needs ~4096 frames)
2. Call sv_audio_callback() → fills buffer with audio
3. Send buffer to speakers (miniaudio handles this)
4. If recording: write same buffer to WAV file
```

### 3. Recording Flow

```
User Action: recording_start("/path/to/output.wav")
   └→ Opens WAV file
   └→ Writes WAV header
   └→ Sets g_is_output_recording = 1

Audio Thread (continuous):
   └→ audio_callback() called every ~85ms (4096 frames @ 48kHz)
      └→ Gets audio from SunVox
      └→ Sends to speakers
      └→ Writes to WAV file (if recording active)

User Action: recording_stop()
   └→ Waits for mutex (ensures last write completes)
   └→ Updates WAV header with final size
   └→ Closes file
   └→ Sets g_is_output_recording = 0
```

## Key Design Decisions

### 1. Single Audio Stream (No Double Consumption)

**Problem:** Initially, SunVox had built-in audio AND we were calling `sv_audio_callback()` separately for recording. This caused:
- 2x playback speed
- Noisy output
- Desynchronized audio

**Solution:** Use `SV_INIT_FLAG_USER_AUDIO_CALLBACK` to disable SunVox's built-in audio. Call `sv_audio_callback()` ONCE per buffer in miniaudio's callback.

### 2. Real-time Monitoring

**Decision:** Record the same buffer that's sent to speakers.

**Benefits:**
- ✅ You hear exactly what's being recorded
- ✅ Perfect sync (no latency)
- ✅ Standard DAW behavior
- ✅ Immediate feedback

### 3. Float32 Format (SV_INIT_FLAG_AUDIO_FLOAT32)

**Decision:** Use float32 throughout the pipeline.

**Benefits:**
- ✅ No int16 ↔ float32 conversion
- ✅ Better performance (~5-10% faster)
- ✅ Higher precision during processing

**Format:**
- Range: -1.0 to +1.0
- Channels: 2 (stereo, interleaved LRLRLR...)
- Sample rate: 48000 Hz

### 4. Thread Safety

**Challenge:** Audio callback runs in audio thread, recording_start/stop run in main thread.

**Solution:**
- Use mutex to protect WAV writer access
- Lock only during file writes (minimal lock time)
- Check recording flag before acquiring mutex (fast path)

### 5. Custom WAV Writer

**Decision:** Implement custom WAV encoder instead of using miniaudio's encoder.

**Rationale:**
- miniaudio encoder requires additional code/dependencies
- WAV format is simple (44-byte header + PCM data)
- Full control over format and error handling
- Reduces binary size

## Configuration

### Audio Settings

```objective-c
#define SUNVOX_SAMPLE_RATE 48000    // 48kHz (high quality)
#define SUNVOX_CHANNELS 2            // Stereo
```

### SunVox Flags

| Flag | Purpose | Required? |
|------|---------|-----------|
| `SV_INIT_FLAG_USER_AUDIO_CALLBACK` | User manages audio output | ✅ YES |
| `SV_INIT_FLAG_AUDIO_FLOAT32` | Float32 format (no conversion) | ⚠️ Recommended |
| `SV_INIT_FLAG_ONE_THREAD` | Simplified threading | ⚠️ Recommended |

## Performance Characteristics

### Real-time Mode (Current Implementation)

- **Playback speed:** 1x (real-time)
- **CPU usage:** Low (audio callback runs ~85ms intervals)
- **Monitoring:** Yes (hear while recording)
- **Use case:** Live recording, performance

### Audio Thread Timing

```
Sample rate: 48000 Hz
Buffer size: 4096 frames
Callback interval: 4096 / 48000 = ~85ms

CPU budget per callback:
  - sv_audio_callback(): ~1-5ms (depends on complexity)
  - Recording write: ~0.1-1ms (disk I/O)
  - Total: <10ms per callback (well within 85ms budget)
```

## Future Enhancements

### Fast Offline Rendering

**Goal:** Export audio faster than real-time (e.g., 100x speed).

**Implementation:**
```objective-c
int recording_start_offline_render(const char* output_path) {
    // 1. Stop miniaudio device (no speakers)
    ma_device_stop(&g_audio_device);
    
    // 2. Pull audio as fast as possible
    float buffer[4096 * 2];  // stereo
    while (not_finished) {
        sv_audio_callback(buffer, 4096, 0, sv_get_ticks());
        wav_write_frames(&writer, buffer, 4096);
        // No sleep! Go as fast as CPU allows
    }
    
    // 3. Close WAV file
    wav_close(&writer);
    
    // 4. Restart miniaudio for playback
    ma_device_start(&g_audio_device);
}
```

**Benefits:**
- ✅ 100x+ faster than real-time
- ✅ Perfect for batch export
- ✅ No speaker output (silent export)
- ✅ Same architecture, different execution

## Troubleshooting

### Common Issues

**1. Crash on `sv_init()` with `USER_AUDIO_CALLBACK` flag**

**Symptom:** Segmentation fault in `smisc_global_init()` or `sfs_make_filename()`.

**Cause:** SunVox tries to load config files (`sunvox_dll_config.ini`) that don't exist on first run.

**Solution:** Pre-create empty config file before `sv_init()`:
```objective-c
#ifdef __APPLE__
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
NSString *docsDir = [paths firstObject];
NSString *configPath = [docsDir stringByAppendingPathComponent:@"sunvox_dll_config.ini"];

if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
    [@"" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
#endif
```

**2. Noisy output / 2x speed playback**

**Symptom:** Audio plays too fast and sounds distorted/noisy.

**Cause:** Double audio consumption - `sv_audio_callback()` called from multiple places.

**Solution:** Ensure `sv_audio_callback()` is called ONLY ONCE per buffer, in miniaudio's audio callback.

**3. Recording file size is 44 bytes (header only)**

**Symptom:** WAV file contains only the header, no audio data.

**Cause:** `recording_write_frames_from_callback()` not being called, or recording flag not set.

**Solution:** Check that:
- `g_is_output_recording` is set to 1
- Audio callback is running (`playback_start()` was called)
- Mutex isn't deadlocked

## File Structure

```
app/native/
├── recording.h                 # Recording module API
├── recording.mm                # Recording implementation
├── wav_writer.h                # WAV encoder API
├── wav_writer.mm               # WAV encoder implementation
├── playback_sunvox.mm          # miniaudio device + audio callback
└── sunvox_wrapper.mm           # SunVox initialization + management

app/docs/features/sunvox_integration/
└── recording.md                # This document
```

## References

- [SunVox Library Documentation](https://warmplace.ru/soft/sunvox/sunvox_lib.php)
- [miniaudio Documentation](https://miniaud.io/)
- [WAV File Format Specification](http://soundfile.sapp.org/doc/WaveFormat/)

## Changelog

- **2025-10-13:** Initial implementation with SunVox + miniaudio + custom WAV writer
  - Implemented hybrid approach (SunVox offline + miniaudio for output)
  - Created custom WAV writer to eliminate miniaudio encoder dependency
  - Fixed crash bug with `SV_INIT_FLAG_USER_AUDIO_CALLBACK` via config file workaround
  - Achieved clean, real-time recording with monitoring





