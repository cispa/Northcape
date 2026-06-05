# Reproducing Conducted Experiments

Follow these instructions to reproduce the evaluation experiments in the paper.
This document has the following structure:
We first give setup instructions.
After that, we describe how to reproduce the experiments in a section-by-section, table-row-by-table-row order.

## Setup Guide
In the provided artifact, you will find four directories: 
- `raw_eval_data` contains traces from our runs.
- `trust_nothing_top` contains our prototype for Skadi and Bredi. We will use this to reproduce experiments that pertain to *Bredi, Skadi and Zephyr*.
- `cva6` contains a slightly modified version of the upstream cva6 CPU/SoC (we changed how interrupt generation in the APB timer works for our IRQ experiments). We will use this to reproduce experiments that pertain to the *upstream cva6 project only*.
- `scripts` contains an evaluation script.
- `extra_appendix.pdf` contains additional measurements from our experiment runs in aggregated form.

For Skadi/zephyr/Linux/Northcape setup, please follow the instructions in [trust_nothing_top/README.md](trust_nothing_top/README.md).
We recommend you follow these steps in a fresh Ubuntu 22.04 VM.
Note that while instructions for two different FPGA boards are given, it is only possible to reproduce our results on the *Genesys 2* board, which requires the appropriate Vivado and FPGA IP licenses as indicated in the README (free evaluation licenses suffice).
However, the *functionality* of our system (sans the AXI MMU, which is not used in the SoC) can be tested on the *Arty A7* board. The SoC for the Arty *can be synthesized completely with built-in (free) Vivado licenses*.
Use a GUI install or X window forwarding to install graphical software like Xilinx Vivado.
*Do this first* to install the toolchain.

We recommend that you follow the instructions run Skadi's hello-world sample at this point to ensure everything is working correctly.
Whenever running a Skadi sample, we recommend you use two concurrent shell sessions: Attach to the serial output of the FPGA board in one session and run all `west` commands in a second session.


For the cva6 setup, run the following command:
```bash
cd trust_nothing_top/hardware/include/cva6
make fpga # defaults suffice
```

## 6 - Loader Loc
First, build the exemplary scenario. Then, run our analysis script.

```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

west build -p always -b cv64a6_genesysII samples/net/zperf

python3 scripts/skadi/analyze_source_loc.py build/zephyr/zephyr.elf
```


## 7.1 - Chip Area

Reproducing the chip area results requires three distinct build artifacts: *the Northcape FPGA SoC, the cva6 FPGA SoC, the ASIC build*.
We will discuss how to build and evaluate the artifacts separately.

### Northcape FPGA SoC

LUT, Flip-Flop, MUX and BRAM count for all Northcape components and Northcape cva6 are derived from the Northcape FGPA SoC.
The SoC is built during the setup stage.
In order to evaluate the SoC, run the following script:

```bash
cd trust_nothing_top/scripts/Vivado
./open_project.sh
```

This will open Xilinx Vivado in interactive mode.
In the Flow Navigator (Left Pane), find *Implemented Design* and expand to click *Report Utilization*. Click *OK* when prompted and accept defaults.
This will take a few minutes and open the post-place-and-route FPGA design afterwards, displaying utilization information in the bottom row.

You can use the looking glass icon closer to "Hierarchy" to search for the Northcape components and expand the hierarchy until you reach the corresponding component.
For "MMU", search "northcape_mmu_dma".
For "Resolver", search "northcape_cap_resolver".
For "Operations", search "northcape_cap_ops".
For "L2 NTLB", search "northcape_cap_cache_0".
For "Northcape cva6", search "i_cva6".

You can retrieve the LUT, Register count, MUX count etc. from the table columns.
Click the percentage (%) icon to switch to relative numbers.
Our reported table rows refer to the "Slice LUTs", "Slice Registers", "F7 Muxes" + "F8 Muxes" and "Block RAM Tile" columns, respectively.

For our power numbers, refer to Vivado's power report for the implemented design.
For the insecure reference, build the non-Bredi version of the SoC:
```bash
cd trust_nothing_top/scripts/Vivado
./create_project_non_bredi.sh && ./create_bitstream_non_bredi.sh
./open_project_non_bredi.sh
```

Follow the same steps to report power.

### cva6 FPGA SoC

LUT, Flip-Flop, MUX and BRAM count for Original cva6 are derived from the cva6 FGPA SoC.
The SoC is built during the setup stage.
In order to evaluate the SoC, run the following script:

