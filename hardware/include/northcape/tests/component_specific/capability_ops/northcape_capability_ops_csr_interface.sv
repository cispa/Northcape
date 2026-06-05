/**
 * Interface that bundles input/output structs for ops' CSR interface.
 */

interface NorthcapeCapabilityOpsCsrIntf (
    input logic clk_i
);

  import northcape_types::*;

  northcape_cap_ops_rcsr_req_t  request;
  northcape_cap_ops_rcsr_resp_t response;

`ifndef VERILATOR
  clocking csr_clocking @(posedge (clk_i));
    output request;
    input response;
  endclocking

  modport CSR(clocking csr_clocking);

  clocking ops_clocking @(posedge (clk_i));
    input request;
    output response;
  endclocking

  modport OPS_MODULE(clocking ops_clocking);

`endif
endinterface
