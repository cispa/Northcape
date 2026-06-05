/**
  * Generic checker that compares two UVM sequence items and issues an error if they do not match.
  */
package northcape_generic_checker;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class NorthcapeGenericCheckerCompItem;
    const uvm_sequence_item actual;
    const uvm_sequence_item predicted;

    function new(uvm_sequence_item actual, uvm_sequence_item predicted);
      this.actual = actual;
      this.predicted = predicted;
    endfunction

  endclass

  class NorthcapeGenericChecker extends uvm_subscriber #(NorthcapeGenericCheckerCompItem);
    `uvm_component_utils(NorthcapeGenericChecker);

    localparam COMPONENT_NAME = "Northcape Generic Checker";

    function void write(NorthcapeGenericCheckerCompItem t);
      string data_str;

      data_str = {
        "Real result ",
        t.actual.convert2string(),
        " predicted result ",
        t.predicted.convert2string()
      };

      if (t.predicted.compare(t.actual)) begin
        `uvm_info(COMPONENT_NAME, {"Checker PASS: ", data_str}, UVM_HIGH);
      end else begin
        `uvm_error(COMPONENT_NAME, {"Checker FAIL: ", data_str});
      end

    endfunction : write

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

endpackage
