#!/bin/bash

set -e
set -x

cd "$(dirname "${BASH_SOURCE[0]}")"

rm .jobs 2>&1 >/dev/null || true
touch .jobs


function build_sample () {
    echo "$@" >> .jobs
}

# CI unit tests

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/hello_world zephyr_hello_world

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/sim_hello_world sim_hello_world

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/sim_fail sim_fail

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/sim_capability_test sim_capability_test

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/subsystem subsystem

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/timer_irq timer_irq -- -D EXTRA_CONF_FILE=rate_bench.conf

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/read_error_exception read_error_exception

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/write_error_exception write_error_exception

build_sample cv64a6_testbench samples/boards/openhwgroup/cv64a6/scheduler_interaction scheduler_interaction

# Genesys 2

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/sim_capability_test zephyr_direct_cap_test_genesys

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/subsystem zephyr_subsystem

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/timer_irq zephyr_timer_irq -- -D EXTRA_CONF_FILE=nmi.conf

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/scheduler_interaction zephyr_scheduler_interaction

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/dumb_http_server zephyr_http_server

build_sample cv64a6_genesysII samples/net/zperf zephyr_zperf

build_sample cv64a6_genesysII ./tests/benchmarks/northcape-coremark/zephyr zephyr_coremark

build_sample cv64a6_genesysII ./tests/benchmarks/northcape-stream/ zephyr_stream

build_sample cv64a6_genesysII tests/benchmarks/latency_measure zephyr_latency_measure

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_timer_irq_rate -- -D EXTRA_CONF_FILE=rate_bench_nmi.conf

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement/ zephyr_net_overhead

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_mqtt_insecure

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_mqtt -- -D EXTRA_CONF_FILE=tls.conf

build_sample cv64a6_genesysII samples/boards/openhwgroup/cv64a6/porting/ porting_genesysII

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/porting/ porting_arty_a7_100

# baselines Genesys2
build_sample cv64a6_genesysII_nocape samples/hello_world zephyr_baseline_hello_world

build_sample cv64a6_genesysII_nocape samples/net/sockets/dumb_http_server zephyr_baseline_http_server

build_sample cv64a6_genesysII_nocape samples/net/zperf zephyr_baseline_zperf

build_sample cv64a6_genesysII_nocape ./tests/benchmarks/northcape-coremark/zephyr zephyr_baseline_coremark

build_sample cv64a6_genesysII_nocape ./tests/benchmarks/northcape-stream/ zephyr_baseline_stream

build_sample cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/network_stack_overhead_measurement zephyr_baseline_net_overhead

build_sample cv64a6_genesysII_nocape tests/benchmarks/latency_measure zephyr_baseline_latency_measure

build_sample cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_baseline_timer_irq_rate -- -D EXTRA_CONF_FILE=rate_bench.conf

build_sample cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_baseline_timer_irq_latency

build_sample cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/  zephyr_baseline_mqtt_insecure

build_sample cv64a6_genesysII_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/  zephyr_baseline_mqtt -- -D EXTRA_CONF_FILE=tls.conf

build_sample cv64a6_genesysII_nocape samples/userspace/syscall_perf/  zephyr_baseline_syscall

# Arty A7
build_sample cv64a6_arty_a7_100 ./tests/benchmarks/northcape-coremark/zephyr  zephyr_arty_coremark

build_sample cv64a6_arty_a7_100 tests/benchmarks/northcape-stream  zephyr_arty_stream -- -DEXTRA_CONF_FILE=small_mem.conf

build_sample cv64a6_arty_a7_100 tests/benchmarks/latency_measure/  zephyr_arty_latency_measure

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/timer_irq/  zephyr_arty_timer_irq -- -D EXTRA_CONF_FILE=nmi.conf

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_arty_timer_irq_rate -- -D EXTRA_CONF_FILE=rate_bench_nmi.conf

build_sample cv64a6_arty_a7_100 samples/net/zperf/ zephyr_arty_zperf

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/dumb_http_server/ zephyr_arty_http_server

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/hello_world/ zephyr_arty_hello_world

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_arty_mqtt_insecure

build_sample cv64a6_arty_a7_100 samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_arty_mqtt -- -D EXTRA_CONF_FILE=tls.conf


# Arty A7 baselines
build_sample cv64a6_arty_a7_100_nocape  ./tests/benchmarks/northcape-coremark/zephyr zephyr_arty_baseline_coremark

build_sample cv64a6_arty_a7_100_nocape tests/benchmarks/northcape-stream/ zephyr_arty_baseline_stream -- -DEXTRA_CONF_FILE=small_mem.conf

build_sample cv64a6_arty_a7_100_nocape tests/benchmarks/latency_measure/ zephyr_arty_baseline_latency_measure

build_sample cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_arty_baseline_timer_irq_latency

build_sample cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/timer_irq/ zephyr_arty_baseline_timer_irq_rate -- -D EXTRA_CONF_FILE=rate_bench.conf

build_sample cv64a6_arty_a7_100_nocape samples/net/zperf/ zephyr_arty_baseline_zperf

build_sample cv64a6_arty_a7_100_nocape samples/net/sockets/dumb_http_server zephyr_arty_baseline_http_server

build_sample cv64a6_arty_a7_100_nocape samples/hello_world zephyr_arty_baseline_hello_world

build_sample cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_arty_baseline_mqtt_insecure

build_sample cv64a6_arty_a7_100_nocape samples/boards/openhwgroup/cv64a6/mqtt_bench/ zephyr_arty_baseline_mqtt -- -D EXTRA_CONF_FILE=tls.conf

build_sample cv64a6_arty_a7_100_nocape samples/userspace/syscall_perf/  zephyr_arty_baseline_syscall

parallel --halt now,fail=1 --jobs "4" bash ./build-app.sh :::: .jobs

cd ../../

# special names
mv build_cv64a6_testbench_sim_hello_world build_sim_hello_world
mv build_cv64a6_testbench_sim_fail build_sim_fail
mv build_cv64a6_testbench_sim_capability_test build_cap_test
mv build_cv64a6_testbench_subsystem build_subsystem_test
mv build_cv64a6_testbench_timer_irq build_timer_irq_test
mv build_cv64a6_testbench_read_error_exception build_read_error_exception
mv build_cv64a6_testbench_write_error_exception build_write_error_exception
mv build_cv64a6_testbench_scheduler_interaction build_scheduler_interaction
 