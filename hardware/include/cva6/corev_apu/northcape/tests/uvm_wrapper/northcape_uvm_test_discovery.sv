/**
 * Prints a list of UVM tests that are compiled in.
 */
package uvm_test_discovery;
    `include "northcape_uvm_test_wrapper.svh"
    import uvm_pkg::*;


    class uvm_test_discovery_env extends uvm_env;
        
        function new(string name = "", uvm_component parent);
            super.new(name, parent);
        endfunction

    endclass

    // uvm has no built-in way of running all tests
    // this test queries all registered tests from the factory
    // we use this in a shell script to run all tests
    `NORTHCAPE_UVM_TEST(northcape_discover_tests,uvm_test_discovery_env)
        $display("========= Test List Start =========");
        uvm_factory::get().print();
        $display("========= Test List End =========");
    `NORTHCAPE_UVM_TEST_END
endpackage
