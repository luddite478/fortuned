/* NASM stub implementations for Android builds */
/* These functions provide fallback implementations when assembly optimizations are not available */

#include "machine.h"

/* FFT optimization stubs */
void fht_3DN(FLOAT *fz, int n) {
    /* Fallback to generic FFT - this function should not be called on Android */
}

void fht_SSE(FLOAT *fz, int n) {
    /* Fallback to generic FFT - this function should not be called on Android */
}

/* CPU feature detection stubs - always return 0 (feature not available) */
int has_MMX_nasm(void) {
    return 0;
}

int has_3DNow_nasm(void) {
    return 0;
}

int has_SSE_nasm(void) {
    return 0;
}

int has_SSE2_nasm(void) {
    return 0;
}

/* MMX optimized table selection stub */
void choose_table_MMX(const unsigned int *ix, const unsigned char *end_pos, int *s) {
    /* Fallback to generic implementation - this function should not be called on Android */
} 