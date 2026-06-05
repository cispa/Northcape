/**
  * Simulates DRAM for verification.
  */
package northcape_sparse_mem_sim;

    interface class NorthcapeSparseMemUpdateCallback #(
        parameter type DATA_TYPE = logic, parameter type INDEX_TYPE = int
    ); pure virtual
    function void data_updated(INDEX_TYPE addr, DATA_TYPE old_value, DATA_TYPE new_value)
    ;
    endclass

  class automatic NorthcapeSparseMem #(
      // this should be a logic or bit vector
      parameter type DATA_TYPE = logic,
      // this should be a queue of DATA_TYPE
      parameter type QUEUE_TYPE = logic,
      parameter type INDEX_TYPE = int,
      parameter AXI_DATA_WIDTH = -1,
      parameter bit ZERO_IF_NOT_EXISTS = 1'b0
  );
    typedef NorthcapeSparseMemUpdateCallback#(
        .DATA_TYPE (DATA_TYPE),
        .INDEX_TYPE(INDEX_TYPE)
    ) update_callback_t;

    update_callback_t update_callback;

    DATA_TYPE associative_array[INDEX_TYPE];


    function QUEUE_TYPE read_mem(input INDEX_TYPE index, int unsigned data_len);
      DATA_TYPE  ret;
      QUEUE_TYPE ret_queue;
      for (int i = 0; i < data_len; i++) begin
        INDEX_TYPE idx;

        idx = index + i * (AXI_DATA_WIDTH / 8);
        ret = associative_array[idx];

        if (ZERO_IF_NOT_EXISTS == 1'b1) begin
          if (!associative_array.exists(idx)) begin
            ret = '0;
          end
        end
`ifdef DEBUG
        $display("Read mem index %x: %x", idx, ret);
`endif
        ret_queue.push_back(ret);
      end
      return ret_queue;

    endfunction

    function void write_mem(input INDEX_TYPE index, input QUEUE_TYPE entry);
`ifdef DEBUG
      $display("Write mem index %x data:", index);
`endif

      // each entry in the queue corresponds to one word in mem
      for (int i = 0; i < entry.size(); i++) begin
        INDEX_TYPE idx;
        DATA_TYPE  old_value;

        idx = index + i * (AXI_DATA_WIDTH / 8);

        old_value = associative_array[idx];

        if (ZERO_IF_NOT_EXISTS == 1'b1) begin
          if (!associative_array.exists(idx)) begin
            old_value = '0;
          end
        end
`ifdef DEBUG
        $display("Data %x: %x", idx, entry[i]);
`endif
        if (this.update_callback) begin
          this.update_callback.data_updated(idx, old_value, entry[i]);
        end
        associative_array[idx] = entry[i];
      end


    endfunction

    function new(update_callback_t update_callback = null);
      this.update_callback = update_callback;
    endfunction


  endclass

endpackage