```bash
cd cva6
vivado ./corev_apu/fpga/work-fpga/ariane_xilinx_routed.dcp
```

This will open Xilinx Vivado in interactive mode.
Click *Reports->Report Utilization", and click OK with default settings.

In the table at the bottom, labeled *Utilization*, expand the row *i_ariane* to locate *i_cva6*.
This refers to the cva6 CPU.

You can retrieve the LUT, Register count, MUX count etc. from the table columns.
Click the percentage (%) icon to switch to relative numbers.
Our reported table rows refer to the "Slice LUTs", "Slice Registers", "F7 Muxes" + "F8 Muxes" and "Block RAM Tile" columns, respectively.


### ASIC
Run the following scripts as root to install ASIC dependencies and reproduce the ASIC results:

```bash
cd trust_nothing_top/scripts/asic/scripts
./install-dependencies.sh
export OPENLANE_ROOT=/tmp/openlane2/ && export PATH=$(dirname `find /nix/ -name nix-shell`):$PATH && ./run-synthesis.sh
```

These steps should work on the same Ubuntu 22.04 setup that is used for the remaining setup.
Expect the build process to run for *several days* depending on the number of available CPU cores.

For each component, the final script will print the area and FMAX information.
For area, we report the total cell count and subtract tap and fill cells (which are only required to fill empty space in the chip mask and have no logical function).
For FMAX, we report the value as printed.


## 7.2 - Software: Code Size

Reproducing the code size results requires two different approaches for Skadi and the zephyr baseline:
Results for zephyr can be determined using the static image, while for Skadi, the image needs to be run on the SoC.
Thus, we recommend you first replicate the zephyr results and then proceed with the Skadi results.

### zephyr Code Size - Genesys2
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_genesysII_nocape samples/hello_world/ # note "_nocape", not "_northcape", so this builds the zephyr baseline - in retrospect, this naming convention might not have been ideal
size -G build/zephyr/zephyr.elf
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row

# "HTTP Server" column
west build -p always -b cv64a6_genesysII_nocape samples/net/sockets/dumb_http_server
# same evaluation as for Hello World

# "zperf" column
west build -p always -b cv64a6_genesysII_nocape samples/net/zperf/
# same evaluation as for Hello World
```

Outputs from our runs can be found in `raw_eval_data/genesys2/code_size_hello_world_zephyr_northcape.txt`, `raw_eval_data/genesys2/code_size_http_server_zephyr_northcape.txt` and `raw_eval_data/genesys2/code_size_zperf_zephyr_northcape.txt`, respectively.


### zephyr Code Size - Arty A7
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/hello_world/ # note "_nocape", not "_northcape", so this builds the zephyr baseline - in retrospect, this naming convention might not have been ideal
size -G build/zephyr/zephyr.elf # convert "size" output from hex to decimal for txt, rodata, datas, bss sections - refers to the respective row
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row

# "HTTP Server" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/net/sockets/dumb_http_server
# same evaluation as for Hello World

# "zperf" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/net/zperf/
# same evaluation as for Hello World
```


### Skadi Code Size - Genesys2

Program the *Northcape SoC* bitstream onto the FPGA board first.
Then, build and run the three scenarios:

```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate
# "Hello World" column
west build -p always -b cv64a6_genesysII samples/hello_world
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row
# value in last row, after "overhead: ", refers to ELF overhead row
./scripts/skadi/extension_overhead.sh

# "HTTP Server" column
west build -p always -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/dumb_http_server/
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row
# value in last row, after "overhead: ", refers to ELF overhead row
./scripts/skadi/extension_overhead.sh

# "zperf" column
west build -p always -b cv64a6_genesysII samples/net/zperf/
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row
# value in last row, after "overhead: ", refers to ELF overhead row
./scripts/skadi/extension_overhead.sh

```

After loading the binary using `west debug`, press `c` to launch execution.
You can then locate the results with the exception of the Disk size determined with `du` in the console output:
- The results for "Text", "Data", "R/O Data" and "BSS" rows can be found in the output after `I: Total subsystem sizes:`.
- The result for "Total mem" can be found in parentheses in the lines like this:
`I: Allocator has 1071227440 of 1073479680 free bytes (accordingly: 2252240 used bytes) in 27 blocks!`
- In the above sample, "Total mem" would be 2252240.


Outputs from our runs can be found in `raw_eval_data/genesys2/code_size_hello_world_skadi_northcape.txt`, `raw_eval_data/genesys2/code_size_http_server_skadi_northcape.txt` and `raw_eval_data/genesys2/code_size_zperf_skadi_northcape.txt`, respectively.

