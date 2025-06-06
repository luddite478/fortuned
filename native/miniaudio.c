#define MINIAUDIO_IMPLEMENTATION

// Disable problematic backends for iOS to avoid Foundation conflicts
#define MA_NO_AVFOUNDATION
#define MA_NO_RUNTIME_LINKING
#define MA_NO_COREAUDIO

// Use only basic audio functionality
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_NULL

#include "miniaudio.h"
