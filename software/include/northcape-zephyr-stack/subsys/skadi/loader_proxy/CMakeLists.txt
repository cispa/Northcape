if(CONFIG_SKADI_LOADER)
    # NO_LOCAL_CLOCK needed to prevent cycle with clock
    create_skadi_subsystem_custom_sources(EXT_NAME loader_proxy APP zephyr SRCS loader_proxy.c EXTRA_CPPFLAGS -DNO_THREADS_IN_CALLEE_TRAMPOLINE -DLOADER_SUBSYSTEM NO_YIELD NO_LOCAL_CLOCK)
endif()
