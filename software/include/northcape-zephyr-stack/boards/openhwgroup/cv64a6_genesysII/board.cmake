# TODO --cmd-reset-halt=halt
board_runner_args(openocd "--config=${BOARD_DIR}/support/ariane.cfg")
board_runner_args(openocd "--use-elf")
board_runner_args(openocd "--verify")
# board_runner_args(openocd "--cmd-pre-init=\"adapter driver ftdi\"")
# board_runner_args(openocd "--cmd-pre-init=\"tcl_port 6666\"")
board_runner_args(openocd "--cmd-pre-init=riscv.cpu configure -work-area-phys 0x90000000 -work-area-size 16780000")

include(${ZEPHYR_BASE}/boards/common/openocd.board.cmake)
