/**
 * Top-level module for verification.
 */
module top;

  // unit test packages
  import northcape_mmu_unit_test::*;
  import northcape_confused_deputy_dma_unit_test::*;
  import northcape_capability_resolver_unit_test::*;
  import northcape_capability_ops_unit_test::*;
  import northcape_integration_unit_test::*;
  import northcape_cva6_mmu_unit_test::*;

  // randomized test packages
  import northcape_mmu_randomized_test::*;
  import northcape_confused_deputy_dma_randomized_test::*;
  import northcape_capability_resolver_randomized_test::*;
  import northcape_reg_interface_randomized_test::*;
  import northcape_fifo_randomized_test::*;
  import northcape_capability_ops_randomized_test::*;
  import northcape_integration_randomized_test::*;
  import northcape_cva6_mmu_randomized_test::*;
  import northcape_capability_cache_randomized_test::*;

  // corresponding modules with the DUTs
  northcape_mmu_top i_mmu_top ();
  northcape_confused_deputy_dma_top i_dma_top ();
  northcape_capability_resolver_top i_capability_resolver_top ();
  northcape_capability_ops_top i_capability_ops_top ();
  northcape_reg_interface_top i_reg_interface_top ();
  northcape_fifo_top i_fifo_top ();
  northcape_integration_top i_integration_top ();
  northcape_cva6_mmu_top i_cva6_mmu_top ();
  northcape_capability_cache_top i_cache_top ();

  initial begin
    automatic uvm_report_server srvr;

    srvr = uvm_report_server::get_server();

    uvm_top.finish_on_completion = 0;

`ifdef DEBUG
    srvr.set_max_quit_count(2);
`endif

    // overwritten with testplusarg UVM_TESTNAME if needed
    run_test("test_northcape_discover_tests");

    if (srvr.get_severity_count(UVM_ERROR) != 0 || srvr.get_severity_count(UVM_FATAL) != 0) begin
      $display("Test error!");
      $fatal(1);
    end else begin
      $display("Test OK");
    end


    $finish();
  end
endmodule
