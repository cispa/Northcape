#!/bin/sh

set -e

cd ../scripts/tests

. ./vivado_check_output.sh

cd ../../tests

single_test=$1;

mkdir ${single_test}_xsim_dir 2>&1 >/dev/null || rm -r ${single_test}_xsim_dir/*
cp -r xsim.dir ${single_test}_xsim_dir

echo "Running test $single_test ... with log dir $LOGDIR";
xsim --R --log "$LOGDIR/${single_test}.log" -cov_db_name "${single_test}_cov" -xsimdir ${single_test}_xsim_dir top -testplusarg "UVM_TESTNAME=$single_test" -testplusarg "UVM_VERBOSITY=UVM_MEDIUM";

rm -r ${single_test}_xsim_dir
check_test_result "$LOGDIR/${single_test}.log";
echo "Test $single_test done";