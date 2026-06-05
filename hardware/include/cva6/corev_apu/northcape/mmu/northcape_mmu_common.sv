/**
  * Common functions for the Northcape MMU.
  */

//===================================
// Common Types
//===================================
package northcape_mmu_common;

  import northcape_types::*;
  import axi5::*;

  class NorthcapeMMUBarrelShifter #(
      parameter SHIFT_WIDTH = -1,
      parameter SHIFT_MAX_AMOUNT = -1
  );
    static function automatic logic [SHIFT_WIDTH-1:0] barrel_shift(
        logic [SHIFT_WIDTH-1:0] data, bit [SHIFT_MAX_AMOUNT-1:0] amount, bit direction_is_left);
      logic [2*SHIFT_WIDTH-1:0] extended_data = {data, data}, shifted_data;
      logic [SHIFT_WIDTH-1:0] shifted_out_bits_mask;

      if (direction_is_left) begin
        shifted_data = extended_data << amount;
        return shifted_data[2*SHIFT_WIDTH-1:SHIFT_WIDTH];
      end else begin
        shifted_data = extended_data >> amount;
        return shifted_data[SHIFT_WIDTH-1:0];
      end
    endfunction
  endclass

  class automatic NorthcapeMMUCommon #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ID_WIDTH = -1,
      parameter AXI_USER_WIDTH = -1,
      parameter ACCEPT_AXI_WRAP_BURSTS = 1,
      parameter bit IS_WRITE_CHAN = 0
  );

    // in an instruction fetch, if the read is not permissible, we return C.EBREAK instructions instead of all-zeros
    // thereby, if the CPU actually tries to execute the instruction (not always the case, e.g., in case of branch mispredict),
    // it stalls, pointing to the problem
    // and we avoid spurious errors due to misspredicts
    localparam logic [15:0] RISCV_C_EBREAK = 16'h9002;
    localparam logic [AXI_DATA_WIDTH-1:0] INSTRUCTION_FETCH_ERROR_RESP = {AXI_DATA_WIDTH{RISCV_C_EBREAK}};

    `include "northcape_mmu_definitions.svh"

    static function bit resolved_address_overlaps_cmt(
        bit [AXI_ADDR_WIDTH-1:0] cmt_base_addr, int unsigned cmt_size_clog2,
        bit [AXI_ADDR_WIDTH-1:0] request_start_addr, int unsigned bytes_in_burst);

      bit [AXI_ADDR_WIDTH-1:0] cmt_end_addr;
      bit [AXI_ADDR_WIDTH-1:0] request_end_addr;

      cmt_end_addr = cmt_base_addr + (1 << cmt_size_clog2) * ($bits(northcape_cmt_entry_t) / 8);
      request_end_addr = request_start_addr + bytes_in_burst;

      if (request_start_addr <= cmt_base_addr && request_end_addr >= cmt_base_addr) begin
        // burst INTO CMT
        return 1;
      end
      if (request_start_addr >= cmt_base_addr && request_start_addr <= cmt_end_addr) begin
        // start in CMT, does not matter if request is fully contained or not
        return 1;
      end
      return 0;

    endfunction

    static function automatic int unsigned getBytesInBurst(
        input axi_size_t last_burst_size, input axi_burst_t last_burst_type,
        input axi_len_t last_burst_len, input axi_bus_addr_t last_burst_addr,
        input logic [7:0] decoded_burst_size);
      axi_bus_addr_t wrap_start_addr, wrap_end_addr;

      unique case (last_burst_type)
        INCR: begin
          // burst starts at a base address and increments by bus width in every burst
          // bursts are also implicitly 1 byte longer than indicated
          return ({24'h0, last_burst_len} + 1) * decoded_burst_size;
        end
        FIXED: begin
          // burst reads the same address over and over
          return {24'h0, decoded_burst_size};
        end
        WRAP: begin
          if (ACCEPT_AXI_WRAP_BURSTS) begin
            axi_bus_addr_t diff_addr;
            bit length_is_allowed;

            length_is_allowed = 0;


            for (int i = 0; i < $size(AXI5_WRAP_VALID_LENGTHS); i = i + 1) begin
              if (AXI5_WRAP_VALID_LENGTHS[i] == last_burst_len) begin
                length_is_allowed = 1;
              end else begin
`ifdef DEBUG
                $display("Wrap length is not allowed!");
