#!/bin/bash
TEST_NAME=$1
TEST_FILE="../../tests/axi_tests.txt"

if [ -z "$TEST_NAME" ];
then
    TEST_NAME="Dummy";
fi

echo "\`SVTEST($TEST_NAME)"

grep -v -e "'{" -e "Test Request End" $TEST_FILE

grep "'{" $TEST_FILE | sed -r "s/([[:digit:]][[:digit:]][[:digit:]][[:digit:]][[:digit:]]*)/64'd\1/g"

grep "Test Request End" $TEST_FILE

echo "\`SVTEST_END"