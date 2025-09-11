#ifndef PITCH_H
#define PITCH_H

#include "miniaudio/miniaudio.h"

#ifdef __cplusplus
extern "C" {
#endif

// Pitch processing methods (kept compatible with legacy semantics)
typedef enum {
    PITCH_METHOD_MINIAUDIO = 0,
    PITCH_METHOD_SOUNDTOUCH_REALTIME = 1,
    PITCH_METHOD_SOUNDTOUCH_PREPROCESSING = 2
} pitch_method_t;

// Opaque pitch data source wrapper
typedef struct ma_pitch_data_source ma_pitch_data_source;

// Set global pitch method (optional; default is preprocessing). Returns previous method.
__attribute__((visibility("default"))) __attribute__((used))
int pitch_set_method(int method);

// Get current global pitch method
__attribute__((visibility("default"))) __attribute__((used))
int pitch_get_method(void);

// Initialize pitch data source.
// - original: required, will be wrapped
// - pitch_ratio: 0.03125 .. 32.0, 1.0 = unity
// - channels/sampleRate: audio format
// - sample_slot: pass the sample bank slot index if known (>=0) to enable cache lookup; -1 if unknown
__attribute__((visibility("default"))) __attribute__((used))
ma_result pitch_ds_init(ma_pitch_data_source* p,
                        ma_data_source* original,
                        float pitch_ratio,
                        ma_uint32 channels,
                        ma_uint32 sampleRate,
                        int sample_slot);

// Convenience factory that allocates and initializes the pitch data source.
__attribute__((visibility("default"))) __attribute__((used))
ma_pitch_data_source* pitch_ds_create(ma_data_source* original,
                                      float pitch_ratio,
                                      ma_uint32 channels,
                                      ma_uint32 sampleRate,
                                      int sample_slot);

// Update pitch ratio at runtime (for realtime/resampler methods). No-op for preprocessing users.
__attribute__((visibility("default"))) __attribute__((used))
ma_result pitch_ds_set_pitch(ma_pitch_data_source* p, float pitch_ratio);

// Uninitialize and free internal resources (does not free p itself)
__attribute__((visibility("default"))) __attribute__((used))
void pitch_ds_uninit(ma_pitch_data_source* p);

// Destroy pitch data source (uninit + free)
__attribute__((visibility("default"))) __attribute__((used))
void pitch_ds_destroy(ma_pitch_data_source* p);

// Access the underlying ma_data_source that the node should wrap (the pitch data source itself)
// Returned pointer is valid while the pitch data source is initialized.
__attribute__((visibility("default"))) __attribute__((used))
ma_data_source* pitch_ds_as_data_source(ma_pitch_data_source* p);

// Seek pitch data source (handles decoder or preprocessed buffer)
__attribute__((visibility("default"))) __attribute__((used))
ma_result pitch_ds_seek_to_start(ma_pitch_data_source* p);

// Decide whether a node should be rebuilt when pitch changes under current method
// Returns 1 if rebuild is required (preprocessing and pitch changed or not yet using preprocessed), 0 otherwise
__attribute__((visibility("default"))) __attribute__((used))
int pitch_should_rebuild_for_change(ma_pitch_data_source* p, float previous_pitch, float new_pitch);

// Query if this pitch data source is using preprocessed audio (only meaningful for preprocessing method)
__attribute__((visibility("default"))) __attribute__((used))
int pitch_ds_uses_preprocessed(ma_pitch_data_source* p);

// Preprocessing cache API (SoundTouch offline). These mirror the legacy behavior.
__attribute__((visibility("default"))) __attribute__((used))
int pitch_preprocess_sample_sync(int source_slot, float pitch_ratio);

__attribute__((visibility("default"))) __attribute__((used))
int pitch_start_async_preprocessing(int source_slot, float pitch_ratio);

// Try to create a decoder from cached preprocessed data. Returns 1 if created, 0 if not found, <0 on error.
__attribute__((visibility("default"))) __attribute__((used))
int pitch_make_decoder_from_cache(int source_slot, float pitch_ratio, ma_decoder* outDecoder);

// Cache maintenance & stats
__attribute__((visibility("default"))) __attribute__((used))
void pitch_clear_preprocessed_cache(void);

__attribute__((visibility("default"))) __attribute__((used))
int pitch_get_preprocessed_cache_count(void);

__attribute__((visibility("default"))) __attribute__((used))
ma_uint64 pitch_get_preprocessed_memory_usage(void);

#ifdef __cplusplus
}
#endif

#endif // PITCH_H