`endif
              end
            end
            // wraps are always confined to a word-alined "cache line"
            // the access can start with any address in the cache line
            // the bus then proceeds to return all of the bytes in the cache line
            wrap_start_addr = axi5_address_calculations #(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_start_address(
                last_burst_len, last_burst_size, last_burst_addr);
            wrap_end_addr = axi5_address_calculations #(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_end_address(
                last_burst_len, last_burst_size, last_burst_addr);
            diff_addr = wrap_end_addr - wrap_start_addr + 1;
            // plus one to account for start address
            return length_is_allowed ? diff_addr[31:0] : '1;
          end else begin
`ifdef DEBUG
            $display("Wrap is not allowed!");
`endif
            return '1;
          end
        end
        default:
        // not implemented or invalid
        return '1;

      endcase
    endfunction

    static function automatic segment_size_correction_t computeSegmentSizeCorrection(
        input logic [7:0] decoded_burst_size, input axis_validate_response_tdata_t response_tdata);
      // these can overflow to 8...
      byte_in_burst_count_t segment_size_correction_first, segment_size_correction_last;
      int unsigned segment_size_correction_first_full_prec, segment_size_correction_last_full_prec;

      // bytes not actually read in last segment
      segment_size_correction_last_full_prec = {24'h0, decoded_burst_size} - (response_tdata.segment_length % {24'h0, decoded_burst_size});
      // bytes not actually read in first segment
      segment_size_correction_first_full_prec = response_tdata.address % {24'h0, decoded_burst_size};

      segment_size_correction_last =
          segment_size_correction_last_full_prec[$clog2(AXI_DATA_WIDTH/8)-1:0];
      segment_size_correction_first =
          segment_size_correction_first_full_prec[$clog2(AXI_DATA_WIDTH/8)-1:0];
      // if the first segment is not aligned with the beginning, we can read one extra burst after what would otherwise be the last; however, we must be careful not to double-count the end correction
      return segment_size_correction_first + segment_size_correction_last + (segment_size_correction_first != 0 ? AXI_DATA_WIDTH/8-segment_size_correction_last  : 0);
    endfunction


    static function automatic mmu_state_t get_next_state_in_wrap(
        axi_bus_addr_t next_wrap_addr, axi_bus_addr_t wrap_start, axi_bus_addr_t last_segment_start,
        axi_bus_addr_t last_segment_end);
      // masks align address with first or last byte in the corresponding word line
      axi_bus_addr_t in_word_addr_bits_set_mask;
      axi_bus_addr_t in_word_addr_bits_clear_mask;

      axi_bus_addr_t low_byte_low_boundary;
      axi_bus_addr_t high_byte_low_boundary;
      axi_bus_addr_t low_byte_high_boundary;
      axi_bus_addr_t high_byte_high_boundary;

      axi_bus_addr_t wrap_end_aligned;

      in_word_addr_bits_set_mask = ((1 << $clog2(AXI_DATA_WIDTH / 8)) - 1);
      in_word_addr_bits_clear_mask = ~((1 << $clog2(AXI_DATA_WIDTH / 8)) - 1);

      low_byte_low_boundary = last_segment_start & in_word_addr_bits_clear_mask;
      high_byte_low_boundary = last_segment_start | in_word_addr_bits_set_mask;
      low_byte_high_boundary = last_segment_end & in_word_addr_bits_clear_mask;
      high_byte_high_boundary = last_segment_end | in_word_addr_bits_set_mask;


      wrap_end_aligned = wrap_start & in_word_addr_bits_clear_mask;

      // wrap always starts at the same word as the originally indicated address
      // segment can start and end anywhere within the wrap
      // wrap address is aligned after first access, but this need not be true for the starting address
      if ((next_wrap_addr & in_word_addr_bits_clear_mask) == wrap_end_aligned) begin
        // have completed wrap
        return WAIT_COMPLETE;
      end

      if (next_wrap_addr < low_byte_low_boundary || next_wrap_addr > high_byte_high_boundary) begin
        // wrap takes us outside segment
        return FORWARD_DATA_ZERO_OUT;
      end  // wrap is somewhere in the segment
      else if (next_wrap_addr <= high_byte_low_boundary) begin
        // wrap is at start of segment
        return FORWARD_DATA_FIRST_TRANSACTION;
      end else if (next_wrap_addr >= low_byte_high_boundary) begin
        // wrap is at end of segment
        return FORWARD_DATA_LAST_TRANSACTION;
      end else begin
        // wrap is somewhere in the middle of the segment
        return FORWARD_DATA;
      end
    endfunction

    static function automatic axi_bus_addr_t get_next_wrap_addr(
        axi_bus_addr_t last_wrap_addr, axi_len_t last_burst_len, axi_size_t last_burst_size);
      axi_bus_addr_t next_wrap_addr, wrap_start_addr, wrap_end_addr, increment;
      axi_bus_addr_t in_word_addr_bits_clear_mask;


      in_word_addr_bits_clear_mask = ~((1 << $clog2(AXI_DATA_WIDTH / 8)) - 1);

      increment = 1 << last_burst_size;
      // starting from the second access, wrap address needs to be aligned to word
      next_wrap_addr = last_wrap_addr & in_word_addr_bits_clear_mask;

      next_wrap_addr = next_wrap_addr + increment;
      wrap_start_addr = axi5_address_calculations #(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_start_address(
          last_burst_len, last_burst_size, last_wrap_addr);
      wrap_end_addr = axi5_address_calculations #(AXI_ADDR_WIDTH)::axi5_wrapped_burst_get_end_address(
          last_burst_len, last_burst_size, last_wrap_addr);

      if (next_wrap_addr > wrap_end_addr) begin
        next_wrap_addr = wrap_start_addr;
      end

      return next_wrap_addr;
    endfunction

    static function automatic axi_bus_addr_t get_next_incr_addr(axi_bus_addr_t last_wrap_addr,
                                                                axi_size_t last_burst_size);
      return last_wrap_addr + (1 << last_burst_size);
    endfunction

    static function automatic axi_bus_addr_t get_next_fixed_addr(axi_bus_addr_t last_wrap_addr);
      return last_wrap_addr;
    endfunction

    static function automatic axi_bus_addr_t get_next_addr(
        axi_burst_t burst_type, axi_bus_addr_t last_wrap_addr, axi_len_t last_burst_len,
        axi_size_t last_burst_size);
      unique case (burst_type)
        WRAP: return get_next_wrap_addr(last_wrap_addr, last_burst_len, last_burst_size);
        INCR: return get_next_incr_addr(last_wrap_addr, last_burst_size);
        FIXED: return get_next_fixed_addr(last_wrap_addr);
        default: return '0;
      endcase
    endfunction

    // we always shift the data right to save on logic
    static function automatic logic [AXI_DATA_WIDTH-1:0] shift_data(
        logic [AXI_DATA_WIDTH-1:0] data, bit [$clog2(AXI_ADDR_WIDTH/8)-1:0] amount);
      // we are shifting bytes here
      return NorthcapeMMUBarrelShifter#(AXI_DATA_WIDTH, AXI_ADDR_WIDTH / 8)::barrel_shift(
          data, amount << 3, 1'b0
      );
    endfunction

    static function automatic logic [AXI_DATA_WIDTH/8-1:0] shift_strobes(
        logic [AXI_DATA_WIDTH/8-1:0] data, bit [$clog2(AXI_ADDR_WIDTH/8)-1:0] amount);
      return NorthcapeMMUBarrelShifter
          #(AXI_DATA_WIDTH / 8, $clog2(AXI_ADDR_WIDTH / 8))::barrel_shift(data, amount, 1'b0);
    endfunction

    // this generates a mask to be applied at the AXI master side of the MMU,
    // canceling out information leaks or data modification outside of capability bounds
    static function automatic bit [AXI_DATA_WIDTH/8-1:0] get_per_byte_mask_for_addr(
        axi_bus_addr_t current_addr, northcape_physical_address_t segment_start,
        northcape_physical_address_t segment_end);
      bit [AXI_DATA_WIDTH/8-1:0] ret;
      northcape_physical_address_t modified_segment_end;
      axi_bus_addr_t actual_burst_start;

      // bursts always start size-aligned
      actual_burst_start = current_addr & ~(AXI_DATA_WIDTH / 8 - 1);

      // first address AFTER segment
      modified_segment_end = segment_end - 1;

      ret = '1;


`ifdef DEBUG
      $display(
          "(1) Mask for current address %x actual start %x segment start %x segment end %d  is %x",
          current_addr, actual_burst_start, segment_start, modified_segment_end, ret);
