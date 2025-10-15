#include "sunvox_wrapper.h"
#include "table.h"
#include "sample_bank.h"
#include "playback.h"  // For PlaybackState and playback_get_state_ptr
#include <math.h>

// Platform-specific logging
#ifdef __APPLE__
    #import <Foundation/Foundation.h>  // For NSString, NSFileManager, etc.
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#elif defined(__ANDROID__)
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#else
    #include "log.h"
    #undef LOG_TAG
    #define LOG_TAG "SUNVOX"
#endif

// Use static linking with SunVox library
#define SUNVOX_STATIC_LIB
#include "sunvox.h"

// Forward declare our custom SunVox functions (defined in sunvox_lib.cpp)
extern "C" {
    int sv_pattern_set_flags(int slot, int pat_num, uint32_t flags, int set);
    int sv_enable_supertracks(int slot, int enable);
    int sv_set_pattern_loop(int slot, int pattern_num);  // NEW: Pattern loop mode
}

#define SV_PATTERN_FLAG_NO_NOTES_OFF  (1<<1)

// Constants
#define SUNVOX_SLOT 0                    // Use slot 0 for our project
#define SUNVOX_SAMPLE_RATE 48000         // Match our audio engine
#define SUNVOX_CHANNELS 2                // Stereo
#define SUNVOX_OUTPUT_MODULE 0           // Output module is always 0
#define SUNVOX_BASE_NOTE 60              // Middle C (C4)

// State
static int g_sunvox_initialized = 0;
static int g_section_patterns[MAX_SECTIONS]; // Pattern IDs for each section (-1 = not created)
static int g_sampler_modules[MAX_SAMPLE_SLOTS]; // Module IDs for each sample slot
static int g_song_mode = 0; // 0 = loop mode, 1 = song mode
static int g_current_section = 0; // Current section for loop mode
static int g_updating_timeline = 0; // Recursion guard for update_timeline

