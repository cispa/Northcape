#!/bin/bash

# where are the tools
if ! [ -n "$RISCV" ]; then
  echo "Error: RISCV variable undefined"
  exit 1
fi


# install the required tools
source ./verif/regress/install-verilator.sh
source ./verif/regress/install-spike.sh

# install the required test suites
source ./verif/regress/install-riscv-compliance.sh
source ./verif/regress/install-riscv-tests.sh
source ./verif/regress/install-riscv-arch-test.sh

# setup sim env
source ./verif/sim/setup-env.sh

echo "$SPIKE_INSTALL_DIR$"

if ! [ -n "$DV_SIMULATORS" ]; then
  DV_SIMULATORS=veri-testharness
fi

if ! [ -n "$UVM_VERBOSITY" ]; then
    UVM_VERBOSITY=UVM_NONE
fi

if ! [ -n "$VERILATOR_THREADS" ]; then
  VERILATOR_THREADS=4
fi


export DV_OPTS="$DV_OPTS --issrun_opts=+debug_disable=1+UVM_VERBOSITY=$UVM_VERBOSITY"

cd verif/sim/

usage() {
  echo Usage: $0 '[-f (expected failure)] -z <zephyr root directory>' 
}

EXPECTED_FAILURE=0
ZEPHYR_ROOT=

while getopts "fz:" o; do
  case "${o}" in 
    f)
      EXPECTED_FAILURE="1"
      ;;
    z)
      ZEPHYR_ROOT=${OPTARG}
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "${ZEPHYR_ROOT}" ];
then
  echo "Must specify zephyr root (-z)";
  exit 1;
fi

pwd 
echo "Zephyr Root"
ls ${ZEPHYR_ROOT}/ 
echo "Zephyr Build"
ls ${ZEPHYR_ROOT}/build
echo "Zephyr build output"
ls ${ZEPHYR_ROOT}/build/zephyr/

ln -s ${ZEPHYR_ROOT}/build/zephyr/zephyr.elf ${ZEPHYR_ROOT}/build/zephyr/zephyr.o
LOGFILE=$(mktemp)
echo "Logfile is $LOGFILE"

export max_cycles=1000000000

export VERILATOR_THREADS=${VERILATOR_THREADS}

echo "Using maximum cycles $max_cycles verilator threads ${VERILATOR_THREADS}"

python3 cva6.py --elf_tests ${ZEPHYR_ROOT}/build/zephyr/zephyr.o  --iss_yaml cva6.yaml --target cv64a6_imafdc_sv39 --iss=veri-testharness --spike_params="" $DV_OPTS 2>&1 | tee $LOGFILE || exit 1

echo "Expected failure : ${EXPECTED_FAILURE}"

if [ "${EXPECTED_FAILURE}" -eq "1" ];
then
  
  grep ERROR $LOGFILE && echo "Test success - failure was expected (-f)!" && exit 0;
  echo "Test error - Expected failure!";
  exit 1
else
  grep ERROR $LOGFILE && echo "Test error!" && exit 1;
  echo "Test success"
  exit 0;
fi
