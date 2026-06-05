.. _hello_world:

Hello World
###########

Overview
********

A sample for the cva6 simulator or the real FPGA. Creates a small area at the end of the RAM that is then made a direct capability.
Makes sure that the capability can be read and written correctly.

Building and Running
********************

This application can be built and executed in the cv64a6 testbench as follows:

.. code-block:: console
   west build -p always -b cv64a6_testbench samples/boards/openhwgroup/cv64a6/sim_capability_test/
   ln -s $(pwd)/build/zephyr/zephyr.elf build/zephyr/zephyr.o
   python3 $CVA6_ROOT/verif/sim/cva6.py --elf_tests $ZEPHYR_ROOT/build/zephyr/zephyr.o  --iss_yaml cva6.yaml --target cv64a6_imafdc_sv39 --iss=veri-testharness --spike_params="/top/max_steps_enabled=y" $DV_OPTS


To build for another board, change "cv64a6_testbench" above to that board's name.

Sample Output
=============

.. code-block:: console

    Hello World! x86

Exit QEMU by pressing :kbd:`CTRL+A` :kbd:`x`.
