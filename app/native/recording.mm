#include "recording.h"
#include "wav_writer.h"
#include <pthread.h>

// Include SunVox for sample rate
#define SUNVOX_STATIC_LIB
#include "sunvox.h"

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "RECORDING"
#endif

// Recording state (super simple now!)
static int g_is_recording = 0;
static wav_writer g_wav_writer;
static pthread_mutex_t g_recording_mutex = PTHREAD_MUTEX_INITIALIZER;

// Start recording output to WAV file
// This just opens the WAV file - actual writing happens in audio callback
int recording_start(const char* file_path) {
    pthread_mutex_lock(&g_recording_mutex);
    
    if (g_is_recording) {
        pthread_mutex_unlock(&g_recording_mutex);
        prnt_err("❌ [RECORDING] Already recording");
        return -2;
    }
    
    prnt("🎙️ [RECORDING] Starting recording to: %s", file_path);
    
    // Open WAV file for writing (48kHz, stereo, float32)
    int result = wav_open(&g_wav_writer, file_path, 48000, 2);
    if (result != 0) {
        pthread_mutex_unlock(&g_recording_mutex);
        prnt_err("❌ [RECORDING] Failed to open WAV file: %s", file_path);
        return -3;
    }
    
    g_is_recording = 1;
    
    pthread_mutex_unlock(&g_recording_mutex);
    
    prnt("✅ [RECORDING] Recording started → %s", file_path);
    prnt("💡 [RECORDING] Audio will be captured from playback callback");
    return 0;
}

// Stop recording and close WAV file
void recording_stop(void) {
    pthread_mutex_lock(&g_recording_mutex);
    
    if (!g_is_recording) {
        pthread_mutex_unlock(&g_recording_mutex);
        return;
    }
    
    prnt("⏹️ [RECORDING] Stopping recording");
    
    // Close WAV file (this finalizes the header with correct sizes)
    wav_close(&g_wav_writer);
    
    g_is_recording = 0;
    
    pthread_mutex_unlock(&g_recording_mutex);
    
    prnt("✅ [RECORDING] Recording stopped and WAV file closed");
}

// Check if recording is active
int recording_is_active(void) {
    return g_is_recording;
}

// Write frames from audio callback
// This is called from playback_sunvox.mm audio callback
// It's the ONLY place where audio is written to the recording
void recording_write_frames_from_callback(const float* buffer, int frame_count) {
    if (!g_is_recording) {
        // Not recording, nothing to do
        return;
    }
    
    pthread_mutex_lock(&g_recording_mutex);
    
    if (!g_is_recording) {
        // Double-check after acquiring lock
        pthread_mutex_unlock(&g_recording_mutex);
        return;
    }
    
    // Write frames to WAV file
    // buffer is float32 interleaved stereo (LRLRLR...)
    // frame_count is number of frames (each frame has 2 samples for stereo)
    int frames_written = wav_write_frames(&g_wav_writer, buffer, frame_count);
    
    if (frames_written < 0) {
        prnt_err("❌ [RECORDING] Failed to write %d frames to WAV", frame_count);
        // Continue recording despite error
    }
    
    pthread_mutex_unlock(&g_recording_mutex);
}

// Legacy function - kept for compatibility but does nothing
// (The old implementation used this, but we've moved to callback-based recording)
void recording_write_frames(const float* buffer, int frame_count) {
    // This function is no longer used - recording happens via callback
    // Kept for API compatibility
    (void)buffer;
    (void)frame_count;
}
