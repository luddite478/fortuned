#include "pitch.h"
#include "sample_bank.h"
#include "table.h"  // for DEFAULT_CELL_PITCH
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <thread>
#include <mutex>

// SoundTouch configuration to match legacy
#define SOUNDTOUCH_FLOAT_SAMPLES                     1
#define SOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION  1
#define SOUNDTOUCH_DISABLE_X86_OPTIMIZATIONS         1

#include "soundtouch/SoundTouch.h"
using namespace soundtouch;

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PITCH"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PITCH"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "PITCH"
#endif

// -----------------------------------------------------------------------------
// Internal structures
// -----------------------------------------------------------------------------

// Memory-based cache removed - now using disk-based pitched files

// Global method (default to preprocessing as requested)
static int g_pitch_method = PITCH_METHOD_SOUNDTOUCH_PREPROCESSING;
// Global pitch quality (0..4, best..worst)
static int g_pitch_quality = 0;

// Hash helper removed - no longer needed for memory cache

// Async preprocessing jobs (up to 4 concurrent)
typedef struct {
    int source_slot;
    float pitch_ratio;
    int in_progress;
    std::thread* worker_thread;
} async_preprocess_job_t;

#define MAX_ASYNC_JOBS 4
static async_preprocess_job_t g_async_jobs[MAX_ASYNC_JOBS];
static std::mutex g_async_jobs_mutex;

// -----------------------------------------------------------------------------
// ma_pitch_data_source wrapper
// -----------------------------------------------------------------------------

struct ma_pitch_data_source {
    ma_data_source_base ds;
    ma_data_source* original;
    float pitch_ratio;
    ma_uint32 channels;
    ma_uint32 sample_rate;
    int approach;

    // Resampler (used only when method is explicitly set to MINIAUDIO)
    ma_resampler resampler;
    int resampler_initialized;
    ma_uint32 target_sample_rate;
    float* temp_input_buffer;
    size_t temp_input_buffer_size;

    // Preprocessing (use ma_audio_buffer for PCM cache)
    int sample_slot;
    ma_audio_buffer preprocessed_buffer;
    int preprocessed_buffer_initialized;
    int uses_preprocessed_data;

    // (no debug flags)
};

// Utility macros (match playback.mm)
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

// Forward decls
static ma_result pitch_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead);
static ma_result pitch_seek(ma_data_source* pDataSource, ma_uint64 frameIndex);
static ma_result pitch_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap);
static ma_result pitch_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor);
static ma_result pitch_get_length(ma_data_source* pDataSource, ma_uint64* pLength);

static ma_data_source_vtable g_pitch_vtable = {
    pitch_read,
    pitch_seek,
    pitch_get_data_format,
    pitch_get_cursor,
    pitch_get_length,
    NULL,
    0
};

// -----------------------------------------------------------------------------
// Memory cache helpers removed - now using disk-based pitched files
// -----------------------------------------------------------------------------

// preprocess_sync function removed - now using disk-based pitched files

static void async_worker(int job_index, int source_slot, float ratio) {
    (void)job_index; // not strictly needed beyond cleanup; keep for parity
    prnt("🚀 [PITCH] Async job start (job=%d, slot=%d, ratio=%.3f)", job_index, source_slot, ratio);
    // Mark sample as processing (if sample bank present)
    extern void sample_bank_set_processing(int slot, int processing);
    sample_bank_set_processing(source_slot, 1);
    
    // Generate pitched file on disk instead of memory cache
    const char* output_path = pitch_get_file_path(source_slot, ratio);
    int result = -1;
    if (output_path) {
        result = pitch_generate_file(source_slot, ratio, output_path);
    }
    
    {
        std::lock_guard<std::mutex> lock(g_async_jobs_mutex);
        if (g_async_jobs[job_index].worker_thread) {
            delete g_async_jobs[job_index].worker_thread;
        }
        memset(&g_async_jobs[job_index], 0, sizeof(async_preprocess_job_t));
    }
    prnt("🏁 [PITCH] Async job finished (job=%d, slot=%d, ratio=%.3f, res=%d)", job_index, source_slot, ratio, result);
    sample_bank_set_processing(source_slot, 0);
}

// -----------------------------------------------------------------------------
// Data source vtable impl
// -----------------------------------------------------------------------------

