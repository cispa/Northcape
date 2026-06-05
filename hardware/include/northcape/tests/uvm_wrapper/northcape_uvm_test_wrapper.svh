/**
 * Generates the boilerplate for a Northcape UVM test.
 */

`ifndef NORTHCAPE_UVM_TEST_WRAPPER
`define NORTHCAPE_UVM_TEST_WRAPPER

`include "uvm_macros.svh"
`define STRINGIFY(x) `"x`"
`define NORTHCAPE_UVM_TEST(NAME, ENV_TYPE)                                               \
        class automatic test_``NAME`` extends uvm_test;                                     \
            `uvm_component_utils(test_``NAME``);                                            \
                                                                                            \
            function new(string name={"test_",`STRINGIFY(NAME)},uvm_component parent);      \
                super.new(name,parent);                                                     \
                `uvm_info({"test_",`STRINGIFY(NAME)},"Test created",UVM_HIGH);              \
            endfunction                                                                     \
            ENV_TYPE env;                                                                   \
            function void build_phase(uvm_phase phase);                                     \
                super.build_phase(phase);                                                   \
                `uvm_info({"test_",`STRINGIFY(NAME)},"Test build",UVM_HIGH);                \
                env = new("env",this);                                                      \
            endfunction: build_phase                                                        \
                                                                                            \
                                                                                            \
            function void end_of_elaboration_phase(uvm_phase phase);                        \
                super.end_of_elaboration_phase(phase);

`define NORTHCAPE_UVM_TEST_END                                                          \
            endfunction                                                                     \
                                                                                            \
        endclass                                                                            
`endif