The number of subsystems, stacks and register sets can be found at the end of the build output.
Likewise, the number of callee ("exported") and caller ("imported") subsystems can be foudn in the build output.
The number of register sets and stacks is statically set in the build configuration.
Finally, run this script to get the ELF overhead:
```bash
./scripts/skadi/extension_overhead.sh
```
The output is in the last row after "overhead:".

### Skadi Code Size - Arty A7

Program the *Northcape SoC* bitstream onto the FPGA board first.
Then, build and run the three scenarios:

```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate
# "Hello World" column
west build -p always -b cv64a6_arty_a7_100 samples/hello_world
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row

# "HTTP Server" column
west build -p always -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/dumb_http_server/
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row

# "zperf" column
west build -p always -b cv64a6_arty_a7_100 samples/net/zperf/
# run the sample
west debug
du -b build/zephyr/zephyr.bin # note .bin - this refers to the "Disk size" row

```

After loading the binary using `west debug`, press `c` to launch execution.
You can then locate the results with the exception of the Disk size determined with `du` in the console output:
- The results for "Text", "Data", "R/O Data" and "BSS" rows can be found in the output after `I: Total subsystem sizes:`.
- The result for "Total mem" can be found in parentheses in the lines like this:
`I: Allocator has 1071227440 of 1073479680 free bytes (accordingly: 2252240 used bytes) in 27 blocks!`
- In the above sample, "Total mem" would be 2252240.


The number of subsystems, stacks and register sets can be found at the end of the build output.
Likewise, the number of callee ("exported") and caller ("imported") subsystems can be foudn in the build output.
The number of register sets and stacks is statically set in the build configuration.
Finally, run this script to get the ELF overhead:
```bash
./scripts/skadi/extension_overhead.sh
```
The output is in the last row after "overhead:".

## 7.3: Load times

### Load times zephyr - Genesys 2
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_genesysII_nocape samples/hello_world/ # note "_nocape", not "_northcape", so this builds the zephyr baseline 
west debug

# "HTTP Server" column
west build -p always -b cv64a6_genesysII_nocape samples/net/sockets/dumb_http_server
west debug

# "zperf" column
west build -p always -b cv64a6_genesysII_nocape samples/net/zperf/
west debug
```

Outputs from our runs can be found in `raw_eval_data/genesys2/load_time_hello_world_zephyr_northcape.txt`, `raw_eval_data/genesys2/load_time_http_server_zephyr_northcape.txt` and `raw_eval_data/genesys2/load_time_zperf_zephyr_northcape.txt`, respectively.

### Load times Skadi - Genesys 2
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_genesysII samples/hello_world/
west debug

# "HTTP Server" column
west build -p always -b cv64a6_genesysII samples/net/sockets/dumb_http_server
west debug

# "zperf" column
west build -p always -b cv64a6_genesysII samples/net/zperf/
west debug
```

Outputs from our runs can be found in `raw_eval_data/genesys2/load_time_hello_world_skadi.txt`, `raw_eval_data/genesys2/load_time_http_server_skadi.txt` and `raw_eval_data/genesys2/load_time_zperf_skadi.txt`, respectively.

### Load times zephyr - Arty A7
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/hello_world/ # note "_nocape", not "_northcape", so this builds the zephyr baseline 
west debug

# "HTTP Server" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/net/sockets/dumb_http_server
west debug

# "zperf" column
west build -p always -b cv64a6_arty_a7_100_nocape samples/net/zperf/
west debug
```

Outputs from our runs can be found in `raw_eval_data/genesys2/load_time_hello_world_zephyr_northcape.txt`, `raw_eval_data/genesys2/load_time_http_server_zephyr_northcape.txt` and `raw_eval_data/genesys2/load_time_zperf_zephyr_northcape.txt`, respectively.

### Load times Skadi - Arty A7
Use the following script to build the scenarios and check their code size:
```bash
cd trust_nothing_top/software/include/northcape-zephyr-stack
source .venv/bin/activate

# "Hello World" column
west build -p always -b cv64a6_arty_a7_100 samples/hello_world/
west debug

# "HTTP Server" column
west build -p always -b cv64a6_arty_a7_100 samples/net/sockets/dumb_http_server
west debug

