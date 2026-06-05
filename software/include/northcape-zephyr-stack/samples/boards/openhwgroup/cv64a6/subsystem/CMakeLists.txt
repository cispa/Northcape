# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(subsystem_sample)

create_skadi_subsystem_main(APP app SRCS src/main.c)

create_skadi_subsystem_custom_sources(EXT_NAME dummy_encrypt_subsys_provider APP app SRCS src/dummy_encrypt_subsys_provider.c ${ZEPHYR_BASE}/subsys/timing/timing.c ${ZEPHYR_BASE}/arch/common/timing.c)
create_skadi_subsystem_custom_sources(EXT_NAME dummy_encrypt_subsys_tester APP app SRCS src/dummy_encrypt_subsys_tester.c ${ZEPHYR_BASE}/subsys/timing/timing.c ${ZEPHYR_BASE}/arch/common/timing.c FPU)
