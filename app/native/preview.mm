#include "preview.h"
#include "playback.h"
#include "table.h"
#include "sample_bank.h"
#include "pitch.h"

#include "miniaudio/miniaudio.h"

#ifdef __APPLE__
#include "log.h"
#undef LOG_TAG
#define LOG_TAG "PREVIEW"
#else
#include "log.h"
#undef LOG_TAG
#define LOG_TAG "PREVIEW"
#endif

typedef struct {
    int active;
    void* decoder;              // ma_decoder*
    void* pitch_ds;             // ma_pitch_data_source*
    void* node;                 // ma_data_source_node*
    int node_initialized;
    int pitch_ds_initialized;
    char* file_path;
} preview_context_t;

static preview_context_t g_sample_preview_ctx;
static preview_context_t g_cell_preview_ctx;

// Forward decl from playback.mm to access global node graph
extern "C" ma_node_graph* playback_get_node_graph(void);

static void preview_cleanup_ctx(preview_context_t* ctx) {
    if (!ctx) return;
    if (ctx->node_initialized && ctx->node) {
        ma_node_uninit((ma_node_base*)ctx->node, NULL);
        free(ctx->node);
        ctx->node = NULL;
        ctx->node_initialized = 0;
    }
    if (ctx->pitch_ds_initialized && ctx->pitch_ds) {
        pitch_ds_destroy((ma_pitch_data_source*)ctx->pitch_ds);
        ctx->pitch_ds = NULL;
        ctx->pitch_ds_initialized = 0;
    }
    if (ctx->decoder) {
        ma_decoder_uninit((ma_decoder*)ctx->decoder);
        free(ctx->decoder);
        ctx->decoder = NULL;
    }
    if (ctx->file_path) {
        free(ctx->file_path);
        ctx->file_path = NULL;
    }
    ctx->active = 0;
}

int preview_init(void) {
    memset(&g_sample_preview_ctx, 0, sizeof(g_sample_preview_ctx));
    memset(&g_cell_preview_ctx, 0, sizeof(g_cell_preview_ctx));
    return 0;
}

void preview_cleanup(void) {
    preview_cleanup_ctx(&g_sample_preview_ctx);
    preview_cleanup_ctx(&g_cell_preview_ctx);
}