static ma_result pitch_read_resampler(ma_pitch_data_source* p, void* out, ma_uint64 frames, ma_uint64* got) {
    if (!p->resampler_initialized || fabs(p->pitch_ratio - 1.0f) < 0.001f) {
        return ma_data_source_read_pcm_frames(p->original, out, frames, got);
    }
    // Read input into temp
    ma_uint64 need_in = frames / (p->sample_rate / (double)p->target_sample_rate);
    if (need_in == 0) need_in = frames;
    if (p->temp_input_buffer_size < need_in * p->channels) {
        size_t ns = (size_t)(need_in * p->channels);
        float* nb = (float*)realloc(p->temp_input_buffer, ns * sizeof(float));
        if (!nb) return MA_OUT_OF_MEMORY;
        p->temp_input_buffer = nb;
        p->temp_input_buffer_size = ns;
    }
    ma_uint64 in_read = 0;
    ma_result mr = ma_data_source_read_pcm_frames(p->original, p->temp_input_buffer, need_in, &in_read);
    if (mr != MA_SUCCESS && mr != MA_AT_END) return mr;
    ma_uint64 in_to_proc = in_read;
    ma_uint64 out_done = frames;
    mr = ma_resampler_process_pcm_frames(&p->resampler, p->temp_input_buffer, &in_to_proc, out, &out_done);
    if (got) *got = out_done;
    return MA_SUCCESS;
}

static ma_result pitch_read(ma_data_source* ds, void* out, ma_uint64 frames, ma_uint64* got) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)ds;
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        return ma_data_source_read_pcm_frames((ma_data_source*)&p->preprocessed_buffer, out, frames, got);
    }
    if (p->approach == PITCH_METHOD_MINIAUDIO) {
        return pitch_read_resampler(p, out, frames, got);
    }
    // For preprocessing approach without cache: use fallback resampler if initialized; otherwise play unpitched
    return ma_data_source_read_pcm_frames(p->original, out, frames, got);
}

static ma_result pitch_seek(ma_data_source* ds, ma_uint64 frameIndex) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)ds;
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        return ma_data_source_seek_to_pcm_frame((ma_data_source*)&p->preprocessed_buffer, frameIndex);
    }
    return ma_data_source_seek_to_pcm_frame(p->original, frameIndex);
}

static ma_result pitch_get_data_format(ma_data_source* ds, ma_format* fmt, ma_uint32* ch, ma_uint32* sr, ma_channel* map, size_t cap) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)ds;
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        return ma_data_source_get_data_format((ma_data_source*)&p->preprocessed_buffer, fmt, ch, sr, map, cap);
    }
    return ma_data_source_get_data_format(p->original, fmt, ch, sr, map, cap);
}

static ma_result pitch_get_cursor(ma_data_source* ds, ma_uint64* cur) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)ds;
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        return ma_data_source_get_cursor_in_pcm_frames((ma_data_source*)&p->preprocessed_buffer, cur);
    }
    return ma_data_source_get_cursor_in_pcm_frames(p->original, cur);
}

static ma_result pitch_get_length(ma_data_source* ds, ma_uint64* len) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)ds;
    ma_result mr;
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        mr = ma_data_source_get_length_in_pcm_frames((ma_data_source*)&p->preprocessed_buffer, len);
        return mr;
    }
    mr = ma_data_source_get_length_in_pcm_frames(p->original, len);
    if (mr == MA_SUCCESS && p->approach == PITCH_METHOD_MINIAUDIO && p->resampler_initialized && p->pitch_ratio != 1.0f) {
        *len = (ma_uint64)(*len * p->pitch_ratio);
    }
    return mr;
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

int pitch_set_method(int method) {
    int prev = g_pitch_method;
    g_pitch_method = method;
    return prev;
}

int pitch_get_method(void) {
    return g_pitch_method;
}

