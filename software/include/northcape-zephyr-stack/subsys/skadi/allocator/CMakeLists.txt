if(CONFIG_SKADI_OS)
    # "kernel" does not exist at run time
    # so we have to duplicate a few kernel sources...
    create_skadi_subsystem_custom_sources(EXT_NAME allocator APP zephyr SRCS skadi_allocator.c ${ZEPHYR_BASE}/lib/utils/rb.c EXTRA_CPPFLAGS -DSKADI_SUBSYSTEM_ALLOCATOR EXTRA_CPPFLAGS -DNO_THREADS_IN_CALLEE_TRAMPOLINE NO_YIELD)
endif()
