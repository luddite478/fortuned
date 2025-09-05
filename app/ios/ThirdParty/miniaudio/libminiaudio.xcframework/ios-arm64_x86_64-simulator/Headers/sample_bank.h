#ifndef SAMPLE_BANK_H
#define SAMPLE_BANK_H

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define MAX_SAMPLE_SLOTS 26  // A-Z sample slots

// Forward declarations
struct ma_decoder;

// Sample management
void sample_bank_init(void);
void sample_bank_cleanup(void);
int sample_bank_load(int slot, const char* file_path);
void sample_bank_unload(int slot);
int sample_bank_play(int slot);
void sample_bank_stop(int slot);
int sample_bank_is_loaded(int slot);
const char* sample_bank_get_file_path(int slot);
struct ma_decoder* sample_bank_get_decoder(int slot);

// For FFI
int sample_bank_get_max_slots(void);

#ifdef __cplusplus
}
#endif

#endif // SAMPLE_BANK_H
