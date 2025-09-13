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

typedef struct preprocessed_sample_t {
    int source_slot;
    float pitch_ratio;
    unsigned int pitch_hash;
    void* processed_data;
    size_t processed_size;
    ma_uint64 processed_frames;
    int in_use;
    ma_uint64 last_accessed;
    ma_uint64 creation_time;
} preprocessed_sample_t;

#define MAX_PREPROCESSED_SAMPLES 64
static preprocessed_sample_t g_pre_cache[MAX_PREPROCESSED_SAMPLES];
static ma_uint64 g_pre_cache_access_counter = 0;
static ma_uint64 g_pre_cache_total_bytes = 0;

// Global method (default to preprocessing as requested)
static int g_pitch_method = PITCH_METHOD_SOUNDTOUCH_PREPROCESSING;
// Global pitch quality (0..4, best..worst)
static int g_pitch_quality = 0;

// Hash helper (quantize to 0.001)
static unsigned int hash_pitch_ratio(float r) {
    return (unsigned int)(r * 1000.0f + 0.5f);
}

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
// Preprocess cache helpers
// -----------------------------------------------------------------------------

static preprocessed_sample_t* find_pre(int source_slot, float ratio) {
    unsigned int h = hash_pitch_ratio(ratio);
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        preprocessed_sample_t* e = &g_pre_cache[i];
        if (e->in_use && e->source_slot == source_slot && e->pitch_hash == h) {
            e->last_accessed = ++g_pre_cache_access_counter;
            prnt("📦 [PITCH] Cache hit (slot=%d, ratio=%.3f, frames=%llu, bytes=%zu)", source_slot, ratio, (unsigned long long)e->processed_frames, (size_t)e->processed_size);
            // Clear cell processing flags for any cells using this sample? Handled at per-cell level.
            return e;
        }
    }
    prnt("📭 [PITCH] Cache miss (slot=%d, ratio=%.3f)", source_slot, ratio);
    return NULL;
}

static void evict_oldest(void) {
    int idx = -1; ma_uint64 t = (ma_uint64)-1;
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (g_pre_cache[i].in_use && g_pre_cache[i].last_accessed < t) {
            t = g_pre_cache[i].last_accessed; idx = i;
        }
    }
    if (idx >= 0) {
        preprocessed_sample_t* e = &g_pre_cache[idx];
        prnt("🧹 [PITCH] Evicting cache entry (slot=%d, ratio=%.3f, frames=%llu, bytes=%zu)", e->source_slot, e->pitch_ratio, (unsigned long long)e->processed_frames, (size_t)e->processed_size);
        if (e->processed_data) {
            g_pre_cache_total_bytes -= e->processed_size;
            free(e->processed_data);
        }
        memset(e, 0, sizeof(*e));
    }
}

