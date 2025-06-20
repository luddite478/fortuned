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

# Include directories
include_directories(lame)
include_directories(miniaudio)

# Create sequencer library (includes both sequencer and conversion functionality)
add_library(sequencer SHARED ${SEQUENCER_SOURCES})

if(ANDROID)
  target_link_libraries(sequencer OpenSLES log)
endif()