// Initialize SunVox engine
int sunvox_wrapper_init(void) {
    prnt("🎵 [SUNVOX] Initializing SunVox wrapper (NEW LIBRARY - Oct 14 2025)");
    
    // WORKAROUND for crash bug: Pre-create config files before sv_init()
    // SunVox's smisc_global_init() tries to load config files and crashes if they don't exist
    // when using USER_AUDIO_CALLBACK mode
    #ifdef __APPLE__
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = [paths firstObject];
    NSString *configPath = [docsDir stringByAppendingPathComponent:@"sunvox_dll_config.ini"];
    
    // Create empty config file if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        [@"" writeToFile:configPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        prnt("🔧 [SUNVOX] Created empty config file at: %s", [configPath UTF8String]);
    }
    #endif
    
    // Initialize SunVox in OFFLINE mode (USER_AUDIO_CALLBACK)
    // This disables SunVox's built-in audio - we'll manage it ourselves via miniaudio
    // This prevents double audio consumption and enables clean recording
    uint32_t flags = SV_INIT_FLAG_USER_AUDIO_CALLBACK | 
                     SV_INIT_FLAG_AUDIO_FLOAT32 | 
                     SV_INIT_FLAG_ONE_THREAD;
    
    int result = sv_init(NULL, SUNVOX_SAMPLE_RATE, SUNVOX_CHANNELS, flags);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to initialize SunVox: %d", result);
        return -1;
    }
    
    prnt("✅ [SUNVOX] sv_init succeeded in OFFLINE mode (USER_AUDIO_CALLBACK)");
    
    // Open slot 0 for our project
    result = sv_open_slot(SUNVOX_SLOT);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to open slot: %d", result);
        sv_deinit();
        return -1;
    }
    
    prnt("✅ [SUNVOX] sv_open_slot succeeded");
    
    // Enable supertracks mode - required for NO_NOTES_OFF flag to work properly
    sv_lock_slot(SUNVOX_SLOT);
    result = sv_enable_supertracks(SUNVOX_SLOT, 1);
    sv_unlock_slot(SUNVOX_SLOT);
    
    if (result == 0) {
        prnt("✅ [SUNVOX] Supertracks mode enabled (required for seamless looping)");
    } else {
        prnt_err("⚠️ [SUNVOX] Failed to enable supertracks mode: %d", result);
        prnt_err("❌ [SUNVOX] Without supertracks, seamless looping will NOT work!");
    }
    
    // Check if SunVox created any default patterns
    int num_pattern_slots = sv_get_number_of_patterns(SUNVOX_SLOT);
    
    int actual_patterns = 0;
    for (int i = 0; i < num_pattern_slots; i++) {
        int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
        if (lines > 0) {
            actual_patterns++;
            const char* name = sv_get_pattern_name(SUNVOX_SLOT, i);
            int tracks = sv_get_pattern_tracks(SUNVOX_SLOT, i);
            int x = sv_get_pattern_x(SUNVOX_SLOT, i);
            int y = sv_get_pattern_y(SUNVOX_SLOT, i);
            prnt("🔧   Default pattern %d: \"%s\" - %d x %d lines, position (%d, %d)", 
                 i, name ? name : "???", tracks, lines, x, y);
        }
    }
    
    if (actual_patterns > 0) {
        prnt("⚠️ [SUNVOX] WARNING: SunVox created %d default pattern(s)!", actual_patterns);
        prnt("🗑️ [SUNVOX] Deleting default patterns to start clean...");
        
        // Delete all default patterns
        sv_lock_slot(SUNVOX_SLOT);
        for (int i = 0; i < num_pattern_slots; i++) {
            int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
            if (lines > 0) {
                prnt("🗑️ [SUNVOX] Deleting default pattern %d", i);
                sv_remove_pattern(SUNVOX_SLOT, i);
            }
        }
        sv_unlock_slot(SUNVOX_SLOT);
        
        prnt("✅ [SUNVOX] Deleted all default patterns");
    } else {
        prnt("✅ [SUNVOX] No default patterns, starting clean");
    }
    
    // Initialize arrays
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        g_sampler_modules[i] = -1; // No module yet
    }
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1; // No pattern yet
    }
    
    // Create sampler modules for each sample slot
    // These will be connected to the output
    sv_lock_slot(SUNVOX_SLOT);
    
    for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
        // Create sampler module
        // Position them in a grid for visual clarity (if we ever need to inspect)
        int x = 100 + (i % 8) * 100;
        int y = 100 + (i / 8) * 100;
        
        char name[32];
        snprintf(name, sizeof(name), "Sampler%d", i);
        
        int mod_id = sv_new_module(SUNVOX_SLOT, "Sampler", name, x, y, 0);
        if (mod_id < 0) {
            prnt_err("❌ [SUNVOX] Failed to create sampler %d: %d", i, mod_id);
            sv_unlock_slot(SUNVOX_SLOT);
            sunvox_wrapper_cleanup();
            return -1;
        }
        
        g_sampler_modules[i] = mod_id;
        
        // Connect sampler to output
        result = sv_connect_module(SUNVOX_SLOT, mod_id, SUNVOX_OUTPUT_MODULE);
        if (result < 0) {
            prnt_err("❌ [SUNVOX] Failed to connect sampler %d to output: %d", i, result);
        }
        
        prnt("✅ [SUNVOX] Created sampler %d (module %d)", i, mod_id);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // Patterns will be created on-demand as sections are added
    // (via sunvox_wrapper_create_section_pattern)
    
    // Set autostop off (patterns will loop automatically)
    sv_set_autostop(SUNVOX_SLOT, 0);

    // Get initial BPM
    int initial_bpm = sv_get_song_bpm(SUNVOX_SLOT);
    
    g_sunvox_initialized = 1;
    return 0;
}

// Cleanup SunVox engine
void sunvox_wrapper_cleanup(void) {
    if (!g_sunvox_initialized) return;
    
    prnt("🧹 [SUNVOX] Cleaning up");
    
    // Stop playback
    sv_stop(SUNVOX_SLOT);
    
    // Close slot
    sv_close_slot(SUNVOX_SLOT);
    
    // Deinit SunVox
    sv_deinit();
    
    g_sunvox_initialized = 0;
    
    // Clear section patterns array
    for (int i = 0; i < MAX_SECTIONS; i++) {
        g_section_patterns[i] = -1;
    }
    
    prnt("✅ [SUNVOX] Cleanup complete");
}

