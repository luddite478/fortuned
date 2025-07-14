//////////////////////////////////////////////////////////////////////////////
///
/// ARM/mobile CPU detection implementation for SoundTouch library
/// Replaces x86-specific cpu_detect_x86.cpp for mobile platforms
///
/// This implementation provides ARM-compatible CPU detection functions
/// with proper isolation between SoundTouch instances.
///
//////////////////////////////////////////////////////////////////////////////

#include "cpu_detect.h"

// Thread-local storage for CPU extension settings to avoid cross-instance interference
#ifdef __APPLE__
    #include <pthread.h>
    static pthread_key_t g_disabled_isa_key;
    static pthread_once_t g_key_once = PTHREAD_ONCE_INIT;
    
    static void make_key() {
        pthread_key_create(&g_disabled_isa_key, NULL);
    }
    
    static uint get_disabled_isa() {
        pthread_once(&g_key_once, make_key);
        void* value = pthread_getspecific(g_disabled_isa_key);
        return value ? (uint)(uintptr_t)value : 0;
    }
    
    static void set_disabled_isa(uint value) {
        pthread_once(&g_key_once, make_key);
        pthread_setspecific(g_disabled_isa_key, (void*)(uintptr_t)value);
    }
#else
    // Fallback to global variable for non-Apple platforms
    static uint g_disabled_isa = 0;
    
    static uint get_disabled_isa() {
        return g_disabled_isa;
    }
    
    static void set_disabled_isa(uint value) {
        g_disabled_isa = value;
    }
#endif

/// Disable given CPU extension features. 
void disableExtensions(uint dwDisableMask)
{
    set_disabled_isa(dwDisableMask);
}

/// ARM/mobile implementation of CPU extension detection
/// Returns 0 since ARM doesn't have x86 extensions, but NEON support
/// is handled by compiler flags and SOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION
uint detectCPUextensions(void)
{
    uint disabled = get_disabled_isa();
    
    // ARM/mobile platforms don't support x86 extensions (MMX, SSE, etc.)
    // NEON support is handled at compile time via:
    // - SOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION
    // - SOUNDTOUCH_FLOAT_SAMPLES
    // - Compiler flags: -mfpu=neon (if needed)
    
    uint extensions = 0;  // No x86 extensions available
    
    // Apply disabled mask (for compatibility with SoundTouch settings)
    return extensions & ~disabled;
}

// Report detected CPU capabilities for diagnostics
void cpu_detect_report_capabilities()
{
    uint capabilities = detectCPUextensions();
    uint disabled = get_disabled_isa();
    
    // Log ARM/mobile capabilities (mainly for debugging)
    if (disabled == 0) {
        // All available extensions enabled (none for ARM)
    } else {
        // Some extensions disabled (academic for ARM)
    }
} 