/* Minimal config.h for LAME on iOS/macOS/Android */
#ifndef CONFIG_H
#define CONFIG_H

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <math.h> header file. */
#define HAVE_MATH_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* IEEE754 floating point */
#define IEEE754_FLOAT32 1

/* IEEE754 float32 type */
typedef float ieee754_float32_t;

/* LAME version */
#define LAME_MAJOR_VERSION 3
#define LAME_MINOR_VERSION 100
#define LAME_PATCH_VERSION 0

/* Package info */
#define PACKAGE_NAME "lame"
#define PACKAGE_VERSION "3.100"

/* Use IEEE754 */
#define TAKEHIRO_IEEE754_HACK 1

/* Compiler supports NASM */
#ifdef __i386__
#define HAVE_NASM 1
#define MMX_choose_table 1
#endif

/* Apple/iOS specific */
#ifdef __APPLE__
#define HAVE_TERMCAP 1
#endif

/* Function compatibility */
#define HAVE_MEMSET 1
#define HAVE_MEMMOVE 1
#define HAVE_STRCHR 1

/* Disable assembly optimizations for Android */
#undef HAVE_NASM
#undef MMX_choose_table

/* Disable CPU feature detection and optimizations */
#define HAVE_NASM 0

/* Disable all x86 assembly optimizations */
#undef HAVE_XMMINTRIN_H
#undef HAVE_IMMINTRIN_H

/* Missing function compatibility macros */
// #define bcopy(src, dst, len) memmove(dst, src, len)

#endif /* CONFIG_H */ 