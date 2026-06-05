.. _hello_world:

Subsystem Example
###########

Overview
********

A demonstrator for creating a protected subsystem and calling into it and returning a value to the caller.

Building and Running
********************

This application can be built and executed in the cv64a6 testbench as follows:

.. code-block:: console
   west build -p always -b cv64a6_testbench samples/boards/openhwgroup/cv64a6/subsystem_root_cap/
   ln -s $(pwd)/build/zephyr/zephyr.elf build/zephyr/zephyr.o
   python3 $CVA6_ROOT/verif/sim/cva6.py --elf_tests $ZEPHYR_ROOT/build/zephyr/zephyr.o  --iss_yaml cva6.yaml --target cv64a6_imafdc_sv39 --iss=veri-testharness --spike_params="/top/max_steps_enabled=y" $DV_OPTS


To build for another board, change "cv64a6_testbench" above to that board's name.