# Northcape (Northbridge Capability Enforcement) Code

## Overview
This is the implementation of the capability enforcement modules in the northcape project.

## Directory Structure
- `ariane` contains a header with macros for assigning northcape interfaces to Ariane interfaces
- `axis_demux` contains an AXI Stream 5 Demultiplexer
- `axis_mux` contains an AXI Stream 5 Multiplexer
- `capability_ops` contains the module that performs capability operations
- `capability_resolver` contains the module that performs capability lookups
- `common` contains interface definitions and other shared structures
- `malicious_peripherals` contains a device for demonstrating the attack: a simple DMA data copyer that is vulnerable against confused deputy attacks and optionally has a backdoor
- `mmu` contains the module that performs capability enforcement on the AXI bus
- `scripts` contains unit scripts for running unit tests with SVUnit
- `tests` contains unit test testbenches
- `xilinx` contains a header with macros for assigning northcape interfaces to Xilinx interfaces

## Dependencies for Unit Tests
- xsim, tested with Vivado 2023.2 (*broken* with 2024.2 - you *need to* install 2023.2 to /opt/Xilinx/Vivado/2023.2 to use the unit tests)
- git
- envsubst (*gettext-base* package on Ubuntu)
- parallel
- libtinfo-dev (might have to symlink to *libtinfo.so.5*)
- locales
- build-essential
- expect
- libtasn1-dev
- libjson-glib-dev
- socat
- libwolfssl-dev
- xxd
- curl
- autoconf
- libtool
- net-tools
- gawk
- libseccomp-dev
- libgmp-dev

## Running Unit Tests

- To run all tests: 
```bash
cd scripts/tests
./unittest_xsim.sh
```
- To run specific tests: 
```bash
cd scripts/tests
./unittest_xsim.sh -testplusarg UVM_TESTNAME=test_$TESTNAME  -testplusarg UVM_VERBOSITY=UVM_DEBUG # UVM_MEDIUM is default
```
- Set `LOGDIR` environment variable to change where logs are stored (default: tempdir). 
- Set `SKIP_COMPILE` environment variable to skip compiling the sources from scratch.
- View waveform using `show_unittest_wave.sh`.

## Running the automatic formatter
- Install dependencies first (scripts contained for Ubuntu 22.04):
```bash
    sudo ./scripts/autoformat/install-bazel-ubuntu.sh
    sudo ./scripts/autoformat/install-verible.sh
```
- Verible will be installed to `/usr/local/bin`.
- Then run the formatter:
```bash
    ./scripts/autoformat/verible-format-check.sh
```
- The formatter **will change files in place automatically**.