// Load a sample into a SunVox sampler module
int sunvox_wrapper_load_sample(int sample_slot, const char* file_path) {
    if (!g_sunvox_initialized) {
        prnt_err("❌ [SUNVOX] Not initialized");
        return -1;
    }
    
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) {
        prnt_err("❌ [SUNVOX] Invalid sample slot: %d", sample_slot);
        return -1;
    }
    
    int mod_id = g_sampler_modules[sample_slot];
    if (mod_id < 0) {
        prnt_err("❌ [SUNVOX] No sampler module for slot %d", sample_slot);
        return -1;
    }
    
    prnt("📂 [SUNVOX] Loading sample %d: %s", sample_slot, file_path);
    
    // Lock slot for sample loading
    sv_lock_slot(SUNVOX_SLOT);
    
    // Load sample into sampler (sample_slot -1 means replace entire sampler)
    int result = sv_sampler_load(SUNVOX_SLOT, mod_id, file_path, -1);
    if (result < 0) {
        sv_unlock_slot(SUNVOX_SLOT);
        prnt_err("❌ [SUNVOX] Failed to load sample into sampler %d: %d", sample_slot, result);
        return -1;
    }
    
    // Verify the module flags
    uint32_t flags = sv_get_module_flags(SUNVOX_SLOT, mod_id);
    prnt("🔍 [SUNVOX] Module %d flags: 0x%X (exists=%d, generator=%d)", 
         mod_id, flags, (flags & SV_MODULE_FLAG_EXISTS) != 0, (flags & SV_MODULE_FLAG_GENERATOR) != 0);
    
    // Set sampler volume to maximum
    int vol_ctl = sv_get_module_ctl_value(SUNVOX_SLOT, mod_id, 4, 0); // Controller 4 = Volume
    prnt("🔊 [SUNVOX] Module %d current volume: %d", mod_id, vol_ctl);
    sv_set_module_ctl_value(SUNVOX_SLOT, mod_id, 4, 256, 0); // Set to max (256)
    prnt("🔊 [SUNVOX] Module %d volume set to 256", mod_id);
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    prnt("✅ [SUNVOX] Loaded sample %d into module %d", sample_slot, mod_id);
    return 0;
}

// Unload a sample from a SunVox sampler module
void sunvox_wrapper_unload_sample(int sample_slot) {
    if (!g_sunvox_initialized) return;
    
    if (sample_slot < 0 || sample_slot >= MAX_SAMPLE_SLOTS) {
        return;
    }
    
    int mod_id = g_sampler_modules[sample_slot];
    if (mod_id < 0) return;
    
    prnt("🗑️ [SUNVOX] Unloading sample %d (module %d)", sample_slot, mod_id);
    
    // Clear the sampler by loading an empty sample
    // TODO: Find better way to clear sampler
}

// Sync single cell to SunVox pattern
void sunvox_wrapper_sync_cell(int step, int col) {
    if (!g_sunvox_initialized) return;
    
    // Find which section this step belongs to
    int section_index = table_get_section_at_step(step);
    if (section_index < 0 || section_index >= MAX_SECTIONS) {
        prnt_err("❌ [SUNVOX] Invalid section index for step %d", step);
        return;
    }
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) {
        prnt_err("❌ [SUNVOX] Pattern doesn't exist for section %d (step %d) - was playback_init() called?", 
                 section_index, step);
        return;
    }
    
    // Convert global step to local line within section
    int section_start = table_get_section_start_step(section_index);
    int local_line = step - section_start;
    
    Cell* cell = table_get_cell(step, col);
    if (!cell) return;
    
    sv_lock_slot(SUNVOX_SLOT);
    
    if (cell->sample_slot >= 0 && cell->sample_slot < MAX_SAMPLE_SLOTS) {
        // Cell has a sample - write note event
        int mod_id = g_sampler_modules[cell->sample_slot];
        if (mod_id >= 0) {
            // Resolve volume from cell or sample settings
            float volume = cell->settings.volume;
            if (volume == DEFAULT_CELL_VOLUME) {
                Sample* s = sample_bank_get_sample(cell->sample_slot);
                volume = (s && s->loaded) ? s->settings.volume : 1.0f;
            }
            
            // Convert volume (0..1) to velocity (1..128)
            int velocity = (int)(volume * 128.0f);
            if (velocity < 1) velocity = 1;
            if (velocity > 128) velocity = 128;

            // Resolve pitch from cell or sample settings
            float pitch = cell->settings.pitch;
            if (pitch == DEFAULT_CELL_PITCH) {
                Sample* s = sample_bank_get_sample(cell->sample_slot);
                pitch = (s && s->loaded) ? s->settings.pitch : 1.0f;
            }

            // Guard against non-positive pitch values for log2f
            if (pitch <= 0.0f) {
                pitch = 1.0f;
            }

            // Convert pitch ratio to semitones
            float semitones = 12.0f * log2f(pitch);
            int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
            if (final_note < 0) final_note = 0;
            if (final_note > 127) final_note = 127;
            
            int result = sv_set_pattern_event(
                SUNVOX_SLOT,
                pat_id,              // section's pattern
                col,                 // track
                local_line,          // line within pattern
                final_note,          // note
                velocity,            // velocity
                mod_id + 1,          // module (1-indexed)
                0,                   // no controller/effect
                0                    // no parameter
            );
            
            if (result == 0) {
                prnt("📝 [SUNVOX] Set pattern event [section=%d, line=%d, col=%d]: note=%d, vel=%d, mod=%d",
                     section_index, local_line, col, final_note, velocity, mod_id + 1);
            } else {
                prnt_err("❌ [SUNVOX] Failed to set pattern event: %d", result);
            }
        }
    } else {
        // Empty cell - clear event
        sv_set_pattern_event(
            SUNVOX_SLOT,
            pat_id,
            col,
            local_line,
            0, 0, 0, 0, 0
        );
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
}

