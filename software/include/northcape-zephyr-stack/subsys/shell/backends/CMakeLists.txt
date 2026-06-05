# SPDX-License-Identifier: Apache-2.0
if(CONFIG_SKADI_OS)

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_SERIAL
    shell_uart.c ${ZEPHYR_BASE}/drivers/serial/uart_async_rx.c # inlined for performance
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_DUMMY
    shell_dummy.c
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_RTT
    shell_rtt.c
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_TELNET
    shell_telnet.c
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_MQTT
    shell_mqtt.c
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_RPMSG
    shell_rpmsg.c
  )

  skadi_extension_add_sources_ifdef(
    shell
    CONFIG_SHELL_BACKEND_ADSP_MEMORY_WINDOW
    shell_adsp_memory_window.c
  )

else()

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_SERIAL
    shell_uart.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_DUMMY
    shell_dummy.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_RTT
    shell_rtt.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_TELNET
    shell_telnet.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_MQTT
    shell_mqtt.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_RPMSG
    shell_rpmsg.c
  )

  zephyr_sources_ifdef(
    CONFIG_SHELL_BACKEND_ADSP_MEMORY_WINDOW
    shell_adsp_memory_window.c
  )
endif()
