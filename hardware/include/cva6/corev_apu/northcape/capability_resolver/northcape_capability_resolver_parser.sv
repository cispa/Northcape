/**
  * Given a Northcape CMT Entry and a validate request, determines whether
  * the entry matches the request and the request is permissible.
  */
module northcape_capability_resolver_parser #(
    // device ID to be used for requesting recursion
    parameter northcape_types::device_id_t CAPABILITY_RESOLVER_RECURSION_DEVICE_ID=-1,
    parameter AXI_ADDR_WIDTH = -1,
    parameter AXI_DATA_WIDTH = -1,
    parameter bit CACHE_RECURSION_SKIP=1'b0
) (
    input logic clk_i,
    input logic rst_ni,
    // do we need to flush the cache? - needed for zero-cycle-skip
    output logic request_cache_flush_o,
    // can we close the speculation window? - efficiency improvement for zero-cycle-skip (cache only invalidates speculatively loaded entries instead of everything)
    output logic request_close_speculation_window_o,

    // validate request with embedded request entry, from lookup module
    Axis5.RECEIVER validate_request_entry,
    // validate request with capability ID and slot
    Axis5.TRANSMITTER validate_response,
    // validate request for recursion
    Axis5.TRANSMITTER validate_request_recursion
  );

    import northcape_types::*;
    import northcape_capability_resolver_common::*;
    import northcape_cmt_parser_pkg::*;

    `include "northcape_unread.vh"

    axis_validate_response_tdata_t response_tdata;
    capability_resolver_validate_request_with_entry_tdata_t request_tdata;

    axis_validate_request_tdata_t recursion_request_tdata;

    assign validate_response.tdata = response_tdata;
    assign request_tdata = validate_request_entry.tdata;

    northcape_lock_key_t lock_key;
    
    // global for debugging
    cmt_parser_verdict_t verdict;

    // for skidbuffer
    logic validate_request_recursion_ready;

    // we might deadlock the resolver when as many devices as the upstream master can accept transactions have made a request
    // and one of the requests is recursive
    // in this case, we need to accept the read response for the request where we recurse irregardless of whether the master can accept a new read request
    // to this end, we temporarily store it in a skidbuffer
    logic recursion_skidbuffer_used_q, recursion_skidbuffer_used_d;
    logic [$bits(axis_validate_request_tdata_t)-1:0] recursion_skidbuffer_q, recursion_skidbuffer_d;

    logic original_permission_tid_match;

    logic parent_in_bounds;

    always_ff @(posedge(clk_i), negedge(rst_ni)) begin: skidbufferFF
        if(rst_ni == 0)
        begin
            recursion_skidbuffer_used_q <= 0;
            recursion_skidbuffer_q <= '0;
        end
        else
        begin
            recursion_skidbuffer_used_q <= recursion_skidbuffer_used_d;
            recursion_skidbuffer_q <= recursion_skidbuffer_d;
        end
    end: skidbufferFF

    always_comb begin: skidbufferLogic
        recursion_skidbuffer_d = recursion_skidbuffer_q;
        recursion_skidbuffer_used_d = recursion_skidbuffer_used_q;

        if(validate_request_entry.tvalid)
        begin
            if(verdict == CMT_ENTRY_RECURSE)
            begin
                // recurse - write into recursion buffer
                recursion_skidbuffer_d = recursion_request_tdata;
                recursion_skidbuffer_used_d = 1'b1;
            end
            else
            begin
                // no recursion needed - clear the buffer
                recursion_skidbuffer_d = '0;
                recursion_skidbuffer_used_d = 1'b0;
            end
        end
        else
        begin
            if(validate_request_recursion.tready)
            begin
                // recursion request accepted - do not try again
                recursion_skidbuffer_used_d = 1'b0;
            end
        end
    end: skidbufferLogic


    assign parent_in_bounds = request_tdata.original_address + request_tdata.original_segment_length <= northcape_cmt_parser::entry_get_phys_addr(request_tdata.cmt_entry) + northcape_cmt_parser::entry_get_phys_length(request_tdata.cmt_entry) && request_tdata.original_address >= northcape_cmt_parser::entry_get_phys_addr(request_tdata.cmt_entry);

    always_comb begin: responseLogic
`ifdef DEBUG
        if(validate_request_entry.tvalid)
        begin
            $display("Validate request valid - checking CMT entry!");
        end
