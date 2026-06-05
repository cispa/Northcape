# SPDX-License-Identifier: Apache-2.0

zephyr_library()
if(CONFIG_SKADI_LOADER)
  # TODO port PTP subsystem if needed
else()
  zephyr_library_sources(
    btca.c
    clock.c
    msg.c
    port.c
    ptp.c
    state_machine.c
    tlv.c
    transport.c
  )
endif()
