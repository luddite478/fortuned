#ifndef RECORDING_H
#define RECORDING_H

#ifdef __cplusplus
extern "C" {
#endif

// Start recording SunVox output to WAV file
// Returns: 0 on success, negative error code on failure
//   -1: Playback not initialized
//   -2: Already recording
//   -3: Failed to initialize encoder
int recording_start(const char* file_path);

// Stop recording and close WAV file
void recording_stop(void);

// Check if recording is currently active
// Returns: 1 if recording, 0 if not
int recording_is_active(void);

// Write frames from audio callback (called from playback_sunvox.mm audio callback)
// This is thread-safe and will only write if recording is active
// buffer: float32 interleaved stereo audio (LRLRLR...)
// frame_count: number of frames (not samples!)
void recording_write_frames_from_callback(const float* buffer, int frame_count);

// Write frames to recording (called from audio callback)
// This is called by audio_output.mm when recording is active
// NOTE: Must be thread-safe!
void recording_write_frames(const float* buffer, int frame_count);

#ifdef __cplusplus
}
#endif

#endif // RECORDING_H

