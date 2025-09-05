#include "sample_bank.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

// Platform-specific logging
#ifdef __APPLE__
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SAMPLE_BANK"
#endif

// Only include miniaudio as a header here (implementation lives elsewhere)
#include "miniaudio/miniaudio.h"

// Sample bank storage
static ma_decoder g_sample_decoders[MAX_SAMPLE_SLOTS];
static char* g_sample_paths[MAX_SAMPLE_SLOTS];
static bool g_sample_loaded[MAX_SAMPLE_SLOTS];

#ifdef __cplusplus
extern "C" {
#endif

void sample_bank_init(void) {
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        g_sample_loaded[i] = false;
        g_sample_paths[i] = NULL;
        memset(&g_sample_decoders[i], 0, sizeof(ma_decoder));
    }
    prnt("✅ [SAMPLE_BANK] Initialized with %d slots", MAX_SAMPLE_SLOTS);
}

void sample_bank_cleanup(void) {
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        if (g_sample_loaded[i]) {
            sample_bank_unload(i);
        }
    }
    prnt("🧹 [SAMPLE_BANK] Cleanup complete");
}

int sample_bank_load(int slot, const char* file_path) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return -1;
    }

    if (!file_path) {
        prnt_err("❌ [SAMPLE_BANK] Null file path for slot %d", slot);
        return -1;
    }

    prnt("📂 [SAMPLE_BANK] Loading sample into slot %d: %s", slot, file_path);

    // Unload existing sample if any
    if (g_sample_loaded[slot]) {
        sample_bank_unload(slot);
    }

    // Initialize decoder for this sample
    ma_result result = ma_decoder_init_file(file_path, NULL, &g_sample_decoders[slot]);
    if (result != MA_SUCCESS) {
        prnt_err("❌ [SAMPLE_BANK] Failed to initialize decoder for %s: %d", file_path, result);
        return -1;
    }

    // Store the file path
    size_t len = strlen(file_path) + 1;
    g_sample_paths[slot] = (char*)malloc(len);
    if (!g_sample_paths[slot]) {
        prnt_err("❌ [SAMPLE_BANK] Failed to allocate memory for path");
        ma_decoder_uninit(&g_sample_decoders[slot]);
        return -1;
    }
    strcpy(g_sample_paths[slot], file_path);

    g_sample_loaded[slot] = true;

    prnt("✅ [SAMPLE_BANK] Sample loaded in slot %d: %s", slot, file_path);
    return 0;
}

void sample_bank_unload(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return;
    }

    if (!g_sample_loaded[slot]) {
        return; // Already unloaded
    }

    prnt("🗑️ [SAMPLE_BANK] Unloading sample from slot %d", slot);

    // Uninitialize decoder
    ma_decoder_uninit(&g_sample_decoders[slot]);

    // Free path memory
    if (g_sample_paths[slot]) {
        free(g_sample_paths[slot]);
        g_sample_paths[slot] = NULL;
    }

    g_sample_loaded[slot] = false;

    prnt("✅ [SAMPLE_BANK] Sample unloaded from slot %d", slot);
}

int sample_bank_play(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return -1;
    }

    if (!g_sample_loaded[slot]) {
        prnt_err("❌ [SAMPLE_BANK] No sample loaded in slot %d", slot);
        return -1;
    }

    prnt("▶️ [SAMPLE_BANK] Playing sample from slot %d", slot);

    // For preview - separate preview playback system can be implemented later
    return 0;
}

void sample_bank_stop(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SAMPLE_BANK] Invalid slot: %d", slot);
        return;
    }

    prnt("⏹️ [SAMPLE_BANK] Stopping sample preview for slot %d", slot);
}

int sample_bank_is_loaded(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS) {
        return 0;
    }

    return g_sample_loaded[slot] ? 1 : 0;
}

const char* sample_bank_get_file_path(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_loaded[slot]) {
        return NULL;
    }

    return g_sample_paths[slot];
}

struct ma_decoder* sample_bank_get_decoder(int slot) {
    if (slot < 0 || slot >= MAX_SAMPLE_SLOTS || !g_sample_loaded[slot]) {
        return NULL;
    }

    return &g_sample_decoders[slot];
}

int sample_bank_get_max_slots(void) {
    return MAX_SAMPLE_SLOTS;
}

#ifdef __cplusplus
} // extern "C"
#endif


