cmake_minimum_required(VERSION 3.10)
project(miniaudio_wrapper LANGUAGES C CXX)

set(SOURCES
  miniaudio_wrapper.mm
  lame_wrapper.mm
  # LAME source files
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

set_source_files_properties(
  miniaudio_wrapper.mm
  lame_wrapper.mm
  PROPERTIES
  LANGUAGE CXX
  COMPILE_FLAGS "-x c++"
)
# Define necessary macros
add_definitions(-DMA_NO_AAUDIO)
add_definitions(-DHAVE_CONFIG_H)

# Include directories for LAME
include_directories(lame)

add_library(miniaudio SHARED ${SOURCES})

if(ANDROID)
  target_link_libraries(miniaudio OpenSLES log)
endif()