# "zperf" column
west build -p always -b cv64a6_arty_a7_100 samples/net/zperf/
west debug
```

Outputs from our runs can be found in `raw_eval_data/genesys2/load_time_hello_world_skadi.txt`, `raw_eval_data/genesys2/load_time_http_server_skadi.txt` and `raw_eval_data/genesys2/load_time_zperf_skadi.txt`, respectively.

## 7.4: Microbenchmarks

### Microbenchmarks - Genesys 2
Build and run the samples like this:
```bash
# do not track cycles for operations - for time from C code
west build -p -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/sim_capability_test/
# track cycles for operations - for time in actual ops module
west build -p -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/sim_capability_test -- -DEXTRA_CONF_FILE=ops_cycles.conf
# system call performance as a baseline
west build -p -b cv64a6_genesysII_nocape samples/userspace/syscall_perf/
# run the samples
west debug
```
Results from our runs can be found here:
- `raw_eval_data/genesys2/microbench_skadi_northcape.txt`
- `raw_eval_data/genesys2/microbench_skadi_northcape_cycles.txt`
- `raw_eval_data/genesys2/microbench_syscall.txt`


### Microbenchmarks - Arty A7
Build and run the samples like this:
```bash
# do not track cycles for operations - for time from C code
west build -p -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/sim_capability_test/
# track cycles for operations - for time in actual ops module
west build -p -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/sim_capability_test -- -DEXTRA_CONF_FILE=ops_cycles.conf
# system call performance as a baseline
west build -p -b cv64a6_arty_a7_100_nocape samples/userspace/syscall_perf/
# run the samples
west debug
```


## 7.5 System: Compute Performance
The experiments in this section comprise running the coremark and stream benchmarks using the zephyr and Skadi operating systems.
Again, program the *Northcape SoC* bitstream onto the FPGA board first, then follow the instructions below to build and run the experiments.
For both zephyr and Skadi, results can be found in the console output.

### zephyr Compute Performance - Genesys2

Build and run the samples like this:
```bash
# coremark
west build -p always -b cv64a6_genesysII_nocape ./tests/benchmarks/northcape-coremark/zephyr
# run the sample
west debug

west build -p always -b cv64a6_genesysII_nocape ./tests/benchmarks/northcape-stream
# run the sample
west debug
```

For coremark, the benchmark will execute 10 times.
Collect the results from the lines starting with `Iterations/Sec   :` and compute the median using any calculator of your choice.

For Stream, the benchmark will compute the average on its own.
Find the lines starting with `Copy:`, `Scale:` etc. and compare the second column to the value in the paper.


Outputs from our runs can be found in `raw_eval_data/genesys2/synthetic_coremark_zephyr_northcape.txt` and `raw_eval_data/genesys2/synthetic_stream_zephyr_northcape.txt`, respectively.

### zephyr Compute Performance - Arty A7

Build and run the samples like this:
```bash
# coremark
west build -p always -b cv64a6_arty_a7_100_nocape ./tests/benchmarks/northcape-coremark/zephyr
# run the sample
west debug

west build -p always -b cv64a6_arty_a7_100_nocape ./tests/benchmarks/northcape-stream -- -DEXTRA_CONF_FILE=small_mem.conf
# run the sample
west debug
```

For coremark, the benchmark will execute 10 times.
Collect the results from the lines starting with `Iterations/Sec   :` and compute the median using any calculator of your choice.

For Stream, the benchmark will compute the average on its own.
Find the lines starting with `Copy:`, `Scale:` etc. and compare the second column to the value in the paper.

### Linux compute performance - Both

Run the following commands from bash:

```bash
for i in `seq 1 10`; do coremark; done
stream
```

Output formats and evaluation are the same as in zephyr.
Outputs from our runs can be found in `raw_eval_data/trace_linux.txt`.

### Skadi Compute Performance - Genesys2
Build and run the samples like this:
```bash
# coremark
west build -p always -b cv64a6_genesysII ./tests/benchmarks/northcape-coremark/zephyr
# run the sample
west debug

west build -p always -b cv64a6_genesysII ./tests/benchmarks/northcape-stream
# run the sample
west debug
```

The output and evaluation is the same as for Skadi, substituting `zephyr` for `skadi` in the output file names.

### Skadi Compute Performance - Arty A7
Build and run the samples like this:
```bash
# coremark
west build -p always -b cv64a6_arty_a7_100 ./tests/benchmarks/northcape-coremark/zephyr
# run the sample
west debug

