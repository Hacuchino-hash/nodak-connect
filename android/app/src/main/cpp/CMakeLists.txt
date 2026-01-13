cmake_minimum_required(VERSION 3.13)
project(meshcore_codec2 C)

set(CODEC2_ROOT ${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/codec2)

include(${CMAKE_CURRENT_LIST_DIR}/codec2_sources.cmake)

set(CODEC2_SRC_DIR ${CODEC2_ROOT}/src)

set(CODEC2_SOURCE_FILES "")
foreach(src ${CODEC2_SOURCES})
    list(APPEND CODEC2_SOURCE_FILES ${CODEC2_SRC_DIR}/${src})
endforeach()

add_library(codec2 SHARED ${CODEC2_SOURCE_FILES})

set_target_properties(codec2 PROPERTIES
    OUTPUT_NAME "codec2"
)

target_include_directories(codec2 PUBLIC
    ${CODEC2_ROOT}/src
    ${CODEC2_ROOT}/include
)

target_compile_definitions(codec2 PRIVATE GIT_HASH="Unknown")

if(ANDROID)
    target_compile_options(codec2 PRIVATE -std=gnu11)
endif()

# Math library required on some platforms.
target_link_libraries(codec2 m)
