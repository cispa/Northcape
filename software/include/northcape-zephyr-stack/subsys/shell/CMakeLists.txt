# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SKADI_OS)
  
  if(CONFIG_SHELL)
    create_skadi_subsystem_custom_sources(
      EXT_NAME shell
      APP zephyr 
      SRCS skadi_shell.c shell_fprintf.c shell_utils.c shell_ops.c ${ZEPHYR_BASE}/kernel/skadi/skadi_shell.c
      EXTRA_CPPFLAGS -I${CMAKE_CURRENT_SOURCE_DIR}
      FPU
      NO_ISOLATED_LIBC # directly jump into libc for performance - shell subsystem is not security-critical
    )


    skadi_extension_add_sources_ifdef(
      shell
      CONFIG_SHELL_LOG_BACKEND
      shell_log_backend.c
    )

    skadi_extension_add_sources_ifdef(
      shell
      CONFIG_SHELL_HELP
      shell_help.c
      )

    skadi_extension_add_sources_ifdef(
      shell
      CONFIG_SHELL_CMDS
      shell_cmds.c
      )

    skadi_extension_add_sources_ifdef(
      shell
      CONFIG_SHELL_HISTORY
      shell_history.c ${ZEPHYR_BASE}/lib/utils/ring_buffer.c # ring_buffer inlined for performance
      )

    skadi_extension_add_sources_ifdef(
      shell
      CONFIG_SHELL_WILDCARD
      shell_wildcard.c
    )
  endif()

else()

  zephyr_sources_ifdef(
    CONFIG_SHELL
    shell.c
    shell_fprintf.c
    shell_utils.c
    shell_ops.c
    )

  zephyr_sources_ifdef(
    CONFIG_SHELL_LOG_BACKEND
    shell_log_backend.c
    )

  zephyr_sources_ifdef(
    CONFIG_SHELL_HELP
    shell_help.c
    )

  zephyr_sources_ifdef(
    CONFIG_SHELL_CMDS
    shell_cmds.c
    )

  zephyr_sources_ifdef(
    CONFIG_SHELL_HISTORY
    shell_history.c
    )

  zephyr_sources_ifdef(
    CONFIG_SHELL_WILDCARD
    shell_wildcard.c
  )
endif()

add_subdirectory(modules)
add_subdirectory(backends)

