// SoundTouch configuration for iOS/mobile platforms
// Manually configured for optimal mobile performance

#ifndef SOUNDTOUCH_CONFIG_H
#define SOUNDTOUCH_CONFIG_H

// Use floating point samples (better performance on ARM64)
#define SOUNDTOUCH_FLOAT_SAMPLES 1

// Enable ARM NEON SIMD optimizations for mobile performance
#define SOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION 1

// Platform and compiler detection
#define SOUNDTOUCH_HAVE_STDINT_H 1

// Enable threading support
#define SOUNDTOUCH_USE_MULTI_THREAD 1

// Disable x86-specific optimizations
#undef SOUNDTOUCH_ALLOW_X86_OPTIMIZATIONS
#undef SOUNDTOUCH_ALLOW_MMX
#undef SOUNDTOUCH_ALLOW_SSE

// Version info is already defined in SoundTouch headers

#endif // SOUNDTOUCH_CONFIG_H
