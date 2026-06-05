/**
 * Interface that bundles I/O signals for testing cva6 MMU. Only used for testing as of now.
 */

interface NorthcapeCva6MMUInterface #(
    parameter AXI_ADDR_WIDTH = -1
) (
    input logic clk_i,
    input logic rst_ni
);

  import northcape_types::*;

  logic [AXI_ADDR_WIDTH-1:0] data_address;
  logic data_is_store;
  logic data_is_atomic;
  logic [$clog2(AXI_ADDR_WIDTH/8)-1:0] data_access_size;
  logic data_is_immediate;
  logic data_is_irq;
  logic data_is_valid;
  logic data_is_branch_predict;
  logic data_is_mispredict;
  logic data_is_correct_predict;

  logic [AXI_ADDR_WIDTH-1:0] translated_address;
  logic translation_error;
  logic translation_valid;
  logic translation_hit;
  logic translation_requires_non_cacheable;
  northcape_device_interpreted_restriction_t translation_device_interpreted;

  logic is_subsystem_call;
  logic is_subsystem_call_self;

  task_id_t task_id_irq;
  task_id_t task_id_non_irq;
`ifndef VERILATOR
  clocking output_clocking @(posedge (clk_i));
    input data_address;
    input data_is_store;
    input data_is_atomic;
    input data_access_size;
    input data_is_immediate;
    input data_is_irq;
    input data_is_valid;
    input data_is_branch_predict;
    input data_is_mispredict;
    input data_is_correct_predict;

    input task_id_irq;
    input task_id_non_irq;

    output translated_address;
    output translation_error;
    output translation_valid;
    output translation_hit;
    output translation_device_interpreted;
    output translation_requires_non_cacheable;
  endclocking

  modport CVA6(clocking output_clocking);

  clocking input_clocking @(posedge (clk_i));
    output data_address;
    output data_is_store;
    output data_is_atomic;
    output data_access_size;
    output data_is_immediate;
    output data_is_irq;
    output data_is_valid;
    output data_is_branch_predict;
    output data_is_mispredict;
    output data_is_correct_predict;

    input task_id_irq;
    input task_id_non_irq;

    input translated_address;
    input translation_error;
    input translation_valid;
    input translation_hit;
    input translation_requires_non_cacheable;
    input translation_device_interpreted;
  endclocking

  modport CVA6_MMU(clocking input_clocking);

`endif
endinterface
