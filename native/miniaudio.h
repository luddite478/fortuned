#ifndef MINIAUDIO_H
#define MINIAUDIO_H

#ifdef __cplusplus
extern "C" {
#endif

// Simple counter function to replace the Flutter increment logic
__attribute__((visibility("default"))) __attribute__((used))
int increment_counter(int current_value);

// Initialize function (placeholder for future miniaudio integration)
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_init(void);

// Cleanup function (placeholder for future miniaudio integration)
__attribute__((visibility("default"))) __attribute__((used))
void miniaudio_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif // MINIAUDIO_H 