static int start_preview_from_decoder(preview_context_t* ctx, ma_decoder* decoder, float pitch, float volume, const char* dbgPathOrNull, int slotForCache) {
    if (!ctx || !decoder) return -1;

    // Replace any existing preview
    preview_cleanup_ctx(ctx);

    ctx->decoder = decoder;

    // For pitched files, we don't need pitch_ds since the file is already pitched
    // Only create pitch_ds if we need real-time pitch processing
    if (fabsf(pitch - 1.0f) > 0.001f && slotForCache >= 0) {
        // Check if we have a pitched file already
        const char* pitched_path = pitch_get_file_path(slotForCache, pitch);
        if (pitched_path) {
            FILE* test = fopen(pitched_path, "rb");
            if (test) {
                fclose(test);
                // Pitched file exists, we should be using it instead of pitch processing
                // This shouldn't happen if caller is using the right file, but handle gracefully
                prnt("ℹ️ [PREVIEW] Pitched file exists, should use disk file instead of pitch processing");
            }
        }
    }

    // Create pitch data source only if needed (for real-time pitch processing)
    if (fabsf(pitch - 1.0f) > 0.001f) {
        ctx->pitch_ds = pitch_ds_create((ma_data_source*)decoder, pitch, CHANNELS, SAMPLE_RATE, slotForCache);
        if (!ctx->pitch_ds) {
            prnt_err("❌ [PREVIEW] Failed to create pitch data source");
            ma_decoder_uninit(decoder);
            free(decoder);
            ctx->decoder = NULL;
            return -1;
        }
        ctx->pitch_ds_initialized = 1;
    } else {
        // No pitch processing needed
        ctx->pitch_ds = NULL;
        ctx->pitch_ds_initialized = 0;
    }

    // Create node
    ctx->node = malloc(sizeof(ma_data_source_node));
    if (!ctx->node) {
        prnt_err("❌ [PREVIEW] Failed to allocate node");
        pitch_ds_destroy((ma_pitch_data_source*)ctx->pitch_ds);
        ctx->pitch_ds = NULL;
        ctx->pitch_ds_initialized = 0;
        ma_decoder_uninit(decoder);
        free(decoder);
        ctx->decoder = NULL;
        return -1;
    }

    ma_node_graph* graph = playback_get_node_graph();
    if (!graph) {
        prnt_err("❌ [PREVIEW] Node graph not available");
        free(ctx->node);
        ctx->node = NULL;
        pitch_ds_destroy((ma_pitch_data_source*)ctx->pitch_ds);
        ctx->pitch_ds = NULL;
        ctx->pitch_ds_initialized = 0;
        ma_decoder_uninit(decoder);
        free(decoder);
        ctx->decoder = NULL;
        return -1;
    }

    ma_data_source* ds;
    if (ctx->pitch_ds) {
        // Use pitch data source (for real-time pitch processing)
        ds = pitch_ds_as_data_source((ma_pitch_data_source*)ctx->pitch_ds);
    } else {
        // Use decoder directly (for unity pitch or already-pitched files)
        ds = (ma_data_source*)ctx->decoder;
    }
    ma_data_source_node_config nodeConfig = ma_data_source_node_config_init(ds);
    ma_result res = ma_data_source_node_init(graph, &nodeConfig, NULL, (ma_data_source_node*)ctx->node);
    if (res != MA_SUCCESS) {
        prnt_err("❌ [PREVIEW] Failed to init data source node: %d", res);
        free(ctx->node);
        ctx->node = NULL;
        pitch_ds_destroy((ma_pitch_data_source*)ctx->pitch_ds);
        ctx->pitch_ds = NULL;
        ctx->pitch_ds_initialized = 0;
        ma_decoder_uninit(decoder);
        free(decoder);
        ctx->decoder = NULL;
        return -1;
    }

    ma_node_attach_output_bus((ma_node_base*)ctx->node, 0, ma_node_graph_get_endpoint(graph), 0);
    ma_node_set_output_bus_volume((ma_node_base*)ctx->node, 0, volume);
    ctx->node_initialized = 1;
    ctx->active = 1;

    if (dbgPathOrNull) {
        ctx->file_path = (char*)malloc(strlen(dbgPathOrNull) + 1);
        if (ctx->file_path) strcpy(ctx->file_path, dbgPathOrNull);
    }

    prnt("▶️ [PREVIEW] Started (vol=%.2f, pitch=%.3f%s%s)", volume, pitch, dbgPathOrNull?", path=":"", dbgPathOrNull?dbgPathOrNull:"");
    return 0;
}

int preview_sample_path(const char* file_path, float pitch, float volume) {
    if (!file_path || *file_path == '\0') {
        prnt_err("❌ [PREVIEW] Invalid file path");
        return -1;
    }

    ma_decoder* dec = (ma_decoder*)malloc(sizeof(ma_decoder));
    if (!dec) return -1;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, CHANNELS, SAMPLE_RATE);
    ma_result res = ma_decoder_init_file(file_path, &cfg, dec);
    if (res != MA_SUCCESS) {
        prnt_err("❌ [PREVIEW] Decoder init failed for %s: %d", file_path, res);
        free(dec);
        return -1;
    }
    return start_preview_from_decoder(&g_sample_preview_ctx, dec, pitch, volume, file_path, -1);
}

