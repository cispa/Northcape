# RAM config
echo Cloning OpenRAM to /tmp
# TODO changes not upstream yet
# original source: https://github.com/FriedrichWu/OpenRAM.git (same branch)
[ -d /tmp/OpenRAM ] || 	git clone -b add-doc --depth 1 https://github.com/WorldofJARcraft/OpenRAM.git /tmp/OpenRAM

if [ -f sram_northcape_32x128/sram_northcape_32x128.gds ] && [ -f sram_northcape_256x64/sram_northcape_256x64.gds ] && [ -f sram_hpdcache_64x128/sram_hpdcache_64x128.gds ];
then
    echo Using existing SRAM macro
else
    echo Generating SRAM macro
    export OPENRAM_HOME=/tmp/OpenRAM/compiler
    export OPENRAM_TECH=/tmp/OpenRAM/technology

    cp sram_northcape_32x128/sram_northcape_32x128.py /tmp/OpenRAM/
    cp sram_northcape_256x64/sram_northcape_256x64.py /tmp/OpenRAM/
    cp sram_hpdcache_64x128/sram_hpdcache_64x128.py /tmp/OpenRAM/


    ORIGINAL_DIR=$(pwd)

    cd /tmp/OpenRAM

    export PDK_ROOT=$(pwd)

    # TODO ciel not downloaded properly at the moment...
    make sky130-pdk || true
    make sky130-pdk
    make sky130-install


    ./install_conda.sh

    source miniconda/bin/activate
    conda install -y scikit-learn

    export OPENRAM_HOME=$(pwd)/compiler
    export OPENRAM_TECH=$(pwd)/technology
    
    echo "Generating SRAM 32x128"
    [ -f temp/sram_northcape_32x128.gds ] || ./sram_compiler.py sram_northcape_32x128.py
    cp temp/* $ORIGINAL_DIR/sram_northcape_32x128

    echo Adding missing .lib timing databases
    cp -v $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_FF_1p8V_25C.lib $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_FF_1p95V_40C.lib
    sed -i 's/FF_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_FF_1p95V_40C.lib
    
    cp -v $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_SS_1p8V_25C.lib $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_SS_1p6V_100C.lib
    sed -i 's/SS_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128_SS_1p6V_100C.lib
    
    echo "Generating SRAM 64x128"
    [ -f temp/sram_hpdcache_64x128.gds ] || ./sram_compiler.py sram_hpdcache_64x128.py
    cp temp/* $ORIGINAL_DIR/sram_hpdcache_64x128

    echo Adding missing .lib timing databases
    cp -v $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_FF_1p8V_25C.lib $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_FF_1p95V_40C.lib
    sed -i 's/FF_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_FF_1p95V_40C.lib
    
    cp -v $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_SS_1p8V_25C.lib $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_SS_1p6V_100C.lib
    sed -i 's/SS_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128_SS_1p6V_100C.lib

    echo "Generating SRAM 256x64"
    [ -f temp/sram_northcape_256x64.gds ] || ./sram_compiler.py sram_northcape_256x64.py
    cp temp/* $ORIGINAL_DIR/sram_northcape_256x64
    cd $ORIGINAL_DIR

    echo Adding missing .lib timing databases
    cp -v $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_FF_1p8V_25C.lib $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_FF_1p95V_40C.lib
    sed -i 's/FF_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_FF_1p95V_40C.lib

    cp -v $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_SS_1p8V_25C.lib $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_SS_1p6V_100C.lib
    sed -i 's/SS_1p8V_25C/FF_1p95V_40C/g' $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64_SS_1p6V_100C.lib

    echo "Fixing LEF units"
    # MICRONS of 2000 do not match MICRONS of 1000 defined for the technology
    # TODO this should not even be here anyway - https://github.com/google/skywater-pdk/issues/134
    sed -i 's/DATABASE MICRONS 2000 ;/DATABASE MICRONS 1000 ;/g' $ORIGINAL_DIR/sram_northcape_32x128/sram_northcape_32x128.lef
    sed -i 's/DATABASE MICRONS 2000 ;/DATABASE MICRONS 1000 ;/g' $ORIGINAL_DIR/sram_northcape_256x64/sram_northcape_256x64.lef
    sed -i 's/DATABASE MICRONS 2000 ;/DATABASE MICRONS 1000 ;/g' $ORIGINAL_DIR/sram_hpdcache_64x128/sram_hpdcache_64x128.lef
fi
