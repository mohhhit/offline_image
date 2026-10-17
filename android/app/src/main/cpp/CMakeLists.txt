cmake_minimum_required(VERSION 3.22.1)
project("stable_diffusion_bridge" LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure upstream stable-diffusion build
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "Build examples" FORCE)
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared library" FORCE)
set(SD_BUILD_SHARED_GGML_LIB OFF CACHE BOOL "Build shared ggml library" FORCE)

add_subdirectory(upstream)

add_library(
    stable_diffusion_bridge
    SHARED
    sd_bridge.cpp
    stb_image_write.cpp
)

target_include_directories(
    stable_diffusion_bridge
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/upstream/include
)

find_library(log-lib log)

target_link_libraries(
    stable_diffusion_bridge
    stable-diffusion
    ${log-lib}
    m
)
