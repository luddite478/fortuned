# Miniaudio Library

This folder contains the external [miniaudio](https://miniaud.io/) library files:

- `miniaudio.h` - The complete miniaudio header-only library (v0.11+)
- `miniaudio.c` - Stub file (implementation is included via `#define MINIAUDIO_IMPLEMENTATION` in sequencer.mm)

## About miniaudio

miniaudio is a single file audio playback and capture library written in C. It's used in this project to provide cross-platform audio functionality including:

- Audio playback and mixing
- Sample-accurate sequencing
- Real-time audio processing
- WAV file recording

## Usage

The library is included in `../sequencer.mm` with:
```c
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio/miniaudio.h"
```

For more information, see the [official miniaudio documentation](https://miniaud.io/docs/). 