cmake_minimum_required(VERSION 3.10)
project(fortuned_native LANGUAGES C CXX)

# Ensure modern C++ for header-only libraries like nlohmann/json
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# SoundTouch configuration - default ON to support preprocessing in pitch module
option(USE_SOUNDTOUCH_PITCH "Use SoundTouch for high-quality pitch shifting" ON)

# SoundTouch source files (common)
set(SOUNDTOUCH_COMMON_SOURCES
  soundtouch/SoundTouch.cpp
  soundtouch/TDStretch.cpp
  soundtouch/RateTransposer.cpp
  soundtouch/FIRFilter.cpp
  soundtouch/AAFilter.cpp
  soundtouch/FIFOSampleBuffer.cpp
  soundtouch/InterpolateLinear.cpp
  soundtouch/InterpolateCubic.cpp
  soundtouch/InterpolateShannon.cpp
  soundtouch/PeakFinder.cpp
  soundtouch/BPMDetect.cpp
)

# Select SoundTouch CPU detection and SIMD sources per-ABI
set(SOUNDTOUCH_SOURCES ${SOUNDTOUCH_COMMON_SOURCES})

if(ANDROID)
  if(ANDROID_ABI STREQUAL "x86" OR ANDROID_ABI STREQUAL "x86_64")
    # Use x86 CPU detection and SSE optimizations for floating-point build
    list(APPEND SOUNDTOUCH_SOURCES
      soundtouch/cpu_detect_x86.cpp
      soundtouch/sse_optimized.cpp
    )
    add_definitions(-DSOUNDTOUCH_ALLOW_X86_OPTIMIZATIONS=1)
    add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-msse2>)
  else()
    # ARM ABIs use ARM CPU detection; NEON handled via generic code paths
    list(APPEND SOUNDTOUCH_SOURCES
      soundtouch/cpu_detect_arm.cpp
    )
  endif()
else()
  # Non-Android builds: prefer x86 detection on desktop
  list(APPEND SOUNDTOUCH_SOURCES soundtouch/cpu_detect_x86.cpp)
endif()

# LAME source files (shared between libraries)
set(LAME_SOURCES
  lame/lame.c
  lame/bitstream.c
  lame/encoder.c
  lame/fft.c
  lame/id3tag.c
  lame/newmdct.c
  lame/presets.c
  lame/psymodel.c
  lame/quantize.c
  lame/quantize_pvt.c
  lame/reservoir.c
  lame/set_get.c
  lame/tables.c
  lame/takehiro.c
  lame/util.c
  lame/vbrquantize.c
  lame/VbrTag.c
  lame/version.c
  lame/gain_analysis.c
)

# Sequencer library sources (includes conversion functionality)
set(SEQUENCER_SOURCES
  conversion.mm
  table.mm
  playback.mm
  miniaudio_impl.mm
  sample_bank.mm
  pitch.mm
  undo_redo.mm
  preview.mm
)

# Add SoundTouch sources if enabled
if(USE_SOUNDTOUCH_PITCH)
  list(APPEND SEQUENCER_SOURCES ${SOUNDTOUCH_SOURCES})
  message(STATUS "SoundTouch pitch shifting enabled (high quality)")
else()
  message(STATUS "miniaudio resampler pitch shifting enabled (fast)")
endif()

set_source_files_properties(
  conversion.mm
  table.mm
  playback.mm
  miniaudio_impl.mm
  sample_bank.mm
  pitch.mm
  undo_redo.mm
  preview.mm
  PROPERTIES
  LANGUAGE CXX
  COMPILE_FLAGS "-x c++"
)

# Set SoundTouch files as C++ if included
if(USE_SOUNDTOUCH_PITCH)
  set_source_files_properties(
    ${SOUNDTOUCH_SOURCES}
    PROPERTIES
    LANGUAGE CXX
  )
endif()

# Define necessary macros
add_definitions(-DMA_NO_AAUDIO)
add_definitions(-DHAVE_CONFIG_H)

# SoundTouch configuration
if(USE_SOUNDTOUCH_PITCH)
  add_definitions(-DUSE_SOUNDTOUCH_PITCH=1)
  add_definitions(-DSOUNDTOUCH_FLOAT_SAMPLES)  # Use floating point for better ARM64 performance
  add_definitions(-DSOUNDTOUCH_ALLOW_NONEXACT_SIMD_OPTIMIZATION)  # Enable ARM NEON optimizations
else()
  add_definitions(-DUSE_SOUNDTOUCH_PITCH=0)
endif()

# Disable NASM and assembly optimizations for Android
if(ANDROID)
  add_definitions(-DHAVE_NASM=0)
  add_definitions(-UMMX_choose_table)
endif()

# Include directories
if(ANDROID)
  include_directories(lame_android)
  list(APPEND SEQUENCER_SOURCES
    lame_android/lame.c
    lame_android/bitstream.c
    lame_android/encoder.c
    lame_android/fft.c
    lame_android/id3tag.c
    lame_android/newmdct.c
    lame_android/presets.c
    lame_android/psymodel.c
    lame_android/quantize.c
    lame_android/quantize_pvt.c
    lame_android/reservoir.c
    lame_android/set_get.c
    lame_android/tables.c
    lame_android/takehiro.c
    lame_android/util.c
    lame_android/vbrquantize.c
    lame_android/VbrTag.c
    lame_android/version.c
    lame_android/gain_analysis.c
    lame_android/nasm_stubs.c
  )
else()
  include_directories(lame)
  list(APPEND SEQUENCER_SOURCES ${LAME_SOURCES})
endif()

include_directories(miniaudio)

 

# Add SoundTouch include directory if enabled
if(USE_SOUNDTOUCH_PITCH)
  include_directories(soundtouch)
endif()

# Create sequencer library (includes both sequencer and conversion functionality)
add_library(sequencer SHARED ${SEQUENCER_SOURCES})

if(ANDROID)
  target_link_libraries(sequencer OpenSLES log android)
endif()