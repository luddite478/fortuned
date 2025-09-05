/* 
 * LAME Prefix Header - automatically included for all LAME source files
 * This ensures all standard library functions are available without modifying LAME sources
 */

#ifndef LAME_PREFIX_H
#define LAME_PREFIX_H

// Include all standard headers that LAME needs
#include <stdio.h>
#include <stdlib.h>    // malloc, free, calloc, exit
#include <string.h>    // memset, strlen, strcpy, etc.
#include <strings.h>   // bcopy on macOS/BSD
#include <memory.h>    // memory functions
#include <unistd.h>    // POSIX functions
#include <stdint.h>    // integer types
#include <math.h>      // math functions

// Define missing functions for iOS/macOS compatibility
#ifndef bcopy
#define bcopy(src, dst, len) memmove(dst, src, len)
#endif

#endif /* LAME_PREFIX_H */ 