`endif
        // result is only *used* when cmt_entry is valid (and this is indicated with tvalid)
        verdict = northcape_cmt_parser::entry_matches_validate_request(request_tdata.cmt_entry,request_tdata.capability_id,request_tdata.tag,ACCESS_DERIVE_RECURSION,request_tdata.device_id,request_tdata.task_id,request_tdata.lock_key);

        // valid or ignored
        original_permission_tid_match = northcape_cmt_parser::entry_permission_allows_access(request_tdata.cmt_entry, request_tdata.access_type);
        original_permission_tid_match &= northcape_cmt_parser::entry_restriction_matches(request_tdata.cmt_entry, request_tdata.device_id, request_tdata.task_id, request_tdata.access_type) == CMT_ENTRY_MATCH;

        request_cache_flush_o = 1'b0;
        request_close_speculation_window_o = 1'b0;
        
        /*
         * Conditions for recursion skip:
         * - globally enabled - only possible with "real" resolver cache!
         * - cache was hit (if this was a miss, we must do a full recursion)
         * - capability is valid but needs recursion (straight match generates immediate response anyway, failure should generate failure response and flush the cache)
         * - we stop recursion at the first cache hit - from here on, the cache security invariant guarantees that the grandparent of that capability must be valid
         * - not a lock holder (need to recurse for length)
         */
        if(CACHE_RECURSION_SKIP == 1'b1 && request_tdata.response_cache_hit == 1'b1 && verdict == CMT_ENTRY_RECURSE && request_tdata.cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER)
        begin
            // we have done a full recursion for this entry before and it was valid
            // or it was just written by the resolver, and by its state machine, must be OK with its grandparent
            verdict = CMT_ENTRY_MATCH;
        end

        lock_key = northcape_cmt_parser::entry_get_lock_key(request_tdata.cmt_entry);

        recursion_request_tdata = '0;
        
        if((request_tdata.flags.have_base_length && request_tdata.flags.is_recursion))
        begin
            // already in recursion - keep effective address and length from parent
            recursion_request_tdata.original_address = request_tdata.original_address;
            recursion_request_tdata.original_segment_length = request_tdata.original_segment_length;
        end
        else
        begin
            // we are the top-level capability
            // or top-level lock holder without address information
            // we need to keep using its address and length, because it is the most restrictive
            recursion_request_tdata.original_address = northcape_cmt_parser::entry_get_phys_addr(request_tdata.cmt_entry);
            recursion_request_tdata.original_segment_length = northcape_cmt_parser::entry_get_phys_length(request_tdata.cmt_entry);
        end

        if(request_tdata.flags.is_recursion)
        begin
            // already in recursion - keep restrictions
            recursion_request_tdata.restriction = request_tdata.restriction;
            recursion_request_tdata.restriction_type = request_tdata.restriction_type;
            recursion_request_tdata.original_permissions = request_tdata.original_permissions;
            recursion_request_tdata.original_permission_tid_match = request_tdata.original_permission_tid_match;
        end
        else
        begin
            // forward from capability
            recursion_request_tdata.restriction = request_tdata.cmt_entry.restrictions.body;
            recursion_request_tdata.restriction_type = request_tdata.cmt_entry.restrictions.restriction_type;
            // the permissions we care about here ()
            recursion_request_tdata.original_permissions = request_tdata.cmt_entry.permissions;
            recursion_request_tdata.original_permission_tid_match = original_permission_tid_match;
        end


        if(request_tdata.cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER)
        begin
            if(request_tdata.flags.have_lock_key == 1'b1)
            begin
                // lock key higher in the hierarchie takes precedence
                recursion_request_tdata.lock_key = request_tdata.lock_key;
            end
            else
            begin
                // first lock holder in the hierarchie
                recursion_request_tdata.lock_key = lock_key;
            end
        end
        else
        begin
            recursion_request_tdata.lock_key = request_tdata.lock_key;
        end

        recursion_request_tdata.address = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_id(northcape_cmt_parser::entry_get_parent_token(request_tdata.cmt_entry));
        recursion_request_tdata.tag = capability_accessors#(AXI_ADDR_WIDTH)::capability_get_tag(northcape_cmt_parser::entry_get_parent_token(request_tdata.cmt_entry));
        // by design, derived cap's must be as least as restrictive as their parents
        // can forward access type if it was valid
        recursion_request_tdata.access_type = ACCESS_DERIVE_RECURSION;

        recursion_request_tdata.device_id = request_tdata.device_id;
        recursion_request_tdata.task_id = request_tdata.task_id;

        recursion_request_tdata.flags.is_recursion = 1'b1;
        recursion_request_tdata.flags.have_base_length = request_tdata.flags.have_base_length || (request_tdata.cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER);
        recursion_request_tdata.flags.have_lock_key = request_tdata.flags.have_lock_key || (request_tdata.cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER);
        recursion_request_tdata.flags.reserved = '0;

        response_tdata.restriction = '0;
        response_tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
        response_tdata.permissions = '0;
        response_tdata.error_code = NORTHCAPE_RESOLVE_NO_ERROR;

        unique case(verdict)
            CMT_ENTRY_FAIL_TAG: response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_TAG;
            CMT_ENTRY_FAIL_PERMISSIONS: response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_PERMISSIONS;
            CMT_ENTRY_FAIL_RESTRICTIONS: response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
            CMT_ENTRY_FAIL_CAP_TYPE: response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_CAP_TYPE;
            CMT_ENTRY_FAIL_LOCKED: response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_LOCKED;
            default: response_tdata.error_code = NORTHCAPE_RESOLVE_NO_ERROR;
        endcase       
        
        unique case(verdict)
            CMT_ENTRY_MATCH:
            // reached last grandparent - can assemble response
            begin
                unique case({request_tdata.flags.have_base_length,request_tdata.flags.is_recursion})
                    2'b00:
                    begin
                        // no recursion - forward from current CMT
                        response_tdata.address = northcape_cmt_parser::entry_get_phys_addr(request_tdata.cmt_entry);
                        response_tdata.segment_length = northcape_cmt_parser::entry_get_phys_length(request_tdata.cmt_entry);
                        // in the same place for direct and indirect
                        response_tdata.permissions = request_tdata.cmt_entry.permissions;

                        response_tdata.restriction = request_tdata.cmt_entry.restrictions.body;
                        response_tdata.restriction_type = request_tdata.cmt_entry.restrictions.restriction_type;

                        if(original_permission_tid_match == 1'b0)
                        begin
                            // invalid task ID or permissions
                            // by our interface contract, we have to indicate an error to the MMU
                            // however, cache invariant is held (grandparent is valid) --> no need to flush L2 cache / can close speculation window
                            response_tdata.address = '0;
                            response_tdata.segment_length = '0;
                            response_tdata.permissions = '0;
                            response_tdata.restriction = '0;
                            response_tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
                            response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
                        end
                    end
                    2'b01:
                    begin
                        // recursion with no base length - bounds from this capability, restrictions and cacheable from recursion request
                        response_tdata.address = northcape_cmt_parser::entry_get_phys_addr(request_tdata.cmt_entry);
                        response_tdata.segment_length = northcape_cmt_parser::entry_get_phys_length(request_tdata.cmt_entry);

                        // no need to check parents_in_bounds - we only get here if the first capability was a lock holder, which has no bounds
                        response_tdata.permissions = request_tdata.original_permissions;

                        response_tdata.restriction = request_tdata.restriction;
                        response_tdata.restriction_type = request_tdata.restriction_type;

                        if(request_tdata.original_permission_tid_match == 1'b0)
                        begin
                            // invalid task ID or permissions for top capability (this capability is the parent, its permissions/restrictions do not matter)
                            // by our interface contract, we have to indicate an error to the MMU
                            // however, cache invariant is held (grandparent is valid) --> no need to flush L2 cache / can close speculation window
                            response_tdata.address = '0;
                            response_tdata.segment_length = '0;
                            response_tdata.permissions = '0;
                            response_tdata.restriction = '0;
                            response_tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
                            response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
                        end
                    end
                    default:
                    // have_base_length implies recursion - can combine the cases
                    begin
                        // recursion with bounds from previous capability
                        // as a sanity check (root capability create with refcount!) we check that the child bounds are within the parent bounds
                        response_tdata.address = parent_in_bounds ? request_tdata.original_address : '0;
                        response_tdata.segment_length = parent_in_bounds ? request_tdata.original_segment_length : '0;
                        response_tdata.permissions = parent_in_bounds ? request_tdata.original_permissions : '0;

                        if(~parent_in_bounds)
                        begin
                            response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_BOUNDS;
                        end

                        response_tdata.restriction = parent_in_bounds ? request_tdata.restriction : '0;
                        response_tdata.restriction_type = parent_in_bounds ? request_tdata.restriction_type : NORTHCAPE_RESTRICTIONS_NONE;

                        if(request_tdata.original_permission_tid_match == 1'b0)
                        begin
                            // invalid task ID or permissions for top capability (this capability is the parent, its permissions/restrictions do not matter)
                            // by our interface contract, we have to indicate an error to the MMU
                            // however, cache invariant is held (grandparent is valid) --> no need to flush L2 cache / can close speculation window
                            response_tdata.address = '0;
                            response_tdata.segment_length = '0;
                            response_tdata.permissions = '0;
                            response_tdata.restriction = '0;
                            response_tdata.restriction_type = NORTHCAPE_RESTRICTIONS_NONE;
                            response_tdata.error_code = NORTHCAPE_RESOLVE_ERROR_RESTRICTIONS;
                        end
                    end
                endcase
                // used for routing back to the MMU (or ourselves)

                // either direct capability, successful recursion or recursion skip - current state of cache matches invariant
                request_close_speculation_window_o = CACHE_RECURSION_SKIP && validate_request_entry.tvalid;

                // handshaking: forwarded to/from memory stage
                validate_response.tvalid = validate_request_entry.tvalid;
                // well-behaved MMU should be ready here
                assert(validate_response.tready);
            end
            CMT_ENTRY_RECURSE:
            begin
                response_tdata.address = '0;
                response_tdata.segment_length = '0;
                response_tdata.permissions = '0;

                assert(validate_request_recursion_ready);

                validate_response.tvalid = 0;
            end
            // CMT_ENTRY_FAIL* and possibly unknown
            default:
            begin
                response_tdata.address = '0;
                response_tdata.segment_length = '0;
                response_tdata.permissions = '0;
                // when we are always fully recursing, there is no need to flush the cache on error
                // errors sometimes occur, e.g., due to CPU speculation...
                request_cache_flush_o = validate_request_entry.tvalid & CACHE_RECURSION_SKIP;
                // error response
                // handshaking: forwarded to/from memory stage
                validate_response.tvalid = validate_request_entry.tvalid;
                // well-behaved MMU should be ready here
                assert(validate_response.tready);
            end

        endcase 
        /* error code from cache takes precedence, closer to the source of the problem */
        if(request_tdata.error_code != NORTHCAPE_RESOLVE_NO_ERROR)
        begin
            response_tdata.error_code = request_tdata.error_code;
        end

        
        validate_response.tdest = request_tdata.device_id;       

        // default signals
        validate_response.tstrb = '1;
        validate_response.tkeep = '1;
        validate_response.tuser = '0;
        validate_response.tid = '0;
        validate_response.tlast = 1;
        validate_response.twakeup = 1;

    end:responseLogic

    always_comb begin: recursionRequestLogic

        // always needs to go through skidbuffer - otherwise, combinatorial loop
        validate_request_recursion.tdata = recursion_skidbuffer_q;
        validate_request_recursion.tvalid = recursion_skidbuffer_used_q;
        

        validate_request_recursion_ready = !recursion_skidbuffer_used_q;

        if(validate_request_entry.tvalid && request_tdata.access_type == ACCESS_DERIVE_RECURSION)
        begin
            // we are clearing the current recursion request with this update
            validate_request_recursion_ready = 1'b1;
        end

        validate_request_recursion.tdest = CAPABILITY_RESOLVER_RECURSION_DEVICE_ID;
        validate_request_recursion.tstrb = '1;
        validate_request_recursion.tkeep = '1;
        validate_request_recursion.tuser = '0;
        validate_request_recursion.tid = '0;
        validate_request_recursion.tlast = 1;
        validate_request_recursion.twakeup = 1;
    end: recursionRequestLogic

    always_comb begin: requestReadyLogic
        // we do not know whether the request will be final or recursion
        // for recursion, need to be able to buffer the request (skidbuffer not used) OR immediately forward this / last recursion request back to input
        // for final request, need to have response ready
        validate_request_entry.tready = (validate_request_recursion.tready || !recursion_skidbuffer_used_q) && validate_response.tready;
    end: requestReadyLogic

`ifdef NORTHCAPE_TEST_COVERAGE
    covergroup cmt_entry_covergroup @(posedge clk_i);
        capability_type: coverpoint request_tdata.cmt_entry.capability_type;
        locked: coverpoint lock_key{
            bins not_locked = {64'h0};
            wildcard bins locked = {64'h????????????????};
        }
        restriction_type: coverpoint request_tdata.cmt_entry.restrictions.restriction_type;
        restriction_task_id: coverpoint request_tdata.cmt_entry.restrictions.body.task_restriction.task_id{
            wildcard bins task_ids={16'h????} iff request_tdata.cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND || request_tdata.cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
        }
        restriction_dev_id: coverpoint request_tdata.cmt_entry.restrictions.body.task_restriction.device_id{
            wildcard bins dev_ids={16'h????} iff request_tdata.cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_TASK_ID_BOUND || request_tdata.cmt_entry.restrictions.restriction_type == NORTHCAPE_RESTRICTIONS_SET_TASK_ID;
        }
        refcount: coverpoint request_tdata.cmt_entry.refcount;

        read_perm: coverpoint request_tdata.cmt_entry.permissions.direct_capability_permissions.read_permission;
        write_perm: coverpoint request_tdata.cmt_entry.permissions.direct_capability_permissions.write_permission;
        x_perm: coverpoint request_tdata.cmt_entry.permissions.direct_capability_permissions.execute_permission;

        lockable: coverpoint request_tdata.cmt_entry.permissions.direct_capability_permissions.lockable_permission{
            wildcard bins lockables={1'b?} iff request_tdata.cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT;
        }

        cow: coverpoint request_tdata.cmt_entry.permissions.direct_capability_permissions.irq_accessible_permission{
            wildcard bins cows={1'b?} iff request_tdata.cmt_entry.capability_type == NORTHCAPE_CMT_DIRECT;
        }

        all_data_flow_attrs: cross capability_type, locked, restriction_type, restriction_task_id, restriction_dev_id, refcount, read_perm, write_perm, x_perm, lockable, cow;
    endgroup

    cmt_entry_covergroup cov_group;
    initial begin
        cov_group = new;
    end
`endif

    `NORTHCAPE_UNREAD(validate_request_entry.clk_i);
    `NORTHCAPE_UNREAD(validate_request_entry.rst_ni);
    `NORTHCAPE_UNREAD(validate_request_entry.tdata);
    `NORTHCAPE_UNREAD(validate_request_entry.tstrb);
    `NORTHCAPE_UNREAD(validate_request_entry.tkeep);
    `NORTHCAPE_UNREAD(validate_request_entry.tdest);
    `NORTHCAPE_UNREAD(validate_request_entry.tid);
    `NORTHCAPE_UNREAD(validate_request_entry.tlast);
    `NORTHCAPE_UNREAD(validate_request_entry.tuser);
    `NORTHCAPE_UNREAD(validate_request_entry.twakeup);

    `NORTHCAPE_UNREAD(validate_response.clk_i);
    `NORTHCAPE_UNREAD(validate_response.rst_ni);

    `NORTHCAPE_UNREAD(validate_request_recursion.clk_i);
    `NORTHCAPE_UNREAD(validate_request_recursion.rst_ni);

    // would form a combinatorical loop if we used it
    `NORTHCAPE_UNREAD(validate_request_recursion.tready);
    `NORTHCAPE_UNREAD(validate_response.tready);
    
endmodule