int preview_slot(int slot, float pitch, float volume) {
    if (!sample_bank_is_loaded(slot)) {
        prnt_err("❌ [PREVIEW] Slot %d not loaded", slot);
        return -1;
    }
    
    const char* path;
    float effective_pitch = pitch;
    
    // Use pitched file if pitch != 1.0, otherwise use original
    if (fabsf(pitch - 1.0f) > 0.001f) {
        path = pitch_get_file_path(slot, pitch);
        
        // Generate pitched file if it doesn't exist
        if (path) {
            FILE* test = fopen(path, "rb");
            if (!test) {
                // File doesn't exist, generate it
                prnt("🎵 [PREVIEW] Generating pitched file for preview...");
                pitch_generate_file(slot, pitch, path);
            } else {
                fclose(test);
            }
            // Use unity pitch since the file is already pitched
            effective_pitch = 1.0f;
        }
        
        if (!path) {
            // Fallback to original file with real-time pitch processing
            path = sample_bank_get_file_path(slot);
            effective_pitch = pitch;
        }
    } else {
        // Use original file for pitch 1.0
        path = sample_bank_get_file_path(slot);
        effective_pitch = 1.0f;
    }
    
    if (!path || *path == '\0') {
        prnt_err("❌ [PREVIEW] No path for slot %d", slot);
        return -1;
    }
    
    ma_decoder* dec = (ma_decoder*)malloc(sizeof(ma_decoder));
    if (!dec) return -1;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, CHANNELS, SAMPLE_RATE);
    ma_result res = ma_decoder_init_file(path, &cfg, dec);
    if (res != MA_SUCCESS) {
        prnt_err("❌ [PREVIEW] Decoder init failed for %s: %d", path, res);
        free(dec);
        return -1;
    }
    return start_preview_from_decoder(&g_cell_preview_ctx, dec, effective_pitch, volume, path, slot);
}

int preview_cell(int step, int column, float pitch, float volume) {
    Cell* cell = table_get_cell(step, column);
    if (!cell || cell->sample_slot < 0) {
        prnt_err("❌ [PREVIEW] Empty cell [%d,%d]", step, column);
        return -1;
    }
    int slot = cell->sample_slot;
    if (!sample_bank_is_loaded(slot)) {
        prnt_err("❌ [PREVIEW] Sample %d not loaded", slot);
        return -1;
    }

    const char* path = sample_bank_get_file_path(slot);
    if (!path || *path == '\0') {
        prnt_err("❌ [PREVIEW] No path for slot %d", slot);
        return -1;
    }

    // Resolve pitch/volume defaults from sample bank if needed
    float resolved_pitch = pitch;
    if (resolved_pitch == DEFAULT_CELL_PITCH) {
        Sample* s = sample_bank_get_sample(slot);
        resolved_pitch = (s && s->loaded) ? s->settings.pitch : 1.0f;
    }
    float resolved_volume = volume;
    if (resolved_volume == DEFAULT_CELL_VOLUME) {
        Sample* s = sample_bank_get_sample(slot);
        resolved_volume = (s && s->loaded) ? s->settings.volume : 1.0f;
    }

    const char* file_path;
    float effective_pitch = resolved_pitch;
    
    // Use pitched file if pitch != 1.0, otherwise use original
    if (fabsf(resolved_pitch - 1.0f) > 0.001f) {
        file_path = pitch_get_file_path(slot, resolved_pitch);
        
        // Generate pitched file if it doesn't exist
        if (file_path) {
            FILE* test = fopen(file_path, "rb");
            if (!test) {
                // File doesn't exist, generate it
                prnt("🎵 [PREVIEW] Generating pitched file for cell preview...");
                pitch_generate_file(slot, resolved_pitch, file_path);
            } else {
                fclose(test);
            }
            // Use unity pitch since the file is already pitched
            effective_pitch = 1.0f;
        }
        
        if (!file_path) {
            // Fallback to original file with real-time pitch processing
            file_path = path;
            effective_pitch = resolved_pitch;
        }
    } else {
        // Use original file for pitch 1.0
        file_path = path;
        effective_pitch = 1.0f;
    }

    ma_decoder* dec = (ma_decoder*)malloc(sizeof(ma_decoder));
    if (!dec) return -1;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, CHANNELS, SAMPLE_RATE);
    ma_result res = ma_decoder_init_file(file_path, &cfg, dec);
    if (res != MA_SUCCESS) {
        prnt_err("❌ [PREVIEW] Decoder init failed for %s: %d", file_path, res);
        free(dec);
        return -1;
    }
    return start_preview_from_decoder(&g_cell_preview_ctx, dec, effective_pitch, resolved_volume, file_path, slot);
}

void preview_stop_sample(void) {
    preview_cleanup_ctx(&g_sample_preview_ctx);
}

void preview_stop_cell(void) {
    preview_cleanup_ctx(&g_cell_preview_ctx);
}


