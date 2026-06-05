#!/bin/bash

# build-app.sh <board> <sample> <outfile name> <extra build args...>

set -e
set -x

# parallel always quotes this...
IFS=" " read -ra argument_array <<< "$1"

BOARD=${argument_array[0]}

SAMPLE=${argument_array[1]}

OUTFILE_NAME=${argument_array[2]}

argument_array=("${argument_array[@]:3}")

DIRNAME="build_${BOARD}_${OUTFILE_NAME}"

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

source .venv/bin/activate

west build -d $DIRNAME -p always -b $BOARD $SAMPLE ${argument_array[@]} 2>&1

mv $DIRNAME/zephyr/zephyr.bin $OUTFILE_NAME.bin
mv $DIRNAME/zephyr/zephyr.elf $OUTFILE_NAME.elf    
