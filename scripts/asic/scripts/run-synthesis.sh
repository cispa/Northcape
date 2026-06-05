#!/bin/bash
set -e
set -x

SCRIPT_DIR="$( dirname -- "${BASH_SOURCE[0]}"; )";   # Get the directory name
SCRIPT_DIR="$( realpath -e -- "$SCRIPT_DIR"; )";    # Resolve its full path if need be

cd $SCRIPT_DIR

DIRS="mmu capability_cache capability_ops capability_resolver cva6/cva6_asic cva6/cva6_northcape"

echo "Running component builds in parallel"
parallel bash ./run-synthesis-component.sh ::: $DIRS 2>&1 > synth_log.txt

cd ..

echo "Component builds done! Printing results!"
for dir in $DIRS;
do
    cd $dir
    echo "FMAX results - $dir"
    grep fmax runs/RUN_*/*-openroad-stapostpnr/nom_tt_025C_1v80/clock.rpt || true
    echo "Area results - $dir"
    # last step where changes to the design are made, and before unused area of the assigned mask is filled
    grep -A 12 "Cell type report" runs/RUN_*/*-openroad-repairantennas/1-diodeinsertion/diodeinsertion.log || true
    echo "Remember to report everything except fill, tap cells!"
    echo "Copying .gds2 mask and logs to $dir for build artifact"
    # might be multiple, from different tools, with the same name - should all be equivalent
    cp -v $(find . -name *verilog.gds | head -1) . || true
    cp -v runs/RUN_*/*-openroad-repairantennas/1-diodeinsertion/diodeinsertion.log . || true
    cp -v runs/RUN_*/*-openroad-stapostpnr/nom_tt_025C_1v80/clock.rpt . || true
    cd $SCRIPT_DIR
    cd ..
done


