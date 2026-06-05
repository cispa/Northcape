if(CONFIG_SKADI_NUUK)
    create_skadi_subsystem_custom_sources(EXT_NAME nuuk APP zephyr SRCS nuuk.c nuuk_final_jump.S NO_YIELD EXTRA_CPPFLAGS -DNUUK_SUBSYSTEM)
endif()