// Sync entire table to SunVox pattern
// Create a pattern for a section
int sunvox_wrapper_create_section_pattern(int section_index, int section_length) {
    if (!g_sunvox_initialized) return -1;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return -1;
    
    
    // Check if playback is active BEFORE any modifications
    int was_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    // If pattern already exists, remove it first
    if (g_section_patterns[section_index] >= 0) {
        sunvox_wrapper_remove_section_pattern(section_index);
    }
    
    sv_lock_slot(SUNVOX_SLOT);
    
    int max_cols = table_get_max_cols();
    
    char name[32];
    snprintf(name, sizeof(name), "Section%d", section_index);
    
    
    int pat_id = sv_new_pattern(
        SUNVOX_SLOT,
        -1,              // clone = -1 (create new)
        0,               // x position (will be set via timeline)
        section_index,   // y position (for visual ordering)
        max_cols,        // tracks = columns
        section_length,  // lines = section length
        0,               // icon seed
        name             // name
    );
    
    if (pat_id < 0) {
        prnt_err("❌ [SUNVOX] Failed to create pattern for section %d: %d", section_index, pat_id);
        sv_unlock_slot(SUNVOX_SLOT);
        return -1;
    }
    
    g_section_patterns[section_index] = pat_id;
    
    // Verify pattern was created with correct size
    int actual_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
    int actual_tracks = sv_get_pattern_tracks(SUNVOX_SLOT, pat_id);
    
    prnt("✅ [SUNVOX] Created pattern %d for section %d (requested: %d x %d, actual: %d x %d)", 
         pat_id, section_index, max_cols, section_length, actual_tracks, actual_lines);
    
    // Force pattern size if SunVox rounded it
    if (actual_lines != section_length || actual_tracks != max_cols) {
        prnt("⚠️ [SUNVOX] Pattern size mismatch, forcing to %d x %d", max_cols, section_length);
        sv_set_pattern_size(SUNVOX_SLOT, pat_id, max_cols, section_length);
        
        // Verify again
        actual_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
        actual_tracks = sv_get_pattern_tracks(SUNVOX_SLOT, pat_id);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    
    // CRITICAL FIX: Set NO_NOTES_OFF flag to prevent samples from being cut off at loop boundary
    // This allows seamless looping - notes continue playing when pattern wraps around
    sv_lock_slot(SUNVOX_SLOT);
    int result = sv_pattern_set_flags(SUNVOX_SLOT, pat_id, SV_PATTERN_FLAG_NO_NOTES_OFF, 1);
    sv_unlock_slot(SUNVOX_SLOT);
    
    if (result == 0) {
        prnt("✅ [SUNVOX] Set NO_NOTES_OFF flag on pattern %d for seamless looping", pat_id);
    } else {
        prnt_err("❌ [SUNVOX] Failed to set NO_NOTES_OFF flag on pattern %d (error: %d)", pat_id, result);
    }
    
    // Sync section content to pattern
    sunvox_wrapper_sync_section(section_index);
    
    
    // Update timeline (unless we're already updating it - prevent recursion)
    if (!g_updating_timeline) {
        sunvox_wrapper_update_timeline();
        
        // If playback was active, restart it to apply new timeline
        if (was_playing) {
            prnt("🔄 [SUNVOX] Restarting playback to apply new pattern size");
            sv_stop(SUNVOX_SLOT);
            sv_rewind(SUNVOX_SLOT, 0);
            sv_play(SUNVOX_SLOT);
        }
    }
    
    return 0;
}

// Remove a pattern for a section
void sunvox_wrapper_remove_section_pattern(int section_index) {
    if (!g_sunvox_initialized) return;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return; // No pattern to remove
    
    sv_lock_slot(SUNVOX_SLOT);
    sv_remove_pattern(SUNVOX_SLOT, pat_id);
    sv_unlock_slot(SUNVOX_SLOT);
    
    g_section_patterns[section_index] = -1;
    prnt("🗑️ [SUNVOX] Removed pattern for section %d", section_index);
    
    // Update timeline
    sunvox_wrapper_update_timeline();
}

// Sync entire section to its pattern
void sunvox_wrapper_sync_section(int section_index) {
    if (!g_sunvox_initialized) return;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return; // Pattern doesn't exist
    
    int section_start = table_get_section_start_step(section_index);
    int section_length = table_get_section_step_count(section_index);
    int max_cols = table_get_max_cols();
    
    prnt("🔄 [SUNVOX] Syncing section %d (start=%d, length=%d)", 
         section_index, section_start, section_length);
    
    for (int local_line = 0; local_line < section_length; local_line++) {
        int global_step = section_start + local_line;
        for (int col = 0; col < max_cols; col++) {
            // Sync this cell
            Cell* cell = table_get_cell(global_step, col);
            
            sv_lock_slot(SUNVOX_SLOT);
            
            if (!cell || cell->sample_slot == -1) {
                // Empty cell - clear pattern event
                sv_set_pattern_event(SUNVOX_SLOT, pat_id, col, local_line, 
                                    0, 0, 0, 0, 0);
            } else {
                // Set note event
                int mod_id = g_sampler_modules[cell->sample_slot];
                if (mod_id >= 0) {
                    float volume = (cell->settings.volume == DEFAULT_CELL_VOLUME) 
                        ? sample_bank_get_sample(cell->sample_slot)->settings.volume 
                        : cell->settings.volume;
                    int velocity = (int)(volume * 128.0f);
                    if (velocity < 1) velocity = 1;
                    if (velocity > 128) velocity = 128;
                    
                    // Resolve pitch
                    float pitch = (cell->settings.pitch == DEFAULT_CELL_PITCH)
                        ? sample_bank_get_sample(cell->sample_slot)->settings.pitch
                        : cell->settings.pitch;
                    
                    // Guard for log2f
                    if (pitch <= 0.0f) {
                        pitch = 1.0f;
                    }
                    // Convert pitch ratio to semitones
                    float semitones = 12.0f * log2f(pitch);
                    int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
                    if (final_note < 0) final_note = 0;
                    if (final_note > 127) final_note = 127;

                    sv_set_pattern_event(
                        SUNVOX_SLOT, 
                        pat_id, 
                        col, 
                        local_line, 
                        final_note,        // note
                        velocity,          // velocity
                        mod_id + 1,        // module
                        0,                 // no controller
                        0                  // no controller value
                    );
                }
            }
            
            sv_unlock_slot(SUNVOX_SLOT);
        }
    }
    
    prnt("✅ [SUNVOX] Section %d sync complete", section_index);
}

// Set playback mode and update timeline
void sunvox_wrapper_set_playback_mode(int song_mode, int current_section, int current_loop) {
    int mode_changed = (g_song_mode != song_mode);
    int was_loop_mode = !g_song_mode;
    
    g_song_mode = song_mode;
    g_current_section = current_section;
    
    // ===== NO-CLONE SOLUTION: Use pattern loop counting =====
    
    if (song_mode) {
        // Song mode: Setup pattern sequence and loop counts
        prnt("🎵 [SUNVOX] Entering SONG MODE");
        
        // Get sections and their loop counts from playback state
        const PlaybackState* pb_state = playback_get_state_ptr();
        int sections_count = table_get_sections_count();
        
        // Build pattern sequence array
        int pattern_sequence[64];
        int seq_count = 0;
        
        for (int i = 0; i < sections_count && seq_count < 64; i++) {
            int pat_id = g_section_patterns[i];
            if (pat_id < 0) continue;
            
            int loops = pb_state ? pb_state->sections_loops_num_storage[i] : 1;
            
            // Set loop count for this pattern
            sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, loops);
            prnt("  📍 [SUNVOX] Pattern %d (section %d): %d loops", pat_id, i, loops);
            
            // Add to sequence
            pattern_sequence[seq_count++] = pat_id;
        }
        
        sv_set_pattern_sequence(SUNVOX_SLOT, pattern_sequence, seq_count);
        prnt("  📋 [SUNVOX] Pattern sequence: %d patterns", seq_count);
        
        // Find the pattern corresponding to the *current_section* to start from.
        int start_pat = -1;
        if (current_section >= 0 && current_section < sections_count) {
            start_pat = g_section_patterns[current_section];
        }

        // Fallback to the first pattern in the sequence if the current section has no pattern.
        if (start_pat < 0 && seq_count > 0) {
            start_pat = pattern_sequence[0];
        }

        if (start_pat >= 0) {
            sv_set_pattern_loop(SUNVOX_SLOT, start_pat);
            sv_set_autostop(SUNVOX_SLOT, 1);
            prnt("  ▶️ [SUNVOX] Starting song mode from pattern %d (section %d)", start_pat, current_section);
        }
    } else {
        // Loop mode: Enable infinite loop for current section
        prnt("🔁 [SUNVOX] Entering LOOP MODE (section %d)", current_section);
        
        int pat_id = g_section_patterns[current_section];
        if (pat_id >= 0) {
            // CRITICAL FIX: Clear pattern sequence to prevent advancement
            prnt("  🗑️ [SUNVOX] Clearing pattern sequence for loop mode");
            int empty_sequence[1] = {pat_id};
            sv_set_pattern_sequence(SUNVOX_SLOT, empty_sequence, 1);
            
            // Set infinite loop (0 = infinite)
            sv_set_pattern_loop_count(SUNVOX_SLOT, pat_id, 0);
            prnt("  ⚙️ [SUNVOX] Set pattern %d loop_count=0 (infinite)", pat_id);
            
            // Calculate seamless position if switching from song mode
            int current_line = sv_get_current_line(SUNVOX_SLOT);
            int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
            int pat_x = sv_get_pattern_x(SUNVOX_SLOT, pat_id);
            
            int offset_from_start = current_line - pat_x;
            int local_offset = offset_from_start % pat_lines;
            int target_line = pat_x + local_offset;
            
            if (mode_changed && !was_loop_mode) {
                // CRITICAL: Set position FIRST, then enable pattern loop
                prnt("  🔄 [SUNVOX] Setting position to line %d (step %d within pattern)", 
                     target_line, local_offset);
                sv_set_position(SUNVOX_SLOT, target_line);
            }
            
            // Enable pattern loop (playhead is now in valid range)
            sv_set_pattern_loop(SUNVOX_SLOT, pat_id);
            sv_set_autostop(SUNVOX_SLOT, 0);  // Infinite loop
            prnt("  🔁 [SUNVOX] Looping pattern %d infinitely", pat_id);
        }
    }
}

