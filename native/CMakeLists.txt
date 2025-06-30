cmake_minimum_required(VERSION 3.10)
project(niyya_native LANGUAGES C CXX)

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
  sequencer.mm
  conversion.mm
)

set_source_files_properties(
  sequencer.mm
  conversion.mm
  PROPERTIES
  LANGUAGE CXX
  COMPILE_FLAGS "-x c++"
)

# Define necessary macros
add_definitions(-DMA_NO_AAUDIO)
add_definitions(-DHAVE_CONFIG_H)

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

# Create sequencer library (includes both sequencer and conversion functionality)
add_library(sequencer SHARED ${SEQUENCER_SOURCES})

if(ANDROID)
  target_link_libraries(sequencer OpenSLES log)
endif()