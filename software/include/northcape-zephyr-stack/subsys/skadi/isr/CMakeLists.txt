if(CONFIG_SKADI_OS)
    # "kernel" does not exist at run time
    # so we have to duplicate a few kernel sources...
    create_skadi_subsystem_custom_sources(EXT_NAME isr APP zephyr SRCS isr_subsystem.c skadi_isr.S skadi_fatal.c skadi_soc_irq.S EXTRA_CPPFLAGS -I${ZEPHYR_BASE}/arch/riscv/include -I${ZEPHYR_BASE}/kernel/include -I${CMAKE_CURRENT_SOURCE_DIR})
endif()