west build -p -b cv64a6_arty_a7_100 tests/benchmarks/northcape-stream/ -- -DEXTRA_CONF_FILE=small_mem.conf
# run the sample
west debug
```

The output and evaluation is the same as for Skadi, substituting `zephyr` for `skadi` in the output file names.

## 7.6 System: Network Performance
For this benchmark, connect your build machine to the FPGA board's Ethernet interface and assign the static IP address `192.0.2.2/24` to your interface.
Required software is installed automatically.

For this benchmark, conducting the experiment requires the same steps for both Skadi and zephyr, with the only difference being which images are built.
Hence, we will give complete instructions for *zephyr* and only provide the commands to build the corresponding *Skadi* images.

### zephyr Network Performance - Genesys2

We recommend starting a third shell interface for running the measurement endpoints for this experiment.
Build and run the samples like this:
```bash
# ping / iperf TCP
west build -p always -b cv64a6_genesysII_nocape samples/net/zperf
# run the sample
west debug

# RX duration, TX duration
west build -p always -b cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement/
# run the sample
west debug

# MQTT-TLS
west build -p always -b cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/ -- -D EXTRA_CONF_FILE=tls.conf
# run the sample
west debug
```

For the ping scenario, execute the following steps on the connected system:
```bash
ping 192.0.2.1 # let it run for 10 samples to warm up ARP cache
ping -i 0.2 192.0.2.1 -c 1000 # collected data
```

Locate the average and standard deviation in the output from the second `ping`.

For the zperf scenario, run an iperf server:
```bash
/usr/bin/iperf  -s -e -i 1
```

Switch to the console connected to the FPGA port and run the following command in zephyr's shell:

```bash
zperf tcp upload 192.0.2.2 5001 60 1k
```

Compute average and standard deviation of the per-second transfer data rates reported by iperf using a calculator of your choice.

For the RX duration / TX duration scenarios, run the following script from the host system:

```bash
./trust_nothing_top/software/include/northcape-zephyr-stack/scripts/skadi/network_perf_test.sh
```

You can find the results for the RX and TX scenarios in the lines starting with `rx network stack processing durations` and `tx network stack processing durations`, respectively.

Finally, for the MQTT-TLS result, use the following scripts to launch a mosquitto server and client:
```bash
cd ./trust_nothing_top/software/include/northcape-zephyr-stack
./scripts/skadi/run_mosquitto_server.sh
./scripts/skadi/run_mosquitto_client.sh # concurrent in a second session
```
You can find the results in the line starting with `MQTT iteration times`.

The console traces from the FPGA board for our ping/iperf run are available as `raw_eval_data/genesys2/net_zperf_trace_zephyr_northcape.txt`.

The results from our runs are available in these files:
- raw_eval_data/genesys2/ping_zephyr_northcape.txt
- raw_eval_data/genesys2/zperf_tcp_zephyr_northcape.txt
- raw_eval_data/genesys2/network_overhead_zephyr_northcape.txt
- raw_eval_data/genesys2/net_mqtt_zephyr_northcape.txt


### zephyr Network Performance - Arty A7

Build and run the samples like this:
```bash
# ping / iperf TCP
west build -p always -b cv64a6_arty_a7_100_nocape samples/net/zperf
# run the sample
west debug

# RX duration, TX duration
west build -p always -b cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement/
# run the sample
west debug

# MQTT-TLS
west build -p always -b cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/ -- -D EXTRA_CONF_FILE=tls.conf
# run the sample
west debug
```
The steps for conducting and evaluating experiments are the same as on the Genesys2 board.


### Linux Network Performance - Both

Build and run the samples like this:

```bash
# iperf TCP
iperf -c 192.0.2.2 -i 1 -t 60
# network stack overhead
net_overhead
# copy software/include/northcape-zephyr-stack/scripts/skadi/mosquitto-ca/ca.crt to the Linux image, e.g., via cat <<EOF > ca.crt and copy-pasting
# set date and time - for TLS validation
date -s $CURRENT_DATE_TIME
# MQTT-TLS
mqtt_bench 192.0.2.2 8883 ca.crt
```

### Skadi Network Performance - Genesys2
Build and run the samples like this:
```bash
# ping / iperf TCP
west build -p always -b cv64a6_genesysII samples/net/zperf
# run the sample
west debug

# RX duration, TX duration
west build -p always -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement/
# run the sample
west debug

