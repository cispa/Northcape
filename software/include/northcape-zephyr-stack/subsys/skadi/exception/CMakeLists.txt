if(CONFIG_SKADI_OS)
    # "kernel" does not exist at run time
    # so we have to duplicate a few kernel sources...
    create_skadi_subsystem_custom_sources(EXT_NAME exception APP zephyr SRCS exception_handler.c exception_isr.S  EXTRA_CPPFLAGS -I${ZEPHYR_BASE}/arch/riscv/include -I${ZEPHYR_BASE}/kernel/include -I${CMAKE_CURRENT_SOURCE_DIR})
endif()

zephyr_library_sources_ifdef(CONFIG_SKADI_OS exception_isr.S exception_handler.c)