`endif

      for (int i = AXI_DATA_WIDTH / 8 - 1; i >= 0; i--) begin
        if (actual_burst_start + i < segment_start) begin
          // address is lower than capability bound
          ret[i] = 0;
        end
      end
`ifdef DEBUG
      if (ret != '1) begin
        $display(
            "(2) Mask for current address %x actual start %x segment start %x segment end %d  is %x",
            current_addr, actual_burst_start, segment_start, modified_segment_end, ret);
      end
`endif

      for (int i = AXI_DATA_WIDTH / 8 - 1; i >= 0; i--) begin
        if (actual_burst_start + i > modified_segment_end) begin
          // address is lower than capability bound
          ret[i] = 0;
        end
      end

`ifdef DEBUG
      if (ret != '1) begin
        $display(
            "(3) Mask for current address %x actual start %x segment start %x segment end %d  is %x",
            current_addr, actual_burst_start, segment_start, modified_segment_end, ret);
      end
`endif

`ifdef DEBUG
      if (ret != '1) begin
        $display(
            "(4) Mask for current address %x actual start %x segment start %x segment end %d  is %x",
            current_addr, actual_burst_start, segment_start, modified_segment_end, ret);
      end
`endif

      return ret;
    endfunction

    static function automatic logic checkBounds(
        input int unsigned bytes_in_burst, input capability_off_t current_capability_offset,
        input segment_length_t segment_length, input axi_burst_t last_burst_type,
        input northcape_physical_address_t request_start_addr,
        input bit [AXI_ADDR_WIDTH-1:0] cmt_start_addr, input int unsigned cmt_size_clog2,
        input axi_len_t burst_len, input logic [7:0] decoded_burst_size, input bit shift_required,
        input bit self_preservation_mode_active = 1, input bit shifting_active = 1);

`ifdef DEBUG
      $display(
          "Checking bounds for bytes in burst %d offset %d segment length %d segment size correction %d last_burst_type %s accept wrap bursts %d start addr %x cmt start %x clog2 cmt length %d burst len %d decoded burst size %d shift required %b",
          bytes_in_burst, current_capability_offset, segment_length, 2 * (AXI_ADDR_WIDTH / 8),
          last_burst_type.name(), ACCEPT_AXI_WRAP_BURSTS, request_start_addr, cmt_start_addr,
          cmt_size_clog2, burst_len, decoded_burst_size, shift_required);
`endif

      if (self_preservation_mode_active && resolved_address_overlaps_cmt(
              cmt_start_addr, cmt_size_clog2, request_start_addr, bytes_in_burst
          )) begin
`ifdef DEBUG
        $display("Self preservation! CMT start %d CMT size %d request start %d request len %d",
                 cmt_start_addr, 1 << cmt_size_clog2, request_start_addr, bytes_in_burst);
`endif
        // self preservation mode - refuse modification of CMT
        return 0;
      end

      if (shifting_active == 1'b1) begin
        bit [AXI_ADDR_WIDTH - 1 : 0]
            byte_lane_start = request_start_addr & ~(AXI_ADDR_WIDTH / 8 - 1),
            byte_lane_end = byte_lane_start + AXI_ADDR_WIDTH / 8;
`ifdef DEBUG
        $display("Byte lane start %x byte lane end %x", byte_lane_start, byte_lane_end);
`endif
        // this would require me to buffer data for the second transfer
        if (shift_required && burst_len != 0) begin
`ifdef DEBUG
          $display("Multi-beat shifting transfer!");
`endif
          return 0;
        end
        // offset is always positive, so we cannot underflow
        if (request_start_addr + decoded_burst_size > byte_lane_end) begin
`ifdef DEBUG
          $display("Overflow right");
`endif
          return 0;
        end
      end else begin
        // no shifting - can accept only requests with no difference in alignment
        if (shift_required == 1'b1) begin
`ifdef DEBUG
          $display(
              "Relative alignment of capability token and resolved physical address is NOT the same and shifting is not active - cannot accept request!");
`endif
          return 0;
        end
      end

      if (bytes_in_burst == '1) begin
`ifdef DEBUG
        $display("Special bytes-in-burst abort encountered");
`endif
        return 0;
      end

      if (current_capability_offset >= segment_length) begin
`ifdef DEBUG
        $display("Capability offset larger than segment length");
`endif
        return 0;
      end

      // all-zeros segment length = error
      // all-ones segment length = entire address space
      // we add up to two AXI_ADDR_WIDTH bytes to the segment length to account for masking off bits in the first and last beat of the transfer
      // however, the offset cannot just straight out leave the segment - we catch this immediately to make debugging in the SoC easier
      if((((bytes_in_burst + current_capability_offset <= segment_length + 2*(AXI_ADDR_WIDTH/8) || (last_burst_type == WRAP && ACCEPT_AXI_WRAP_BURSTS)) && segment_length != '0) || segment_length == '1))
      begin
        return 1;
      end else begin
`ifdef DEBUG
        $display("Request goes OOB!");
`endif
        return 0;
      end
    endfunction

    static function automatic mmu_state_t computeNextState(
        input mmu_state_t current_state, input logic slave_address_channel_valid_ready,
        input logic axis_validate_request_ready, input logic axis_validate_response_valid,
        input logic bounds_check_ok, input axi_len_t last_burst_len,
        input axi_size_t last_burst_size, input axi_burst_t last_burst_type,
        input logic master_addr_chan_ready, input axi_bus_addr_t last_segment_start,
        input axi_bus_addr_t last_segment_end, input logic axi_slave_data_burst_complete,
        input logic axi_slave_data_transfer_complete, input logic axi_slave_data_channel_ready,
        input axi_bus_addr_t master_addr_chan_addr, input logic input_data_chan_valid,
        input logic input_data_chan_last, input axi_bus_addr_t last_wrap_addr,
        input logic expect_atomic_transaction, input logic atomic_transaction_complete,
        input logic error_beat_complete, input logic atomic_request_error_in,
        input logic axi_slave_bready);
      axi_bus_addr_t next_wrap_addr;

      unique case (current_state)
        IDLE: begin
          if (expect_atomic_transaction) begin
            // if we accept a "normal" read transaction now, we might later confuse the responses...
            return FORWARD_ATOMIC_TRANSACTION;
          end else if (slave_address_channel_valid_ready == 1'b1) begin
            // if resolver can accept this immediately, can skip REQUEST_VALIDATION; otherwise, hold request until accepted.
            return axis_validate_request_ready == 1'b1 ? WAIT_VALIDATION : REQUEST_VALIDATION;
          end
        end
        REQUEST_VALIDATION, WAIT_VALIDATION: begin
          if (axis_validate_response_valid == 1'b1) begin
            // the burst might technically be larger than the segment, as bursts need to be padded to bus data width
            // in this case, need to wait until last burst to adjust strobe or data accordingly
            // segment_size_connection can only hold 3 bits, thereby, never adds 8 bytes erroneously when no correction needed
            // need to also account the offset in the capability length, otherwise, can overrun the segment
            // for WRAP burst, we omit the length check and zero out extra bytes later
            // for all-zeros length, the address was invalid, so we go to consume for all types of burst
            if (bounds_check_ok) begin
              // we can complete the entire transfer in one cycle if it is a 0-length transfer
              if (axi_slave_data_transfer_complete) begin
                // end of transmission before last allowed address
                // might have to wait for awready/arready before transaction is completed, though
                return master_addr_chan_ready ? IDLE : WAIT_ADDRESS_HANDSHAKE;
              end
              if (master_addr_chan_ready == 1'b1) begin
                // can skip FORWARD_ADDR and expect/forward data
                if (ACCEPT_AXI_WRAP_BURSTS && last_burst_type == WRAP) begin
                  next_wrap_addr = master_addr_chan_addr;
                  return get_next_state_in_wrap(
                      next_wrap_addr, '1, last_segment_start, last_segment_end
                  );
                end else begin
                  // if first transfer occured, can skip forward for first transaction
                  return input_data_chan_valid && axi_slave_data_channel_ready ? FORWARD_DATA : FORWARD_DATA_FIRST_TRANSACTION;
                end
              end else begin
                return FORWARD_ADDR;
              end
            end else begin
`ifdef DEBUG
              $display("Bounds check fail!");
`endif
              if (last_burst_len == 0) begin
                return SINGLE_REPORT_ERROR;
              end else begin
                return REPORT_ERROR;
              end
            end
          end else if (axis_validate_request_ready == 1'b1) begin
            // clear tvalid on request and wait for tvalid on response
            return WAIT_VALIDATION;
          end
        end
        FORWARD_ADDR: begin
          // we can complete the entire transfer in one cycle if it is a 0-length transfer
          if (axi_slave_data_transfer_complete) begin
            // end of transmission before last allowed address
            // might have to wait for awready/arready before transaction is completed, though
            return master_addr_chan_ready ? IDLE : WAIT_ADDRESS_HANDSHAKE;
          end
          if (master_addr_chan_ready == 1'b1) begin
            // we can only go into a new state when a transaction is completed
            if (ACCEPT_AXI_WRAP_BURSTS && last_burst_type == WRAP) begin
              next_wrap_addr = master_addr_chan_addr;
              return get_next_state_in_wrap(
                  next_wrap_addr, '1, last_segment_start, last_segment_end
              );
            end else begin
              // if first transfer occured, can skip forward for first transaction
              return input_data_chan_valid && axi_slave_data_channel_ready ? FORWARD_DATA : FORWARD_DATA_FIRST_TRANSACTION;
            end
          end
        end
        WAIT_ADDRESS_HANDSHAKE: begin
          return master_addr_chan_ready ? IDLE : WAIT_ADDRESS_HANDSHAKE;
        end
        // FORWARD_DATA_FIRST_TRANSACTION is irrelevant to the state machine itself, but needed for clearing read bytes
        FORWARD_DATA_FIRST_TRANSACTION, FORWARD_DATA: begin
          if(ACCEPT_AXI_WRAP_BURSTS && last_burst_type == WRAP && input_data_chan_valid && axi_slave_data_channel_ready)
            begin
            if (axi_slave_data_transfer_complete) begin
              // end of transmission before last allowed address
              return IDLE;
            end else begin
              // handshake completed in Wrap burst - update address
              next_wrap_addr = get_next_wrap_addr(last_wrap_addr, last_burst_len, last_burst_size);
              return get_next_state_in_wrap(
                  next_wrap_addr, master_addr_chan_addr, last_segment_start, last_segment_end
              );
            end
          end else begin
            if (input_data_chan_valid && input_data_chan_last) begin
              if (axi_slave_data_transfer_complete) begin
                return IDLE;
              end else begin
                return FORWARD_DATA_LAST_TRANSACTION;
              end
            end else if (!input_data_chan_valid || !axi_slave_data_channel_ready) begin
              // first transaction has not completed
              return current_state;
            end else begin
              return FORWARD_DATA;
            end
          end
        end
        FORWARD_DATA_LAST_TRANSACTION: begin
          if(ACCEPT_AXI_WRAP_BURSTS && last_burst_type == WRAP && axi_slave_data_burst_complete)
            begin
            mmu_state_t computed_state;
            // stay in the state as long as the transaction is not accepted
            next_wrap_addr = get_next_wrap_addr(last_wrap_addr, last_burst_len, last_burst_size);
            computed_state = get_next_state_in_wrap(next_wrap_addr, master_addr_chan_addr,
                                                    last_segment_start, last_segment_end);

            if (computed_state == WAIT_COMPLETE) begin
              if (axi_slave_data_transfer_complete) begin
                // last transaction was confirmed immediately - no need to wait for completion
                return IDLE;
              end else begin
                return current_state;
              end
            end
            return computed_state;
          end else if (!ACCEPT_AXI_WRAP_BURSTS || last_burst_type != WRAP) begin
            if (axi_slave_data_transfer_complete) begin
              // transfer complete
              return IDLE;
            end
          end
        end
        FORWARD_DATA_ZERO_OUT: begin
          if (ACCEPT_AXI_WRAP_BURSTS && last_burst_type == WRAP) begin
            mmu_state_t computed_state;
            next_wrap_addr = get_next_wrap_addr(last_wrap_addr, last_burst_len, last_burst_size);
            computed_state = get_next_state_in_wrap(next_wrap_addr, master_addr_chan_addr,
                                                    last_segment_start, last_segment_end);

            if (computed_state == WAIT_COMPLETE) begin
              if (axi_slave_data_transfer_complete) begin
                // last transaction was confirmed immediately - no need to wait for completion
                return IDLE;
              end else begin
                return current_state;
              end
            end
            return computed_state;
          end else begin
            // we should not be in this state to begin with...
            return WAIT_COMPLETE;
          end
        end
        REPORT_ERROR: begin
          if (axi_slave_data_burst_complete) begin
            if (last_burst_len == 1) begin
              // decrementing to 1 - next transfer is the last one
              return LAST_REPORT_ERROR;
            end
          end
        end
        LAST_REPORT_ERROR, SINGLE_REPORT_ERROR: begin
          if (error_beat_complete) begin
            // write chan can only give write response now
            return IS_WRITE_CHAN ? REPORT_ERROR_BCHAN : IDLE;
          end
        end
        WAIT_COMPLETE: begin
          if (axi_slave_data_transfer_complete) begin
            return IDLE;
          end
        end
        FORWARD_ATOMIC_TRANSACTION: begin
          if (atomic_transaction_complete) begin
            return IDLE;
          end
          if (atomic_request_error_in) begin
            if (last_burst_len == 0) begin
              return SINGLE_REPORT_ERROR;
            end else begin
              return REPORT_ERROR;
            end
          end
        end
        REPORT_ERROR_BCHAN: begin
          if (axi_slave_bready) begin
            // valid is up, ready is low --> we are done, go back to idle
            return IDLE;
          end
        end
        default: begin
          return current_state;
        end
      endcase
      // case might have matched, but conditions for leaving state not met
      return current_state;
    endfunction

  endclass

endpackage
