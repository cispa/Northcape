# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(timer_irq_sample)

set(extra_def "")

if(CONFIG_SKADI_LOADER)
    create_skadi_subsystem_main(APP app SRCS src/main.c)

    create_skadi_subsystem(busy_waiter app)
    create_skadi_subsystem_custom_sources(EXT_NAME irq_client APP zephyr SRCS src/irq_client.c FPU EXTRA_CPPFLAGS ${extra_def})
else()
    target_sources(app PRIVATE
        src/main.c
        src/busy_waiter.c
        src/irq_client.c
    )

    target_compile_options(app PRIVATE ${extra_def})
endif()
