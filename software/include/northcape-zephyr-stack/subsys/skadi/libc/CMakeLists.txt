if(CONFIG_SKADI_LOADER)
    # "kernel" does not exist at run time
    # so we have to duplicate a few kernel sources...

    get_property(LIBC_LINK_LIBRARIES TARGET zephyr_interface PROPERTY LIBC_LINK_LIBRARIES)
    message("Linking C libraries ${LIBC_LINK_LIBRARIES}")
    if(CONFIG_SKADI_LIBC_SUPPORTS_FPU)
        create_skadi_subsystem_custom_sources(EXT_NAME libc APP zephyr SRCS skadi_library_subsystem.c skadi_libc_hooks.c ${ZEPHYR_BASE}/lib/libc/common/source/time/gmtime_r.c ${ZEPHYR_BASE}/lib/utils/bitarray.c NO_LIBRARY NO_ISOLATED_LIBC FPU EXTRA_CPPFLAGS -DNO_THREADS_IN_CALLEE_TRAMPOLINE -DLIBC_SUBSYSTEM)
    else()
        create_skadi_subsystem_custom_sources(EXT_NAME libc APP zephyr SRCS skadi_library_subsystem.c skadi_libc_hooks.c ${ZEPHYR_BASE}/lib/libc/common/source/time/gmtime_r.c ${ZEPHYR_BASE}/lib/utils/bitarray.c NO_LIBRARY NO_ISOLATED_LIBC EXTRA_CPPFLAGS -DNO_THREADS_IN_CALLEE_TRAMPOLINE -DLIBC_SUBSYSTEM)
    endif()

    skadi_subsystem_add_libraries(libc c -lgcc)

    skadi_extension_add_sources_ifdef(libc CONFIG_SKADI_TRACK_CYCLES_OPS skadi_libc_ops_cycles.c)
    skadi_extension_add_sources_ifdef(libc CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS skadi_libc_count_ss_calls.c)
    
endif()
