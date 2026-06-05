# CAN-SPI

An interposer that goes between, e.g., a Xilinx AXI Quad SPI and the Northbridge/CPU.
Its purpose is to a) decode permissible CAN transactions via a PMOD-CAN behind the Quad SPI for the provided current task ID from the device-specific restriction and b) to enforce that only the intended CAN transactions can be triggered by the current task.
