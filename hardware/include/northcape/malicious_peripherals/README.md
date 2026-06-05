# Confused Deputy (and optionally malicious) DMA

## Overview
A simple data-copyer DMA to both debug the capability system in conjunction with DMAs and showcase ineffectiveness of DMA attacks.
Its legitimate purpose is to copy bytes from a starting address to an ending address.
It optionally waits for a request matching a trigger address (e.g., to determine that a memory region is available) and performs a configurable malicious write to main memory.

## Memory map
| Register | Bit | Interpretation | R or W|
|----------|-----|----------------|-------|
|   0x0    | 6-5 | AXI write resp.|  R    |
|   0x0    | 4-3 | AXI read resp. |  R    |
|   0x0    | 2   | running?       |  R    |
|   0x0    | 1   | ready?         |  R    |
|   0x0    | 0   | start transfer |  W    |
|   0x8    | all | start address  |  W    |
|   0x10   | all | dest. address  |  W    |
|   0x18   | all | transfer bytes |  W    |
