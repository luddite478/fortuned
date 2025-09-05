// Dedicated compilation unit for miniaudio implementation to avoid duplicate symbols.

#ifdef __APPLE__
    // iOS/macOS: Configure miniaudio to use CoreAudio only and avoid AVFoundation defaults.
    #define MA_NO_AVFOUNDATION
    #define MA_NO_RUNTIME_LINKING
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_COREAUDIO
    #define MA_ENABLE_NULL
#elif defined(__ANDROID__)
    // Android backends configuration (kept here for parity; this file is not used on Android build).
    #define MA_NO_RUNTIME_LINKING
    #define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
    #define MA_ENABLE_AAUDIO
    #define MA_ENABLE_OPENSL
    #define MA_ENABLE_NULL
#else
    // Other platforms: minimal configuration
    #define MA_NO_RUNTIME_LINKING
#endif

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio/miniaudio.h"