ma_result pitch_ds_init(ma_pitch_data_source* p,
                        ma_data_source* original,
                        float ratio,
                        ma_uint32 channels,
                        ma_uint32 sampleRate,
                        int sample_slot) {
    if (!p || !original) return MA_INVALID_ARGS;
    memset(p, 0, sizeof(*p));
    ma_data_source_config cfg = ma_data_source_config_init();
    cfg.vtable = &g_pitch_vtable;
    ma_result mr = ma_data_source_init(&cfg, &p->ds);
    if (mr != MA_SUCCESS) return mr;
    p->original = original;
    p->pitch_ratio = ratio;
    p->channels = channels;
    p->sample_rate = sampleRate;
    p->approach = g_pitch_method;
    p->sample_slot = sample_slot;
    prnt("🔧 [PITCH] ds_init(approach=%s, slot=%d, ratio=%.3f, ch=%u, sr=%u)",
         (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING ? "PREPROCESS" : (p->approach == PITCH_METHOD_MINIAUDIO ? "MINIAUDIO" : "UNKNOWN")),
         sample_slot, ratio, (unsigned)p->channels, (unsigned)p->sample_rate);

    // Resampler setup (MINIAUDIO only)
    p->resampler_initialized = 0;
    p->temp_input_buffer = NULL;
    p->temp_input_buffer_size = 0;
    if (p->approach == PITCH_METHOD_MINIAUDIO && ratio != 1.0f) {
        p->target_sample_rate = (ma_uint32)(sampleRate / ratio);
        if (p->target_sample_rate < 8000) p->target_sample_rate = 8000;
        if (p->target_sample_rate > 192000) p->target_sample_rate = 192000;
        ma_resampler_config rc = ma_resampler_config_init(ma_format_f32, channels, sampleRate, p->target_sample_rate, ma_resample_algorithm_linear);
        mr = ma_resampler_init(&rc, NULL, &p->resampler);
        if (mr == MA_SUCCESS) {
            p->resampler_initialized = 1;
            prnt("🎚️ [PITCH] Resampler init ok (target_sr=%u)", (unsigned)p->target_sample_rate);
        } else {
            prnt_err("❌ [PITCH] Resampler init failed: %d", mr);
        }
    }

    // Preprocessing approach now uses disk-based pitched files
    // The pitch data source will use the original decoder for real-time processing
    // or the preloader will use pitched files directly
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && sample_slot >= 0) {
        prnt("ℹ️ [PITCH] Preprocessing approach - using disk-based pitched files (slot=%d, ratio=%.3f)", sample_slot, ratio);
    }
    return MA_SUCCESS;
}

ma_result pitch_ds_set_pitch(ma_pitch_data_source* p, float ratio) {
    if (!p) return MA_INVALID_ARGS;
    if (fabs(p->pitch_ratio - ratio) < 0.001f) return MA_SUCCESS;
    prnt("🎛️ [PITCH] ds_set_pitch: %.3f → %.3f (approach=%d)", p->pitch_ratio, ratio, p->approach);
    p->pitch_ratio = ratio;
    if (p->approach != PITCH_METHOD_MINIAUDIO) {
        // For preprocessing: live change is not applied; caller should rebuild or wait for next trigger
        return MA_SUCCESS;
    }
    // Reconfigure resampler
    if (p->resampler_initialized) { ma_resampler_uninit(&p->resampler, NULL); p->resampler_initialized = 0; }
    if (ratio == 1.0f) return MA_SUCCESS;
    p->target_sample_rate = (ma_uint32)(p->sample_rate / ratio);
    if (p->target_sample_rate < 8000) p->target_sample_rate = 8000;
    if (p->target_sample_rate > 192000) p->target_sample_rate = 192000;
    ma_resampler_config rc = ma_resampler_config_init(ma_format_f32, p->channels, p->sample_rate, p->target_sample_rate, ma_resample_algorithm_linear);
    ma_result mr = ma_resampler_init(&rc, NULL, &p->resampler);
    if (mr == MA_SUCCESS) { p->resampler_initialized = 1; prnt("🎚️ [PITCH] Resampler reinit ok (target_sr=%u)", (unsigned)p->target_sample_rate); }
    return mr;
}

ma_pitch_data_source* pitch_ds_create(ma_data_source* original,
                                      float ratio,
                                      ma_uint32 channels,
                                      ma_uint32 sampleRate,
                                      int sample_slot) {
    ma_pitch_data_source* p = (ma_pitch_data_source*)malloc(sizeof(ma_pitch_data_source));
    if (!p) return NULL;
    if (pitch_ds_init(p, original, ratio, channels, sampleRate, sample_slot) != MA_SUCCESS) {
        free(p);
        return NULL;
    }
    return p;
}

void pitch_ds_uninit(ma_pitch_data_source* p) {
    if (!p) return;
    if (p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        prnt("🧯 [PITCH] Uninit preprocessed buffer");
        ma_audio_buffer_uninit(&p->preprocessed_buffer);
        p->preprocessed_buffer_initialized = 0;
    }
    if (p->resampler_initialized) {
        prnt("🧯 [PITCH] Uninit resampler");
        ma_resampler_uninit(&p->resampler, NULL);
        p->resampler_initialized = 0;
    }
    if (p->temp_input_buffer) { free(p->temp_input_buffer); p->temp_input_buffer = NULL; p->temp_input_buffer_size = 0; }
    ma_data_source_uninit(&p->ds);
}

