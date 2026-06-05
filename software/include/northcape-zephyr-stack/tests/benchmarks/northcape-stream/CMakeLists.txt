cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(stream)

set(STREAM_DIR ${CMAKE_CURRENT_SOURCE_DIR})

set(STREAM_SRCS
        # core sources
        ${STREAM_DIR}/stream.c
)

if(CONFIG_SKADI_OS)
    create_skadi_subsystem_main(APP app SRCS ${STREAM_SRCS} FPU EXTRA_CPPFLAGS -Wno-unknown-pragmas -DSTREAM_ARRAY_SIZE=${CONFIG_STREAM_ARRAY_SIZE})
else()
    target_sources(app PRIVATE ${STREAM_SRCS})
    target_compile_options(app PRIVATE -Wno-unknown-pragmas -DSTREAM_ARRAY_SIZE=${CONFIG_STREAM_ARRAY_SIZE})
endif()
