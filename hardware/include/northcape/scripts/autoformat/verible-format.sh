#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd $SCRIPT_DIR/../..

FORMATABLE_FILES=$(find . -regextype sed -regex ".*\.s\{0,1\}vh\{0,1\}" | grep -v "./include/")

for file in $FORMATABLE_FILES;
do
    echo "Formatting file $file";
    verible-verilog-format --inplace $file;
done