ma_data_source* pitch_ds_as_data_source(ma_pitch_data_source* p) {
    return (ma_data_source*)p;
}

ma_result pitch_ds_seek_to_start(ma_pitch_data_source* p) {
    if (!p) return MA_INVALID_ARGS;
    prnt("⏮️ [PITCH] Seek to start (approach=%d, using_pre=%d)", p->approach, pitch_ds_uses_preprocessed(p));
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) {
        return ma_data_source_seek_to_pcm_frame((ma_data_source*)&p->preprocessed_buffer, 0);
    }
    return ma_data_source_seek_to_pcm_frame((ma_data_source*)p->original, 0);
}

int pitch_should_rebuild_for_change(ma_pitch_data_source* p, float previous_pitch, float new_pitch) {
    if (!p) return 1;
    int method = pitch_get_method();
    if (method == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING) {
        int using_pre = pitch_ds_uses_preprocessed(p);
        if (fabsf(previous_pitch - new_pitch) >= 0.001f) return 1; // pitch changed → rebuild
        return using_pre ? 0 : 1; // same pitch but not bound to preprocessed yet → rebuild
    }
    return 0;
}

// (removed) pitch_maybe_request_preprocessing; playback triggers preprocessing explicitly

void pitch_ds_destroy(ma_pitch_data_source* p) {
    if (!p) return;
    pitch_ds_uninit(p);
    free(p);
}

int pitch_ds_uses_preprocessed(ma_pitch_data_source* p) {
    if (!p) return 0;
    return (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && p->uses_preprocessed_data && p->preprocessed_buffer_initialized) ? 1 : 0;
}

// pitch_preprocess_sample_sync removed - now using disk-based pitched files

int pitch_start_async_preprocessing(int source_slot, float ratio) {
    // Check if pitched file already exists
    const char* output_path = pitch_get_file_path(source_slot, ratio);
    if (output_path) {
        FILE* test = fopen(output_path, "rb");
        if (test) {
            fclose(test);
            prnt("✅ [PITCH] Async skip, file already exists (slot=%d, ratio=%.3f)", source_slot, ratio);
            extern void sample_bank_set_processing(int slot, int processing);
            sample_bank_set_processing(source_slot, 0);
            return 0;
        }
    }

    std::lock_guard<std::mutex> lock(g_async_jobs_mutex);
    // Avoid duplicate jobs
    for (int i = 0; i < MAX_ASYNC_JOBS; i++) {
        if (g_async_jobs[i].in_progress && g_async_jobs[i].source_slot == source_slot && fabs(g_async_jobs[i].pitch_ratio - ratio) < 0.001f) {
            prnt("⏳ [PITCH] Async already in progress (slot=%d, ratio=%.3f)", source_slot, ratio);
            return 0;
        }
    }
    // Find free slot
    int job_index = -1;
    for (int i = 0; i < MAX_ASYNC_JOBS; i++) { if (!g_async_jobs[i].in_progress) { job_index = i; break; } }
    if (job_index == -1) {
        // No free slot; caller may try again later
        prnt_err("❌ [PITCH] No free async job slot");
        return -1;
    }
    g_async_jobs[job_index].source_slot = source_slot;
    g_async_jobs[job_index].pitch_ratio = ratio;
    g_async_jobs[job_index].in_progress = 1;
    try {
        // Mark processing started
        extern void sample_bank_set_processing(int slot, int processing);
        sample_bank_set_processing(source_slot, 1);
        g_async_jobs[job_index].worker_thread = new std::thread(async_worker, job_index, source_slot, ratio);
        g_async_jobs[job_index].worker_thread->detach();
        prnt("📥 [PITCH] Async job queued (job=%d, slot=%d, ratio=%.3f)", job_index, source_slot, ratio);
        return 0;
    } catch (...) {
        memset(&g_async_jobs[job_index], 0, sizeof(async_preprocess_job_t));
        prnt_err("❌ [PITCH] Failed to start async thread");
        return -1;
    }
}

// pitch_make_decoder_from_cache removed - now using disk-based pitched files

void pitch_clear_preprocessed_cache(void) {
    // Memory cache removed - this function is now a no-op
    // Kept for compatibility with existing code
    prnt("🧹 [PITCH] Cache clearing no longer needed (using disk-based files)");
}

int pitch_get_preprocessed_cache_count(void) {
    // Memory cache removed - always return 0
    return 0;
}