// Update timeline with current section order
// NEW: Always use song mode layout (all patterns + clones)
// Mode switching handled by sv_set_pattern_loop(), NOT by rebuilding timeline!
void sunvox_wrapper_update_timeline(void) {
    if (!g_sunvox_initialized) return;
    
    // Prevent recursion
    if (g_updating_timeline) {
        prnt("⚠️ [SUNVOX] update_timeline called recursively, skipping");
        return;
    }
    g_updating_timeline = 1;
    
    int sections_count = table_get_sections_count();
    
    // Check if playback is active
    int was_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    // Stop playback before timeline rebuild to avoid glitches
    // (Note: This only happens during initial setup or section structure changes,
    //  NOT during mode switching which is now seamless!)
    if (was_playing) {
        prnt("⏸️ [SUNVOX] Stopping playback for timeline rebuild");
        sv_stop(SUNVOX_SLOT);
    }
    
    // ===== NO-CLONE APPROACH: Simple linear layout =====
    // One pattern per section, placed sequentially
    // Loop counting is handled in SunVox engine via sv_set_pattern_loop_count()
    prnt("📋 [SUNVOX] Building simple timeline: %d sections (NO CLONES)", sections_count);
    
    sv_lock_slot(SUNVOX_SLOT);
    
    // Layout patterns sequentially
    int timeline_x = 0;
    for (int i = 0; i < sections_count; i++) {
        int pat_id = g_section_patterns[i];
        if (pat_id < 0) continue;
        
        int pat_lines = sv_get_pattern_lines(SUNVOX_SLOT, pat_id);
        
        // Place pattern at current X position
        sv_set_pattern_xy(SUNVOX_SLOT, pat_id, timeline_x, i);
        prnt("  📍 [SUNVOX] Section %d: Pattern %d at x=%d (%d lines)", 
             i, pat_id, timeline_x, pat_lines);
        
        timeline_x += pat_lines;
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
    prnt("✅ [SUNVOX] Simple timeline built: %d lines total (0 clones)", timeline_x);
    
    g_updating_timeline = 0;
    
    
    // Always rewind to beginning after timeline rebuild
    sv_rewind(SUNVOX_SLOT, 0);
    
    if (was_playing) {
        // Resume playback from beginning
        prnt("▶️ [SUNVOX] Restarting playback from beginning (timeline rebuild)");
        sv_play(SUNVOX_SLOT);
        
    } else {
        // Playback was stopped
        prnt("⏮️ [SUNVOX] Rewound to beginning (playback stopped)");
    }
}

// Start playback
int sunvox_wrapper_play(void) {
    if (!g_sunvox_initialized) {
        prnt_err("❌ [SUNVOX] Not initialized");
        return -1;
    }
    
    prnt("▶️ [SUNVOX] Starting playback from current position");
    
    // Debug: Check audio status
    int audio_callback = sv_get_sample_rate();
    prnt("🔊 [SUNVOX] Audio sample rate: %d Hz", audio_callback);
    
    // Debug: Check module volume and mute status
    for (int i = 0; i < 3; i++) {
        int mod_id = g_sampler_modules[i];
        if (mod_id >= 0) {
            uint32_t flags = sv_get_module_flags(SUNVOX_SLOT, mod_id);
            int muted = (flags & SV_MODULE_FLAG_MUTE) != 0;
            prnt("🔍 [SUNVOX] Module %d: exists=%d, muted=%d", 
                 mod_id, (flags & SV_MODULE_FLAG_EXISTS) != 0, muted);
        }
    }
    
    // Use sv_play() to start from current position (set by sv_rewind)
    int result = sv_play(SUNVOX_SLOT);
    if (result < 0) {
        prnt_err("❌ [SUNVOX] Failed to start playback: %d", result);
        return -1;
    }
    
    // Verify playback status
    int status = sv_end_of_song(SUNVOX_SLOT);
    prnt("🎵 [SUNVOX] Playback status after start: %d (0=playing)", status);
    
    return 0;
}

// Stop playback
void sunvox_wrapper_stop(void) {
    if (!g_sunvox_initialized) return;
    
    prnt("⏹️ [SUNVOX] Stopping playback");
    sv_stop(SUNVOX_SLOT);
}

// Set BPM
void sunvox_wrapper_set_bpm(int bpm) {
    if (!g_sunvox_initialized) return;
    
    // SunVox BPM is set via the project's BPM controller
    // We need to find the "BPM" module controller or send a BPM command
    // For simplicity, we'll send it as an event to the output module
    
    prnt("🎵 [SUNVOX] Setting BPM to %d", bpm);
    
    // TODO: Set BPM properly via sv_set_module_ctl_value or by modifying project settings
    // For now, this is a placeholder
}

// Set playback region (loop range)
void sunvox_wrapper_set_region(int start, int end) {
    if (!g_sunvox_initialized) return;
    
    prnt("🎭 [SUNVOX] Setting region: %d to %d", start, end);
    
    // Stop all currently playing notes by sending note-off to all samplers
    // Only needed if playback is active
    int is_playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
    
    if (is_playing) {
        sv_lock_slot(SUNVOX_SLOT);
        
        int max_cols = table_get_max_cols();
        for (int track = 0; track < max_cols; track++) {
            for (int i = 0; i < MAX_SAMPLE_SLOTS; i++) {
                int mod_id = g_sampler_modules[i];
                if (mod_id >= 0) {
                    // Send note-off event to this sampler on this track
                    // sv_send_event(slot, track, note, vel, module, ctl, ctl_val)
                    // note=128 (NOTE_OFF), module=sampler module ID + 1
                    sv_send_event(SUNVOX_SLOT, track, 128, 0, mod_id + 1, 0, 0);
                }
            }
        }
        
        sv_unlock_slot(SUNVOX_SLOT);
        
        prnt("🔇 [SUNVOX] Stopped all playing notes for region change");
    }
}

// Get current playback line/step
int sunvox_wrapper_get_current_line(void) {
    if (!g_sunvox_initialized) return -1;
    
    return sv_get_current_line(SUNVOX_SLOT);
}

// Get pattern X position for a section (for calculating local position in loop mode)
int sunvox_wrapper_get_section_pattern_x(int section_index) {
    if (!g_sunvox_initialized) return 0;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return 0;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return 0;
    
    return sv_get_pattern_x(SUNVOX_SLOT, pat_id);
}

// Trigger notes at a specific step
void sunvox_wrapper_trigger_step(int step) {
    if (!g_sunvox_initialized) return;
    
    prnt("🎯 [SUNVOX] Triggering notes at step %d", step);
    
    sv_lock_slot(SUNVOX_SLOT);
    
    int max_cols = table_get_max_cols();
    for (int col = 0; col < max_cols; col++) {
        Cell* cell = table_get_cell(step, col);
        if (!cell || cell->sample_slot == -1) {
            continue; // Empty cell
        }
        
        int mod_id = g_sampler_modules[cell->sample_slot];
        if (mod_id < 0) {
            continue; // Sample not loaded
        }
        
        // Calculate velocity
        float volume = (cell->settings.volume == DEFAULT_CELL_VOLUME) 
            ? sample_bank_get_sample(cell->sample_slot)->settings.volume 
            : cell->settings.volume;
        int velocity = (int)(volume * 128.0f);
        if (velocity < 1) velocity = 1;
        if (velocity > 128) velocity = 128;
        
        // Resolve and convert pitch to note
        float pitch = (cell->settings.pitch == DEFAULT_CELL_PITCH)
            ? sample_bank_get_sample(cell->sample_slot)->settings.pitch
            : cell->settings.pitch;
        
        if (pitch <= 0.0f) {
            pitch = 1.0f;
        }
        float semitones = 12.0f * log2f(pitch);
        int final_note = SUNVOX_BASE_NOTE + (int)roundf(semitones);
        if (final_note < 0) final_note = 0;
        if (final_note > 127) final_note = 127;

        // Send note-on event
        // sv_send_event(slot, track, note, vel, module, ctl, ctl_val)
        sv_send_event(
            SUNVOX_SLOT,        // slot
            col,                // track/column
            final_note,         // note
            velocity,           // velocity
            mod_id + 1,         // module (sampler ID + 1)
            0,                  // no controller
            0                   // no controller value
        );
        
        prnt("🎵 [SUNVOX] Triggered note [step=%d, col=%d]: mod=%d, vel=%d, note=%d", 
             step, col, mod_id, velocity, final_note);
    }
    
    sv_unlock_slot(SUNVOX_SLOT);
}

// Render audio frames (called from audio callback)
int sunvox_wrapper_render(float* buf, int frames) {
    if (!g_sunvox_initialized) return 0;
    
    // Call SunVox audio callback to render audio
    uint32_t out_time = sv_get_ticks();
    return sv_audio_callback(buf, frames, 0, out_time);
}

// Check if SunVox is initialized
int sunvox_wrapper_is_initialized(void) {
    return g_sunvox_initialized;
}

// Debug: Dump all pattern information (disabled to reduce log noise)
// void sunvox_wrapper_debug_dump_patterns(const char* context) {
//     if (!g_sunvox_initialized) return;
//
//     prnt("🔍 [SUNVOX DEBUG DUMP] ========== %s ==========", context);
//
//     // Get number of pattern slots from SunVox
//     int num_pattern_slots = sv_get_number_of_patterns(SUNVOX_SLOT);
//     prnt("🔍 [SUNVOX DEBUG] SunVox has %d pattern slots", num_pattern_slots);
//
//     // List all patterns that exist (slots that contain patterns)
//     int actual_patterns = 0;
//     for (int i = 0; i < num_pattern_slots; i++) {
//         int lines = sv_get_pattern_lines(SUNVOX_SLOT, i);
//         if (lines > 0) {
//             actual_patterns++;
//             int tracks = sv_get_pattern_tracks(SUNVOX_SLOT, i);
//             int x = sv_get_pattern_x(SUNVOX_SLOT, i);
//             int y = sv_get_pattern_y(SUNVOX_SLOT, i);
//             const char* name = sv_get_pattern_name(SUNVOX_SLOT, i);
//
//             prnt("🔍   Pattern %d: \"%s\" - %d x %d lines, position (%d, %d)",
//                  i, name ? name : "???", tracks, lines, x, y);
//         }
//     }
//     prnt("🔍 [SUNVOX DEBUG] %d actual patterns exist (out of %d slots)", actual_patterns, num_pattern_slots);
//
//     // Show our mapping
//     prnt("🔍 [SUNVOX DEBUG] Our section->pattern mapping:");
//     for (int i = 0; i < MAX_SECTIONS; i++) {
//         if (g_section_patterns[i] >= 0) {
//             int lines = sv_get_pattern_lines(SUNVOX_SLOT, g_section_patterns[i]);
//             prnt("🔍   Section %d -> Pattern %d (%d lines)", i, g_section_patterns[i], lines);
//         }
//     }
//
//     // Get song length
//     int song_length = sv_get_song_length_lines(SUNVOX_SLOT);
//     prnt("🔍 [SUNVOX DEBUG] Song length (from sv_get_song_length_lines): %d lines", song_length);
//
//     // Get current line
//     int current_line = sv_get_current_line(SUNVOX_SLOT);
//     prnt("🔍 [SUNVOX DEBUG] Current playback line: %d", current_line);
//
//     // Get autostop setting
//     int autostop = sv_get_autostop(SUNVOX_SLOT);
//     prnt("🔍 [SUNVOX DEBUG] Autostop: %d (0=loop, 1=stop at end)", autostop);
//
//     // Get playback status
//     int playing = (sv_end_of_song(SUNVOX_SLOT) == 0);
//     prnt("🔍 [SUNVOX DEBUG] Playing: %s", playing ? "YES" : "NO");
//
//     prnt("🔍 [SUNVOX DEBUG] ================================");
// }

int sunvox_wrapper_get_pattern_current_loop(int section_index) {
    if (!g_sunvox_initialized) return 0;
    if (section_index < 0 || section_index >= MAX_SECTIONS) return 0;
    
    int pat_id = g_section_patterns[section_index];
    if (pat_id < 0) return 0;
    
    return sv_get_pattern_current_loop(SUNVOX_SLOT, pat_id);
}

