**Simple Mixing Implementation:**
```c
// Official miniaudio Simple Mixing data callback (exactly like the example)
static void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    float* pOutputF32 = (float*)pOutput;
    memset(pOutputF32, 0, sizeof(float) * frameCount * CHANNEL_COUNT);

    // Mix all active slots
    for (int slot = 0; slot < MINIAUDIO_MAX_SLOTS; ++slot) {
        audio_slot_t* s = &g_slots[slot];
        
        // Skip inactive, unloaded, or finished slots
        if (!s->active || !s->loaded || s->at_end) {
            continue;
        }

        mix_slot_audio(s, pOutputF32, frameCount);
    }
}

**How Mixing Works:**
- **Zero Output Buffer**: Starts with silence (`memset(pOutputF32, 0, ...)`)
- **Additive Mixing**: Each slot adds its samples to the output buffer
- **Natural Blending**: Multiple samples playing simultaneously blend together
- **No Clipping Protection**: Relies on proper sample levels (like the official example)

**Key Technical Benefits:**
- **Low-Latency Path**: Memory-loaded samples bypass file I/O for instant triggering
- **Efficient Mixing**: Simple float addition, no complex DSP processing
- **Scalable**: Easily handles 1-8 simultaneous samples
- **Standard Pattern**: Follows miniaudio's recommended approach exactly