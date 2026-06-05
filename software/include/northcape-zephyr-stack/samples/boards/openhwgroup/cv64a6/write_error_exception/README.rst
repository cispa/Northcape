.. _hello_world:

Exception on write error example
###########

Overview
********

A sample for the cva6 simulator or the real FPGA. Writes an invalid capability, causing a bus error and expecting an exception.

Building and Running
********************

This application can be built and executed in the cv64a6 testbench as follows:

.. code-block:: console
   west build -p always -b cv64a6_testbench samples/boards/openhwgroup/cv64a6/write_error_exception/
   ln -s $(pwd)/build/zephyr/zephyr.elf build/zephyr/zephyr.o
   python3 $CVA6_ROOT/verif/sim/cva6.py --elf_tests $ZEPHYR_ROOT/build/zephyr/zephyr.o  --iss_yaml cva6.yaml --target cv64a6_imafdc_sv39 --iss=veri-testharness --spike_params="/top/max_steps_enabled=y" $DV_OPTS


To build for another board, change "cv64a6_testbench" above to that board's name.

Sample Output
=============

.. code-block:: console

    I: Initializing skadi memory management!
    I: Step 1 - Remove unusable physical address space at the end of the DRAM!
    I: Step 1 success - created capability 2d9bc00100000000!

    I: Step 2 - Create Skadi Arena with length 788529152 at end of DRAM!
    I: Step 2 success - created skadi arena 0x2403000200000000!
    I: Step 3 - Create loader's private heap with length 10485760 between remaining root capability and Northape Arena!
    I: Step 3 success - created loader's private heap 0x17b5400300000000!
    I: Setting mtvec!
    I: Got machine timer interrupt cap: 0xbb01404000040000
    I: Skadi memory management initialization complete with return status 0!
    ^[[B^[[B^[[B*** Booting Zephyr OS build v3.7.0-rc1-4460-gd6ece4b6acb5 ***
    [1883187] %Warning: ariane_testharness.sv:715: TOP.ariane_testharness.p_assert: R Response Errored with code 3
    E: 
    E:  mcause: 7, Store access fault
    E:   mtval: ffffffffffffffff
    E:      a0: 000000009b98395b    t0: ffffffff5eee86e4
    E:      a1: ffffffff805acbec    t1: ffffffffd2fd4367
    E:      a2: 00000000091f0046    t2: ffffffffa604a73c
    E:      a3: ffffffffebe7d904    t3: 00000000ad6cd8cb
    E:      a4: 000000007d02c934    t4: ffffffff525a32db
    E:      a5: ffffffffb7a25b1b    t5: ffffffff1219054e
    E:      a6: 000000001a7f7971    t6: ffffffff876f7742
    E:      a7: 000000008dd0b063
    E:      sp: ac0f0040000603f0
    E:      ra: ffffffffe061131c
    E:    mepc: 0000000080001d38
    E: mstatus: 0000000a00003880
    E: 
    E: call trace:
    E: 
    E: >>> ZEPHYR FATAL ERROR 0: CPU exception on CPU 0
    E: Current thread: 0x80013978 (main)
    E: Halting system

Exit QEMU by pressing :kbd:`CTRL+A` :kbd:`x`.
