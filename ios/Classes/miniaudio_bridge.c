#include "miniaudio.h"

// Declare the engine globally if you want shared state
static ma_engine engine;

void init_engine() {
    ma_result result = ma_engine_init(NULL, &engine);
    if (result != MA_SUCCESS) {
        // Handle error if you want
    }
}

void play_sample(const char* path) {
    ma_engine_play_sound(&engine, path, NULL);
}
