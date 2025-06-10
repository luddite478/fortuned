cmake_minimum_required(VERSION 3.10)
project(miniaudio_wrapper LANGUAGES C CXX)

set(SOURCES
  miniaudio_wrapper.mm
  # add other sources if needed
)

set_source_files_properties(
  miniaudio_wrapper.mm
  PROPERTIES
  LANGUAGE CXX
  COMPILE_FLAGS "-x c++"
)
add_definitions(-DMA_NO_AAUDIO)
add_library(miniaudio SHARED ${SOURCES})

if(ANDROID)
  target_link_libraries(miniaudio OpenSLES log)
endif()