ma_uint64 pitch_get_preprocessed_memory_usage(void) {
    // Memory cache removed - always return 0
    return 0;
}

int pitch_run_preprocessing(int sample_slot, float cell_pitch) {
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) return 1; // nothing to do
    if (pitch_get_method() != PITCH_METHOD_SOUNDTOUCH_PREPROCESSING) return 1;
    float resolved = cell_pitch;
    if (resolved == DEFAULT_CELL_PITCH) {
        Sample* s = sample_bank_get_sample(sample_slot);
        if (s && s->loaded) {
            resolved = s->settings.pitch;
        } else {
            // Sample not loaded yet; cannot resolve default safely
            return 1;
        }
    }
    // Guard invalid ratios and near-unity skips
    if (resolved <= 0.0f) return 1; // guard against sentinel or invalid
    if (resolved < PITCH_MIN_RATIO) resolved = PITCH_MIN_RATIO;
    if (resolved > PITCH_MAX_RATIO) resolved = PITCH_MAX_RATIO;
    if (fabsf(resolved - 1.0f) <= 0.001f) return 1;
    return pitch_start_async_preprocessing(sample_slot, resolved);
}

int pitch_set_quality(int q) {
    if (q < 0) q = 0; if (q > 4) q = 4;
    int prev = g_pitch_quality;
    g_pitch_quality = q;
    prnt("🎚️ [PITCH] Quality set to %d", g_pitch_quality);
    return prev;
}

int pitch_get_quality(void) {
    return g_pitch_quality;
}

// ===================== Disk-Based Pitched File Management =====================

// Get pitched file path for a sample at specific pitch
const char* pitch_get_file_path(int sample_slot, float pitch) {
    static char path[512];
    const char* original_path = sample_bank_get_file_path(sample_slot);
    if (!original_path) return NULL;
    
    // Extract directory and filename
    char dir[256];
    strncpy(dir, original_path, sizeof(dir) - 1);
    dir[sizeof(dir) - 1] = '\0';
    
    char* last_slash = strrchr(dir, '/');
    if (last_slash) *last_slash = '\0';
    
    // Extract filename without extension
    const char* filename = strrchr(original_path, '/');
    filename = filename ? filename + 1 : original_path;
    
    char name_only[128];
    strncpy(name_only, filename, sizeof(name_only) - 1);
    name_only[sizeof(name_only) - 1] = '\0';
    
    // Remove extension
    char* dot = strrchr(name_only, '.');
    if (dot) *dot = '\0';
    
    // Create pitched version path: "kick_p1.200.wav"
    snprintf(path, sizeof(path), "%s/%s_p%.3f.wav", dir, name_only, pitch);
    return path;
}