# MQTT-TLS
west build -p always -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/mqtt_bench/ -- -D EXTRA_CONF_FILE=tls.conf
# run the sample
west debug
```

The console traces from the FPGA board for our ping/iperf run are available as `raw_eval_data/genesys2/net_zperf_trace_skadi.txt`.
The results from our runs are available in these files:
- `raw_eval_data/genesys2/ping_skadi.txt`
- `raw_eval_data/genesys2/zperf_tcp_skadi.txt`
- `raw_eval_data/genesys2/network_overhead_skadi_northcape.txt`
- `raw_eval_data/genesys2/net_mqtt_skadi_northcape.txt`


### Skadi Network Performance - Arty A7
Build and run the samples like this:
```bash
# ping / iperf TCP
west build -p always -b cv64a6_arty_a7_100 samples/net/zperf
# run the sample
west debug

# RX duration, TX duration
west build -p always -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement/
# run the sample
west debug

# MQTT-TLS
west build -p always -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/mqtt_bench/ -- -D EXTRA_CONF_FILE=tls.conf
# run the sample
west debug
```

## 7.7 System: Real-Time Capability
This final section conducts three experiments that gauge the ability of Skadi to handle interrupts in real time and the scheduler performance.
Again, the steps for conducting the experiments on zephyr and Skadi are the same, so we give full instructions for zephyr and only provide build steps and raw data for Skadi.

### zephyr Real-Time Capability - Genesys2

Build and run the samples like this:
```bash
# independent IRQ sample
west build -p always -b cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/timer_irq/
# run the sample
west debug

# monotonic IRQ sample
west build -p always -b cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=rate_bench.conf
# run the sample
west debug

# scheduler API sample
west build -p always -b cv64a6_genesysII_nocape tests/benchmarks/latency_measure
# run the sample
west debug
```

For the independent IRQ sample, results for average and standard deviation can be read from the output line that starts like this:
`IRQ delays for rate 200000000 (10000000 cycles)`.
For the monotonic period and average/standard deviation, find the line that starts with `IRQ delays for rate`.
The indicated rate is the period, and average and standard deviation can similarly be read from the remainder of that line.

Finally, for the `latency_measure` sample, we suggest you capture the output in a file (e.g., using `picocom -g`).
Copy the captured file to `raw_eval_data/rt_macrobench_zephyr_northcape.txt`.
Then run the following script:
```bash
mkdir tables # table 9 from the paper to be re-created here
python3 scripts/generate_macrobench_table.sh
```
The results from this experiment are included as items in plain text in the paper.
The items will be re-created in the console output from said script.
Note that the reproduction for this experiment is only complete once you have run the sample for both zephyr and Skadi.

Results from our runs can be found here:
- `raw_eval_data/genesys2/rt_latency_zephyr_northcape.txt`
- `raw_eval_data/genesys2/rt_rate_zephyr_northcape.txt`
- `raw_eval_data/genesys2/rt_macrobench_zephyr_northcape.txt`

### zephyr Real-Time Capability - Arty A7

Build and run the samples like this:
```bash
# independent IRQ sample
west build -p always -b cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/timer_irq/
# run the sample
west debug

# monotonic IRQ sample
west build -p always -b cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=rate_bench.conf
# run the sample
west debug

# scheduler API sample
west build -p always -b cv64a6_arty_a7_100_nocape tests/benchmarks/latency_measure
# run the sample
west debug
```

The steps to conduct and evaluate the experiments are the same as for the Genesys2.


### Linux real-time capability
Run the following commands:
```bash
insmod /lib/modules/5.10.7/extra/pulp_apb_timer.ko 
# independent
irq_client_independent
# monotonic
irq_client_monotonic
```

### Skadi Real-Time Capability - Genesys2

Build and run the samples like this:
```bash
# independent IRQ sample
west build -p always -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=nmi.conf
# run the sample
west debug

# monotonic IRQ sample
west build -p always -b cv64a6_genesysII samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=rate_bench_nmi.conf
# run the sample
west debug

# scheduler API sample
west build -p always -b cv64a6_genesysII tests/benchmarks/latency_measure
# run the sample
west debug
```
Results from our runs can be found here:
- `raw_eval_data/genesys2/rt_latency_skadi_northcape.txt`
- `raw_eval_data/genesys2/rt_rate_skadi_northcape.txt`
- `raw_eval_data/genesys2/rt_macrobench_skadi_northcape.txt`


### Skadi Real-Time Capability - Arty A7

Build and run the samples like this:
```bash
# independent IRQ sample
west build -p always -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=nmi.conf
# run the sample
west debug

# monotonic IRQ sample
west build -p always -b cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/timer_irq/ -- -D EXTRA_CONF_FILE=rate_bench_nmi.conf
# run the sample
west debug

# scheduler API sample
west build -p always -b cv64a6_arty_a7_100 tests/benchmarks/latency_measure
# run the sample
west debug
```