static int preprocess_sync(int source_slot, float ratio) {
    if (fabs(ratio - 1.0f) < 0.001f) {
        prnt("⏭️ [PITCH] Skip preprocessing (ratio≈1.0)");
        return 0;
    }
    if (find_pre(source_slot, ratio)) {
        prnt("✅ [PITCH] Preprocess already available (slot=%d, ratio=%.3f)", source_slot, ratio);
        return 0;
    }

    // Prepare decoder
    ma_decoder tmp;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 2, 48000);
    const char* file_path = sample_bank_get_file_path(source_slot);
    if (!file_path) {
        prnt_err("❌ [PITCH] preprocess_sync: no file path for slot=%d", source_slot);
        return -1;
    }
    prnt("⚙️ [PITCH] Preprocess start (slot=%d, ratio=%.3f, file=%s)", source_slot, ratio, file_path);
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
    st.setPitch(ratio);
    // Apply settings based on global pitch quality preset (0 best .. 4 worst)
    // References: SoundTouch docs and community recommendations
    switch (g_pitch_quality) {
        case 0: // Best quality: larger sequence/seek, AA filter on
            st.setSetting(SETTING_USE_QUICKSEEK, 0);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 82);
            st.setSetting(SETTING_SEEKWINDOW_MS, 28);
            st.setSetting(SETTING_OVERLAP_MS, 12);
            break;
        case 1: // High: balanced quality/perf
            st.setSetting(SETTING_USE_QUICKSEEK, 0);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 60);
            st.setSetting(SETTING_SEEKWINDOW_MS, 24);
            st.setSetting(SETTING_OVERLAP_MS, 10);
            break;
        case 2: // Medium: faster, slight artifacts allowed
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 1);
            st.setSetting(SETTING_SEQUENCE_MS, 40);
            st.setSetting(SETTING_SEEKWINDOW_MS, 15);
            st.setSetting(SETTING_OVERLAP_MS, 8);
            break;
        case 3: // Low: faster, AA off
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 0);
            st.setSetting(SETTING_SEQUENCE_MS, 30);
            st.setSetting(SETTING_SEEKWINDOW_MS, 12);
            st.setSetting(SETTING_OVERLAP_MS, 8);
            break;
        default: // 4: Lowest: aggressive speed
            st.setSetting(SETTING_USE_QUICKSEEK, 1);
            st.setSetting(SETTING_USE_AA_FILTER, 0);
            st.setSetting(SETTING_SEQUENCE_MS, 24);
            st.setSetting(SETTING_SEEKWINDOW_MS, 8);
            st.setSetting(SETTING_OVERLAP_MS, 6);
            break;
    }

    ma_uint64 est = total_frames + (total_frames / 2);
    size_t out_bytes = est * 2 * sizeof(float);
    float* out = (float*)malloc(out_bytes);
    if (!out) { ma_decoder_uninit(&tmp); prnt_err("❌ [PITCH] malloc failed (bytes=%zu)", out_bytes); return -1; }

    const ma_uint64 CHUNK = 16384;
    float buf[CHUNK * 2];
    ma_uint64 written = 0; ma_uint64 rd = 0;
    ma_decoder_seek_to_pcm_frame(&tmp, 0);
    for (;;) {
        mr = ma_decoder_read_pcm_frames(&tmp, buf, CHUNK, &rd);
        if (mr != MA_SUCCESS || rd == 0) break;
        st.putSamples(buf, (uint)rd);
        uint avail = st.numSamples();
        if (avail > 0) {
            uint max_recv = (uint)MIN((ma_uint64)avail, est - written);
            written += st.receiveSamples(out + written * 2, max_recv);
        }
        if (written >= est) break;
    }
    st.flush();
    uint avail = st.numSamples();
    if (avail > 0 && written < est) {
        uint max_recv = (uint)MIN((ma_uint64)avail, est - written);
        written += st.receiveSamples(out + written * 2, max_recv);
    }

    ma_decoder_uninit(&tmp);
    if (written == 0) { free(out); prnt_err("❌ [PITCH] SoundTouch produced 0 frames"); return -1; }

    int slot = -1;
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) if (!g_pre_cache[i].in_use) { slot = i; break; }
    if (slot == -1) { evict_oldest(); for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) if (!g_pre_cache[i].in_use) { slot = i; break; } }
    if (slot == -1) { free(out); prnt_err("❌ [PITCH] No cache slot available after eviction"); return -1; }

    preprocessed_sample_t* e = &g_pre_cache[slot];
    e->source_slot = source_slot;
    e->pitch_ratio = ratio;
    e->pitch_hash = hash_pitch_ratio(ratio);
    e->processed_data = out;
    e->processed_size = written * 2 * sizeof(float);
    e->processed_frames = written;
    e->in_use = 1;
    e->last_accessed = ++g_pre_cache_access_counter;
    e->creation_time = g_pre_cache_access_counter;
    g_pre_cache_total_bytes += e->processed_size;
    prnt("✅ [PITCH] Preprocess done (slot=%d, ratio=%.3f, frames=%llu, bytes=%zu, cache_total=%llu)",
         source_slot, ratio, (unsigned long long)e->processed_frames, (size_t)e->processed_size, (unsigned long long)g_pre_cache_total_bytes);
    return 0;
}

