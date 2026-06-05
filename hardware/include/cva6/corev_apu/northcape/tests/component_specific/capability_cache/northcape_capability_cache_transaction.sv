/**
  * Transaction for capability cache.
  */
package northcape_capability_cache_transaction;

  import northcape_types::*;
  import northcape_test::*;
  import northcape_capability_cache_common::*;
  import northcape_capability_resolver_common::NorthcapeCapabilityResolverHash;
  import northcape_capability_resolver_common::HASH_TYPE_IDENTITY;
  import northcape_capability_cache_driver::NorthcapeCapabilityCacheResolverTransaction;
  import northcape_capability_cache_driver::NorthcapeCapabilityCacheOpsTransaction;


  import uvm_pkg::*;
  `include "uvm_macros.svh"


  class NorthcapeCapabilityCacheTransaction extends uvm_sequence_item;
    typedef NorthcapeCapabilityCacheTransaction my_type_t;


    localparam string COMPONENT_NAME = "Northcape Capability Cache Transaction";

    // to make sure we are repeating capability IDs at some point...
    localparam int MAX_CAPABILITY_ID = 128;

    rand northcape_capability_cache_arbitration_type_t active_port;

    rand capability_id_t request_capability_id;

    constraint request_capability_id_is_small {request_capability_id < MAX_CAPABILITY_ID;}
    capability_tag_t capability_tag;

    // only interpreted for ops port
    rand logic is_write;
    rand northcape_cmt_entry_t write_cmt_entry;
    rand logic write_request_flush;
    rand logic request_close_speculation_window;
    rand logic request_is_uncacheable;
    rand logic request_is_recursion;

    function new(string name = "");
      super.new(name);
    endfunction

    constraint not_both_flush_and_end_of_window {
      !(request_close_speculation_window && write_request_flush);
    }



    function void post_randomize();
      // should stay the same for capability IDs - otherwise, might break cache lookup logic
      capability_tag = NorthcapeCapabilityResolverHash#(HASH_TYPE_IDENTITY)::compute_hash_djb2(
          request_capability_id);
    endfunction


    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Copy RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      active_port = other_transaction.active_port;
      request_capability_id = other_transaction.request_capability_id;
      capability_tag = other_transaction.capability_tag;
      is_write = other_transaction.is_write;
      write_cmt_entry = other_transaction.write_cmt_entry;
      write_request_flush = other_transaction.write_request_flush;
      request_is_uncacheable = other_transaction.request_is_uncacheable;
      request_is_recursion = other_transaction.request_is_recursion;
    endfunction

    function string convert2string();

      return $sformatf(
          "Active port %s request capability ID %d capability tag %x is write %b write CMT entry %x write request flush %b ops uncacheable %b recursion %b",
          active_port.name(),
          request_capability_id,
          capability_tag,
          is_write,
          write_cmt_entry,
          write_request_flush,
          request_is_uncacheable,
          request_is_recursion
      );

    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "Compare RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return active_port == other_transaction.active_port &&
             request_capability_id == other_transaction.request_capability_id &&
             capability_tag == other_transaction.capability_tag &&
             is_write == other_transaction.is_write &&
             write_cmt_entry == other_transaction.write_cmt_entry &&
             write_request_flush == other_transaction.write_request_flush &&
             request_is_uncacheable == other_transaction.request_is_uncacheable &&
             request_is_recursion == other_transaction.request_is_recursion;
    endfunction

    /* NorthcapeCapabilityCacheResolverTransaction functions */

    function NorthcapeCapabilityCacheResolverTransaction to_resolver_transaction();
      NorthcapeCapabilityCacheResolverTransaction ret = new("Resolver transaction");

      if (active_port != NORTHCAPE_CAP_CACHE_RESOLVER) begin
        `uvm_fatal(COMPONENT_NAME, "Am no resolver transaction!");
      end

      ret.capability_tag = capability_tag;
      ret.request_capability_id = request_capability_id;
      ret.request_cache_flush = write_request_flush;
      ret.request_close_speculation_window = request_close_speculation_window;
      ret.request_is_recursion = request_is_recursion;
      return ret;
    endfunction

    /* NorthcapeCapabilityCacheOpsTransaction functions */
    function NorthcapeCapabilityCacheOpsTransaction to_ops_transaction();
      NorthcapeCapabilityCacheOpsTransaction ret = new("Ops transaction");
      if (active_port != NORTHCAPE_CAP_CACHE_OPS) begin
        `uvm_fatal(COMPONENT_NAME, "Am no ops transaction!");
      end
      ret.capability_tag = capability_tag;
      ret.request_capability_id = request_capability_id;
      ret.is_write = is_write;
      ret.write_cmt_entry = write_cmt_entry;
      ret.write_request_flush = write_request_flush;
      ret.request_is_uncacheable = request_is_uncacheable;
      return ret;

    endfunction




  endclass

endpackage