// Generate pitched file on disk using SoundTouch (similar to preprocess_sync but saves to file)
int pitch_generate_file(int sample_slot, float pitch, const char* output_path) {
    if (fabsf(pitch - 1.0f) < 0.001f) {
        return 0; // No need to generate for pitch 1.0
    }
    
    // Check if already exists
    FILE* test = fopen(output_path, "rb");
    if (test) {
        fclose(test);
        prnt("📁 [PITCH] File already exists: %s", output_path);
        return 0;
    }
    
    prnt("🎵 [PITCH] Generating pitched file: slot=%d, pitch=%.3f → %s", sample_slot, pitch, output_path);
    
    // Prepare decoder
    ma_decoder tmp;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 2, 48000);
    const char* file_path = sample_bank_get_file_path(sample_slot);
    if (!file_path) {
        prnt_err("❌ [PITCH] pitch_generate_file: no file path for slot=%d", sample_slot);
        return -1;
    }
    
    ma_result mr = ma_decoder_init_file(file_path, &cfg, &tmp);
    if (mr != MA_SUCCESS) {
        prnt_err("❌ [PITCH] ma_decoder_init_file failed: %d", mr);
        return -1;
    }
    
    ma_uint64 total_frames = 0;
    ma_decoder_get_length_in_pcm_frames(&tmp, &total_frames);
    prnt("ℹ️ [PITCH] Source length: %llu frames", (unsigned long long)total_frames);
    
    SoundTouch st;
    st.setSampleRate(48000);
    st.setChannels(2);
    st.setPitch(pitch);
    
    // Apply current quality settings
    switch (g_pitch_quality) {
        case 0: // Best quality
            st.setSetting(SETTING_USE_QUICKSEEK, 0);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 82);
            st.setSetting(SETTING_SEEKWINDOW_MS, 28);
            st.setSetting(SETTING_OVERLAP_MS, 12);
            break;
        case 1: // High
            st.setSetting(SETTING_USE_QUICKSEEK, 0);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 60);
            st.setSetting(SETTING_SEEKWINDOW_MS, 24);
            st.setSetting(SETTING_OVERLAP_MS, 10);
            break;
        case 2: // Medium
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 40);
            st.setSetting(SETTING_SEEKWINDOW_MS, 15);
            st.setSetting(SETTING_OVERLAP_MS, 8);
            break;
        case 3: // Low
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 0);
            st.setSetting(SETTING_SEQUENCE_MS, 30);
            st.setSetting(SETTING_SEEKWINDOW_MS, 12);
            st.setSetting(SETTING_OVERLAP_MS, 8);
            break;
        default: // Lowest
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 0);
            st.setSetting(SETTING_SEQUENCE_MS, 24);
            st.setSetting(SETTING_SEEKWINDOW_MS, 8);
            st.setSetting(SETTING_OVERLAP_MS, 6);
            break;
    }
    
    // Process and save to WAV file
    ma_encoder encoder;
    ma_encoder_config encoder_cfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, 2, 48000);
    mr = ma_encoder_init_file(output_path, &encoder_cfg, &encoder);
    if (mr != MA_SUCCESS) {
        prnt_err("❌ [PITCH] Failed to init encoder: %d", mr);
        ma_decoder_uninit(&tmp);
        return -1;
    }
    
    const ma_uint64 CHUNK = 16384;
    float buf[CHUNK * 2];
    float out_buf[CHUNK * 4]; // Extra space for pitch processing
    ma_uint64 rd = 0;
    ma_uint64 total_written = 0;
    
    ma_decoder_seek_to_pcm_frame(&tmp, 0);
    
    for (;;) {
        mr = ma_decoder_read_pcm_frames(&tmp, buf, CHUNK, &rd);
        if (mr != MA_SUCCESS || rd == 0) break;
        
        st.putSamples(buf, (uint)rd);
        
        uint avail = st.numSamples();
        if (avail > 0) {
            uint max_recv = MIN(avail, CHUNK * 2);
            uint received = st.receiveSamples(out_buf, max_recv);
            if (received > 0) {
                ma_encoder_write_pcm_frames(&encoder, out_buf, received, NULL);
                total_written += received;
            }
        }
    }
    
    // Flush remaining samples
    st.flush();
    uint avail = st.numSamples();
    if (avail > 0) {
        uint max_recv = MIN(avail, CHUNK * 2);
        uint received = st.receiveSamples(out_buf, max_recv);
        if (received > 0) {
            ma_encoder_write_pcm_frames(&encoder, out_buf, received, NULL);
            total_written += received;
        }
    }
    
    ma_encoder_uninit(&encoder);
    ma_decoder_uninit(&tmp);
    
    if (total_written == 0) {
        prnt_err("❌ [PITCH] SoundTouch produced 0 frames");
        unlink(output_path); // Delete empty file
        return -1;
    }
    
    prnt("✅ [PITCH] Generated pitched file: %llu frames written to %s", (unsigned long long)total_written, output_path);
    return 0;
}

// Delete specific pitched file
void pitch_delete_file(int sample_slot, float pitch) {
    const char* path = pitch_get_file_path(sample_slot, pitch);
    if (!path) return;
    
    if (unlink(path) == 0) {
        prnt("🗑️ [PITCH] Deleted: %s", path);
    } else {
        prnt("ℹ️ [PITCH] File not found or couldn't delete: %s", path);
    }
}

// Delete all pitched files for a sample
void pitch_delete_all_files_for_sample(int sample_slot) {
    const char* original_path = sample_bank_get_file_path(sample_slot);
    if (!original_path) return;
    
    prnt("🗑️ [PITCH] Cleaning up all pitched files for sample %d", sample_slot);
    
    // Delete common pitch ratios (we'll improve this later with directory scanning)
    float common_pitches[] = {0.25f, 0.5f, 0.707f, 0.8f, 0.9f, 1.1f, 1.2f, 1.414f, 1.5f, 2.0f, 4.0f};
    int num_pitches = sizeof(common_pitches) / sizeof(common_pitches[0]);
    
    for (int i = 0; i < num_pitches; i++) {
        pitch_delete_file(sample_slot, common_pitches[i]);
    }
    
    // TODO: Implement proper directory scanning to find all files matching pattern
}
