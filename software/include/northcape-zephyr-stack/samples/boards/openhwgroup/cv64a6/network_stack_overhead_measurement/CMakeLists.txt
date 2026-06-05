# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(dumb_http_server)

FILE(GLOB app_sources src/*.c)
set(gen_dir ${ZEPHYR_BINARY_DIR}/include/generated/)

if(CONFIG_SKADI_OS)
    create_skadi_subsystem_main(APP app SRCS ${app_sources} EXTRA_CPPFLAGS -I${ZEPHYR_BASE}/include/zephyr/posix FPU)
else()
    target_sources(app PRIVATE ${app_sources})
endif()

include(${ZEPHYR_BASE}/samples/net/common/common.cmake)
