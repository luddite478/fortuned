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
- **Automatic Naming**: Files named `fortuned_recording_YYYYMMDD_HHMMSS.wav`