static void async_worker(int job_index, int source_slot, float ratio) {
    (void)job_index; // not strictly needed beyond cleanup; keep for parity
    prnt("🚀 [PITCH] Async job start (job=%d, slot=%d, ratio=%.3f)", job_index, source_slot, ratio);
    // Mark sample as processing (if sample bank present)
    extern void sample_bank_set_processing(int slot, int processing);
    sample_bank_set_processing(source_slot, 1);
    int result = preprocess_sync(source_slot, ratio);
    (void)result;
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

    // Preprocessing: if cached exists, create audio buffer from memory
    if (p->approach == PITCH_METHOD_SOUNDTOUCH_PREPROCESSING && sample_slot >= 0) {
        preprocessed_sample_t* e = find_pre(sample_slot, ratio);
        if (e) {
            ma_audio_buffer_config bufCfg = ma_audio_buffer_config_init(ma_format_f32, channels, e->processed_frames, (const float*)e->processed_data, NULL);
            mr = ma_audio_buffer_init(&bufCfg, &p->preprocessed_buffer);
            if (mr == MA_SUCCESS) {
                p->preprocessed_buffer_initialized = 1;
                p->uses_preprocessed_data = 1;
                prnt("🔗 [PITCH] Bound preprocessed buffer (frames=%llu, bytes=%zu)", (unsigned long long)e->processed_frames, (size_t)e->processed_size);
            } else {
                prnt_err("❌ [PITCH] ma_audio_buffer_init failed: %d", mr);
            }
        } else {
            // No cached data yet; caller may kick async preprocessing. We'll play unpitched until cache exists.
            prnt("⏳ [PITCH] No cached data yet for slot=%d, ratio=%.3f", sample_slot, ratio);
        }
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

int pitch_preprocess_sample_sync(int source_slot, float ratio) {
    return preprocess_sync(source_slot, ratio);
}

int pitch_start_async_preprocessing(int source_slot, float ratio) {
    // If already cached, nothing to do
    if (find_pre(source_slot, ratio)) {
        prnt("✅ [PITCH] Async skip, already cached (slot=%d, ratio=%.3f)", source_slot, ratio);
        extern void sample_bank_set_processing(int slot, int processing);
        sample_bank_set_processing(source_slot, 0);
        return 0;
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

int pitch_make_decoder_from_cache(int source_slot, float ratio, ma_decoder* outDecoder) {
    preprocessed_sample_t* e = find_pre(source_slot, ratio);
    if (!e) { prnt("📭 [PITCH] No cached decoder data (slot=%d, ratio=%.3f)", source_slot, ratio); return 0; }
    ma_decoder_config dc = ma_decoder_config_init(ma_format_f32, 2, 48000);
    ma_result mr = ma_decoder_init_memory(e->processed_data, e->processed_size, &dc, outDecoder);
    if (mr == MA_SUCCESS) {
        prnt("🎚️ [PITCH] Decoder created from cache (frames=%llu, bytes=%zu)", (unsigned long long)e->processed_frames, (size_t)e->processed_size);
        return 1;
    } else {
        prnt_err("❌ [PITCH] ma_decoder_init_memory failed: %d", mr);
        return -1;
    }
}

void pitch_clear_preprocessed_cache(void) {
    ma_uint64 before = g_pre_cache_total_bytes;
    int cleared = 0;
    for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) {
        if (g_pre_cache[i].in_use && g_pre_cache[i].processed_data) free(g_pre_cache[i].processed_data);
        if (g_pre_cache[i].in_use) cleared++;
    }
    memset(g_pre_cache, 0, sizeof(g_pre_cache));
    g_pre_cache_total_bytes = 0;
    g_pre_cache_access_counter = 0;
    prnt("🧹 [PITCH] Cleared cache (entries=%d, bytes=%llu)", cleared, (unsigned long long)before);
}

int pitch_get_preprocessed_cache_count(void) {
    int c = 0; for (int i = 0; i < MAX_PREPROCESSED_SAMPLES; i++) if (g_pre_cache[i].in_use) c++; return c;
}

ma_uint64 pitch_get_preprocessed_memory_usage(void) {
    return g_pre_cache_total_bytes;
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
