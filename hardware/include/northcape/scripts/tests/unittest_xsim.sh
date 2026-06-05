#!/bin/sh
. ./testsetup_vivado.sh || exit $?

. ./vivado_check_output.sh || exit $?

cd ../../tests || exit 1
envsubst < tests_vlog.f > .tests_vlog.f || exit 1
envsubst < tests_vhdl.f > .tests_vhdl.f || exit 1
echo "Running tests in Vivado xsim!"

if command -v parallel; then
    echo "GNU parallel found!";
else
    echo "Please install GNU parallel!";
    exit 1;
fi

set -e
# more CPUs can lead to thrashing
CPU_LIMIT=16
CPUS=$(( $(nproc) < $CPU_LIMIT ? $(nproc) : $CPU_LIMIT ))
# there is a bug in Vivado 2024.2 that causes runs to error out with a spurious warning regarding X/Z values in constraints
export PATH=/opt/Xilinx/Vivado/2023.2/bin:$PATH
echo Using vivado $(which vivado)


generate_coverage_report(){
    LOGDIR=$1;
    COV_DIR="xsim.covdb/"
    COV_REPORTS=$(find $COV_DIR);
    echo "Found coverage reports $COV_REPORTS";

    xcrg -dir $COV_DIR -merge_db_name cov_out.covdb -merge_dir $LOGDIR -report_dir $LOGDIR/xcrg_func_cov_report 

    echo "Find the coverage report at $LOGDIR/xcrg_func_cov_report"
}

if [ -z "${NO_WRAP+x}" ]; then
    EXTRA_DEFINES=""
else
    EXTRA_DEFINES="--define NORTHCAPE_MMU_NO_AXI_WRAP"
fi

if [ -z "${DEBUG+x}" ]; then
    # nothing to do - no debug
    echo "Set DEBUG environment variable and re-compile to enable debug prints in synthesizable and DPI code!";
    EXTRA_DEFINES_XSC=""
else
    EXTRA_DEFINES="$EXTRA_DEFINES --define DEBUG"
    EXTRA_DEFINES_XSC="--gcc_compile_options \"-D DEBUG\""
fi

if [ -z "${SKIP_COMPILE+x}" ]; then
    # TODO currently no VHDL sources
    # xvhdl --2008 --log compile.log --lib uvm -f .tests_vhdl.f
    xvlog --sv --log compile.log --lib uvm -f .tests_vlog.f --define NORTHCAPE_TEST_COVERAGE --define XSIM $EXTRA_DEFINES top.sv
    # circular dependency: DPI library needs header, xelab needs DPI library
    xelab top -debug typical --sv_lib dpi --sc_root dpi/xsim.dir/work/xsc -dpiheader dpi/dpi.h -dpi_stacksize 65536 || true
    EXTRA_DEFINES_XSC=$EXTRA_DEFINES_XSC make -C dpi
    xelab top -debug typical --sv_lib dpi --sc_root dpi/xsim.dir/work/xsc -dpiheader dpi/dpi.h -dpi_stacksize 65536
else
    echo "Skipping compile";
fi

echo Launching Sim TPM

echo "Removing lock file"
rm .lockfile || true



if [ $# -eq 0 ]; then

    if [ -z "${LOGDIR+x}" ]; then 
        LOGDIR=$(mktemp -d)
    fi

    echo "Using log directory $LOGDIR"

    echo "No test specified - running all tests!";
    echo "Specify a test using argument -testplusarg \"UVM_TESTNAME=\<test_name\>\"";

    echo "Getting list of tests!"
    xsim --tclbatch ../scripts/tests/vivado_no_wave.tcl --R --log $LOGDIR/list_tests.log top

    . ../scripts/tests/northcape_get_registered_tests.sh

    TEST_LIST_RAW=$(get_registered_tests $LOGDIR/list_tests.log)

    export LOGDIR=$LOGDIR;

    rm .test_fail 2>&1 >/dev/null || true;

    parallel --jobs $CPUS ../scripts/tests/unittest_xsim_single_test.sh ::: $TEST_LIST_RAW;

    echo "Log output:";
    for single_test in $TEST_LIST_RAW;
    do
        echo "Test ${single_test}:";
        cat "$LOGDIR/${single_test}.log";
    done

    if [ -f .test_fail ];
    then
        echo "Test fail!";
        rm .test_fail;
        exit 1;
    fi

    echo "All tests passed!";
    echo "Generating coverage report!";
    generate_coverage_report $LOGDIR;

    unset LOGDIR
else
    echo "Assuming you specified a test to run!"
    if [ -z "${GUI_MODE+x}" ]; then
        xsim --tclbatch ../scripts/tests/vivado_waveconfig.tcl --R --log run.log -cov_db_name custom_test_cov top $@
    else
        xsim --tclbatch ../scripts/tests/vivado_waveconfig_debug.tcl -gui --R --log run.log -cov_db_name custom_test_cov top $@
    fi
    check_test_result run.log
fi
