/**
  * Data structures for the request generator and checker.
  */

package northcape_test;

  import axi5::*;
  import northcape_types::*;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {
    AXI_TEST_READ  = 0,
    AXI_TEST_WRITE = 1
  } axi_test_request_type_t;

  typedef enum logic [1:0] {
    AXI_TEST_OK,
    AXI_TEST_ERR,
    AXI_TEST_TIMEOUT
  } axi_test_request_result_t;

  typedef enum {
    AR_VALID,
    AR_READY,
    AW_VALID,
    AW_READY,
    R_VALID,
    R_READY,
    W_VALID,
    W_READY,
    B_VALID,
    B_READY,
    AXIS_VALID,
    AXIS_READY
  } axi_test_delay_type;

  localparam AXI_MAX_TRANSFER_CYCLES = 1024;


  localparam string NORTHCAPE_CAPABILITY_COUNT_CONFIG_NAME = "northcape_capability_count";


  /**
  * Holds all provided data for commencing an AXI transaction.
  */
    interface class INorthcapeAXITransactionSlaveSide #(
        parameter AXI_DATA_WIDTH = -1,
        parameter AXI_ADDR_WIDTH = -1,
        parameter AXI_ID_WIDTH = -1,
        parameter AXI_USER_WIDTH = -1
    ); pure virtual
    function axi_test_request_type_t get_axi_request_type()
    ; pure virtual
    function bit [AXI_ADDR_WIDTH- 1 : 0] get_slave_axi_addr()
    ; pure virtual
    function axi_len_t get_test_len()
    ; pure virtual
    function axi_burst_t get_burst_type()
    ; pure virtual
    function axi_size_t get_test_size()
    ; pure virtual
    function bit get_test_lock()
    ; pure virtual
    function axi_cache_t get_test_cache()
    ; pure virtual
    function axi_prot_t get_test_prot()
    ; pure virtual
    function axi_qos_t get_test_qos()
    ; pure virtual
    function axi_region_t get_test_region()
    ; pure virtual
    function bit [AXI_ID_WIDTH-1:0] get_test_id()
    ; pure virtual
    function bit [AXI_USER_WIDTH-1:0] get_test_user()
    ;

    // (write only) test_len many words to be written
    pure virtual
    function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_write_data()
    ; pure virtual
    function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] get_slave_write_strobes()
    ;

    // (write only) type of atomic transfer
    pure virtual
    function axi5_atop_t get_atomic_type()
    ;

    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    pure virtual
    function bit get_regression_ready_before_valid()
    ;
    // keep arvalid/awvalid after a ready, accepting a second transaction
    pure virtual
    function bit get_regression_keep_valid_high()
    ; pure virtual
    function bit generate_random_delay(axi_test_delay_type delay_type)
    ;

    endclass

  /**
  * Holds all provided data for commencing an AXI transaction.
  */
    interface class INorthcapeAXITransactionMasterSide #(
        parameter AXI_DATA_WIDTH = -1,
        parameter AXI_ADDR_WIDTH = -1,
        parameter AXI_ID_WIDTH = -1,
        parameter AXI_USER_WIDTH = -1
    ); pure virtual
    function axi_test_request_type_t get_axi_request_type()
    ; pure virtual
    function bit [AXI_ID_WIDTH-1:0] get_test_id()
    ; pure virtual
    function bit [AXI_USER_WIDTH-1:0] get_test_user()
    ;

    // (read only) provided response
    pure virtual
    function bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] get_response_data()
    ;

    // (read only) response
    pure virtual
    function axi_resp_t get_given_response()
    ;

    // used by driver to know how many beats of data to send
    pure virtual
    function axi_atop_t get_atomic_type()
    ; pure virtual
    function axi_len_t get_test_len()
    ;


    // regressions: specific scenarios that failed in hardware and are unlikely to appear in random testing
    // force ready high before valid
    pure virtual
    function bit get_regression_ready_before_valid()
    ;
    // keep arvalid/awvalid after a ready, accepting a second transaction
    pure virtual
    function bit get_regression_keep_valid_high()
    ; pure virtual
    function bit generate_random_delay(axi_test_delay_type delay_type)
    ; pure virtual
    function string to_string()
    ;
    endclass

  /**
  * Holds all provided data for checking and answering a capability resolver transaction.
  */
    interface class INorthcapeCapabilityResolverTransaction; pure virtual
    function axis_validate_response_tdata_t get_resolver_response()
    ;

    endclass

  class Axi5DelayGenerator;
    // auto-initialized to 0
    bit [$clog2(AXI_MAX_TRANSFER_CYCLES)-1:0]
        ar_valid_counter,
        ar_ready_counter,
        aw_valid_counter,
        aw_ready_counter,
        r_valid_counter,
        r_ready_counter,
        w_valid_counter,
        w_ready_counter,
        b_valid_counter,
        b_ready_counter,
        axis_valid_counter,
        axis_ready_counter;

    bit ar_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit ar_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    bit aw_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit aw_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    bit r_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit r_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    bit w_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit w_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    bit b_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit b_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    bit axis_channel_valids[AXI_MAX_TRANSFER_CYCLES];
    bit axis_channel_readys[AXI_MAX_TRANSFER_CYCLES];

    localparam COMPONENT_NAME = "Axi Delay Generator";

    function new();
      for (int i = 0; i < AXI_MAX_TRANSFER_CYCLES; i++) begin
        int unsigned rnd = $urandom();
        ar_channel_valids[i] = rnd[0];
        ar_channel_readys[i] = rnd[1];

        aw_channel_valids[i] = rnd[2];
        aw_channel_readys[i] = rnd[3];

        r_channel_valids[i] = rnd[4];
        r_channel_readys[i] = rnd[5];

        w_channel_valids[i] = rnd[6];
        w_channel_readys[i] = rnd[7];

        b_channel_valids[i] = rnd[8];
        b_channel_readys[i] = rnd[9];

        axis_channel_valids[i] = rnd[10];
        axis_channel_readys[i] = rnd[11];
      end
    endfunction

    virtual function bit generate_random_delay(axi_test_delay_type delay_type);
      bit ret;
      unique case (delay_type)
        AR_VALID: begin
          ret = ar_channel_valids[ar_valid_counter];
          ar_valid_counter += 1;
        end
        AR_READY: begin
          ret = ar_channel_readys[ar_ready_counter];
          ar_ready_counter += 1;
        end
        AW_VALID: begin
          ret = aw_channel_valids[aw_valid_counter];
          aw_valid_counter += 1;
        end
        AW_READY: begin
          ret = aw_channel_readys[aw_ready_counter];
          aw_ready_counter += 1;
        end
        R_VALID: begin
          ret = r_channel_valids[r_valid_counter];
          r_valid_counter += 1;
        end
        R_READY: begin
          ret = r_channel_readys[r_ready_counter];
          r_ready_counter += 1;
        end
        W_VALID: begin
          ret = w_channel_valids[w_valid_counter];
          w_valid_counter += 1;
        end
        W_READY: begin
          ret = w_channel_readys[w_ready_counter];
          w_ready_counter += 1;
        end
        B_VALID: begin
          ret = b_channel_valids[b_valid_counter];
          b_valid_counter += 1;
        end
        B_READY: begin
          ret = b_channel_readys[b_ready_counter];
          b_ready_counter += 1;
        end
        AXIS_VALID: begin
          ret = axis_channel_valids[axis_valid_counter];
          axis_valid_counter += 1;
        end
        AXIS_READY: begin
          ret = axis_channel_readys[axis_ready_counter];
          axis_ready_counter += 1;
        end
        default: begin
          `uvm_error(COMPONENT_NAME, $sformatf("Unexpected enum type %s", delay_type.name()));
        end
      endcase

      return ret;
    endfunction
  endclass

    interface class IRNGSeedTransaction #(
        parameter RNG_DATA_WIDTH = -1
    ); pure virtual
    function int get_rng_seed()
    ; pure virtual
    function int get_number_expected_rng_invocations()
    ;

    endclass

  typedef interface class IAxis5ReceiverChecker;

    interface class IAxis5TransmitterTransaction #(
        parameter AXIS_TDATA_WIDTH = -1,
        parameter AXIS_TID_WIDTH = -1,
        parameter AXIS_TDEST_WIDTH = -1,
        parameter AXIS_TUSER_WIDTH = -1
    );
    localparam AXIS_TSTROBE_WIDTH = AXIS_TDATA_WIDTH / 8;
    localparam AXIS_TKEEP_WIDTH = AXIS_TSTROBE_WIDTH;

    pure virtual
    function bit [AXIS_TDATA_WIDTH-1:0] get_transmitter_tdata()
    ; pure virtual
    function bit [AXIS_TSTROBE_WIDTH-1:0] get_transmitter_tstrb()
    ; pure virtual
    function bit [AXIS_TKEEP_WIDTH-1:0] get_transmitter_tkeep()
    ; pure virtual
    function bit [AXIS_TID_WIDTH-1:0] get_transmitter_tid()
    ; pure virtual
    function bit [AXIS_TDEST_WIDTH-1:0] get_transmitter_tdest()
    ; pure virtual
    function bit [AXIS_TUSER_WIDTH-1:0] get_transmitter_tuser()
    ;
    endclass

    interface class IAxis5ReceiverScoreboard #(
        parameter AXIS_TDATA_WIDTH = -1,
        parameter AXIS_TID_WIDTH = -1,
        parameter AXIS_TDEST_WIDTH = -1,
        parameter AXIS_TUSER_WIDTH = -1
    );
    localparam AXIS_TSTROBE_WIDTH = AXIS_TDATA_WIDTH / 8;
    localparam AXIS_TKEEP_WIDTH = AXIS_TSTROBE_WIDTH;

    typedef IAxis5ReceiverChecker#(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) checker_t;

    pure virtual
    function bit [AXIS_TDATA_WIDTH-1:0] get_receiver_tdata()
    ; pure virtual
    function bit [AXIS_TSTROBE_WIDTH-1:0] get_receiver_tstrb()
    ; pure virtual
    function bit [AXIS_TKEEP_WIDTH-1:0] get_receiver_tkeep()
    ; pure virtual
    function bit [AXIS_TID_WIDTH-1:0] get_receiver_tid()
    ; pure virtual
    function bit [AXIS_TDEST_WIDTH-1:0] get_receiver_tdest()
    ; pure virtual
    function bit [AXIS_TUSER_WIDTH-1:0] get_receiver_tuser()
    ; pure virtual
    function checker_t get_receiver_checker()
    ;
    endclass

    interface class IAxis5ReceiverChecker #(
        parameter AXIS_TDATA_WIDTH = -1,
        parameter AXIS_TID_WIDTH = -1,
        parameter AXIS_TDEST_WIDTH = -1,
        parameter AXIS_TUSER_WIDTH = -1
    );
    typedef virtual Axis5Test #(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ).TEST_RECEIVER intf_t;
    pure virtual
    function axi_test_request_result_t check_interface(intf_t intf)
    ;
    endclass

  /**
  * Result to be returned from Axi5 Slave driver.
  * This is here to prevent circular dependency with MMU scoreboard.
  */
  class Axi5SlaveDriverResultTransaction #(
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1
  ) extends uvm_sequence_item;

    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] read_data;
    axi_resp_t resp;
    axi_len_t data_len;

    bit [AXI_ID_WIDTH-1:0] id;

    bit [AXI_USER_WIDTH-1:0] user;

    function new(string name = "");
      super.new(name);

      // initialization that will trip the scoreboard
      data_len = '0;
      resp = DECERR;
      read_data = '0;
      id = '0;
      user = '0;
    endfunction

    typedef Axi5SlaveDriverResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) my_type_t;

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      read_data = other_transaction.read_data;
      resp = other_transaction.resp;
      data_len = other_transaction.data_len;
      id = other_transaction.id;
      user = other_transaction.user;
    endfunction

    function string convert2string();
      string s;
      string read_data_str;

      read_data_str = "[";

      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        read_data_str = $sformatf(i ? "%s,\n%x" : "%s\n%x", read_data_str, read_data[i]);
      end
      read_data_str = {read_data_str, "\n]"};

      s = $sformatf(
          "Read data: %s, resp = %s, data len = %d, id = %x, user=%x",
          read_data_str,
          resp.name(),
          data_len,
          id,
          user
      );
      return s;
    endfunction

    localparam COMPONENT_NAME = "Slave Driver Result Transaction";

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (read_data !== other_transaction.read_data) begin
        `uvm_error(COMPONENT_NAME, "request read data do not match!");
        return 0;
      end

      if (resp !== other_transaction.resp) begin
        `uvm_error(COMPONENT_NAME, "request response does not match!");
        return 0;
      end

      if (data_len !== other_transaction.data_len) begin
        `uvm_error(COMPONENT_NAME, "request data len does not match!");
        return 0;
      end

      if (id !== other_transaction.id) begin
        `uvm_error(COMPONENT_NAME, "request id does not match!");
        return 0;
      end

      if (user !== other_transaction.user) begin
        `uvm_error(COMPONENT_NAME, "request user does not match!");
        return 0;
      end

      return 1;
    endfunction

  endclass

  /**
  * Result to be returned from Axi5 Master driver.
  * This is here to prevent circular dependency with MMU scoreboard.
  */
  class Axi5MasterDriverResultTransaction #(
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = 1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1
  ) extends uvm_sequence_item;

    axi_test_request_type_t request_type;

    // common attributes for read and write
    bit [AXI_ADDR_WIDTH-1:0] addr;
    axi_len_t len;
    axi_burst_t burst;
    axi_size_t size;
    bit lock;
    axi_cache_t cache;
    axi_prot_t prot;
    axi_qos_t qos;
    axi_region_t region;
    bit [AXI_ID_WIDTH-1:0] id;
    bit [AXI_USER_WIDTH-1:0] user;

    // (write only) write atomic transaction type
    axi5_atop_t atop;

    // (write only) data and strobes
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH-1:0] write_data;
    bit [AXI5_MAX_BURST_LEN-1:0][AXI_DATA_WIDTH/8-1:0] write_strobes;
    // (write only) write ID + user
    bit [AXI_ID_WIDTH-1:0] wid;
    bit [AXI_USER_WIDTH-1:0] wuser;

    typedef Axi5MasterDriverResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) my_type_t;


    localparam COMPONENT_NAME = "Master Driver Result Transaction";

    function new(string name = "");
      super.new(name);
    endfunction

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      addr = other_transaction.addr;
      len = other_transaction.len;
      burst = other_transaction.burst;
      size = other_transaction.size;
      lock = other_transaction.lock;
      cache = other_transaction.cache;
      prot = other_transaction.prot;
      qos = other_transaction.qos;
      region = other_transaction.region;
      id = other_transaction.id;
      user = other_transaction.user;

      atop = other_transaction.atop;

      write_data = other_transaction.write_data;
      write_strobes = other_transaction.write_strobes;
      wid = other_transaction.wid;
      wuser = other_transaction.wuser;
    endfunction

    function string convert2string();
      string s;
      string write_data_str, write_strobes_str;

      write_data_str = "[";
      write_strobes_str = "[";

      for (int i = 0; i < AXI5_MAX_BURST_LEN; i++) begin
        write_data_str = $sformatf(i ? "%s,\n%x" : "%s\n%x", write_data_str, write_data[i]);
        write_strobes_str =
            $sformatf(i ? "%s,\n%x" : "%s\n%x", write_strobes_str, write_strobes[i]);
      end
      write_data_str = {write_data_str, "\n]"};
      write_strobes_str = {write_strobes_str, "\n]"};


      s = $sformatf(
          "request type: %s, addr: %x, len: %d, burst: %s, size: %d, lock: %b, cache: %b, prot: %x, qos: %x, region: %x, id: %x, user: %x, atop type: %s, atop_subtype: %x, write_data: %s, write_strobes: %s, wid: %x, wuser: %x",
          request_type.name(),
          addr,
          len,
          burst.name(),
          size,
          lock,
          cache,
          prot,
          qos,
          region,
          id,
          user,
          atop.atop_type,
          atop.atop_subtype,
          write_data_str,
          write_strobes_str,
          wid,
          wuser
      );
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (request_type != other_transaction.request_type) begin
        `uvm_error(COMPONENT_NAME, "request type does not match!");
        return 0;
      end

      if (addr !== other_transaction.addr) begin
        `uvm_error(COMPONENT_NAME, $sformatf(
                   "request addr does not match - own %x other %x", addr, other_transaction.addr));
        return 0;
      end

      if (len !== other_transaction.len) begin
        `uvm_error(COMPONENT_NAME, "request len does not match!");
        return 0;
      end

      if (burst !== other_transaction.burst) begin
        `uvm_error(COMPONENT_NAME, "request burst does not match!");
        return 0;
      end

      if (size !== other_transaction.size) begin
        `uvm_error(COMPONENT_NAME, "request size does not match!");
        return 0;
      end

      if (lock !== other_transaction.lock) begin
        `uvm_error(COMPONENT_NAME, "request lock does not match!");
        return 0;
      end

      if (cache !== other_transaction.cache) begin
        `uvm_error(COMPONENT_NAME, "request cache does not match!");
        return 0;
      end

      if (prot !== other_transaction.prot) begin
        `uvm_error(COMPONENT_NAME, "request prot does not match!");
        return 0;
      end

      if (qos !== other_transaction.qos) begin
        `uvm_error(COMPONENT_NAME, "request qos does not match!");
        return 0;
      end

      if (region !== other_transaction.region) begin
        `uvm_error(COMPONENT_NAME, "request region does not match!");
        return 0;
      end

      if (id !== other_transaction.id) begin
        `uvm_error(COMPONENT_NAME, "request id does not match!");
        return 0;
      end

      if (user !== other_transaction.user) begin
        `uvm_error(COMPONENT_NAME, "request user does not match!");
        return 0;
      end

      if (write_data !== other_transaction.write_data) begin
        `uvm_error(COMPONENT_NAME, "request write data do not match!");
        return 0;
      end

      if (write_strobes !== other_transaction.write_strobes) begin
        `uvm_error(COMPONENT_NAME, "request write strobes do not match!");
        return 0;
      end

      if (wid !== other_transaction.wid) begin
        `uvm_error(COMPONENT_NAME, "request write id does not match!");
        return 0;
      end

      if (wuser !== other_transaction.wuser) begin
        `uvm_error(COMPONENT_NAME, "request write user does not match!");
        return 0;
      end

      return 1;
    endfunction

  endclass

  /**
  * Result to be returned from Axi5 Resolver driver.
  * This is here to prevent circular dependency with MMU scoreboard.
  */
  class AxisValidateResultTransaction extends uvm_sequence_item;
    axis_validate_request_tdata_t request_data;

    function new(string name = "");
      super.new(name);
    endfunction


    localparam COMPONENT_NAME = "Axis Driver Result Transaction";

    function void do_copy(uvm_object rhs);
      AxisValidateResultTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end
      request_data = other_transaction.request_data;
    endfunction

    function string convert2string();
      string s;
      s = $sformatf(
          "Device ID %x task id %x Address %x Tag %x Access Type %s flags %x original address %x original segment length %x original permissions %x lock key %x restriction %x restriction type %s original_permission_tid_match %b",
          request_data.device_id,
          request_data.task_id,
          request_data.address,
          request_data.tag,
          request_data.access_type.name(),
          request_data.flags,
          request_data.original_address,
          request_data.original_segment_length,
          request_data.original_permissions,
          request_data.lock_key,
          request_data.restriction,
          request_data.restriction_type.name(),
          request_data.original_permission_tid_match
      );
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      AxisValidateResultTransaction other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (request_data.device_id != other_transaction.request_data.device_id) begin
        `uvm_error(COMPONENT_NAME, "Request device id does not match!");
        return 0;
      end

      if (request_data.task_id != other_transaction.request_data.task_id) begin
        `uvm_error(COMPONENT_NAME, "Request task id does not match!");
        return 0;
      end

      if (request_data.address !== other_transaction.request_data.address) begin
        `uvm_error(COMPONENT_NAME, "Request address does not match!");
        return 0;
      end

      if (request_data.tag !== other_transaction.request_data.tag) begin
        `uvm_error(COMPONENT_NAME, "Request tag does not match!");
        return 0;
      end

      if (request_data.access_type !== other_transaction.request_data.access_type) begin
        `uvm_error(COMPONENT_NAME, "Request access type does not match!");
        return 0;
      end

      if (request_data.flags != other_transaction.request_data.flags) begin
        `uvm_error(COMPONENT_NAME, "Request flags do not match!");
        return 0;
      end

      if (request_data.original_address != other_transaction.request_data.original_address) begin
        `uvm_error(COMPONENT_NAME, "Request original address does not match!");
        return 0;
      end

      if (request_data.original_segment_length != other_transaction.request_data.original_segment_length) begin
        `uvm_error(COMPONENT_NAME, "Request original segment length does not match!");
        return 0;
      end

      if(request_data.original_permission_tid_match != other_transaction.request_data.original_permission_tid_match) begin
        `uvm_error(COMPONENT_NAME, "Request original TID match does not match!");
        return 0;
      end

      if (request_data.original_permissions != other_transaction.request_data.original_permissions) begin
        `uvm_error(COMPONENT_NAME, "Request original permissions do not match!");
        return 0;
      end

      if (request_data.lock_key != other_transaction.request_data.lock_key) begin
        `uvm_error(COMPONENT_NAME, "Request lock key does not match!");
        return 0;
      end

      if (request_data.restriction != other_transaction.request_data.restriction) begin
        `uvm_error(COMPONENT_NAME, "Request restriction does not match!");
        return 0;
      end

      if (request_data.restriction_type != other_transaction.request_data.restriction_type) begin
        `uvm_error(COMPONENT_NAME, "Request restriction type does not match!");
        return 0;
      end

      return 1;
    endfunction

  endclass

  /**
  * Result to be returned from generic AXIS driver.
  */
  class AxisGenericResultTransaction #(
      parameter AXIS_TDATA_WIDTH = -1,
      parameter AXIS_TID_WIDTH   = -1,
      parameter AXIS_TDEST_WIDTH = -1,
      parameter AXIS_TUSER_WIDTH = -1
  ) extends uvm_sequence_item;
    bit [AXIS_TDATA_WIDTH-1:0] tdata;
    bit [AXIS_TID_WIDTH-1:0] tid;
    bit [AXIS_TDEST_WIDTH-1:0] tdest;
    bit [AXIS_TUSER_WIDTH-1:0] tuser;

    bit [AXIS_TDATA_WIDTH/8-1:0] tstrb;
    bit [AXIS_TDATA_WIDTH/8-1:0] tkeep;



    function new(string name = "");
      super.new(name);
    endfunction

    typedef AxisGenericResultTransaction#(
        .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
        .AXIS_TID_WIDTH  (AXIS_TID_WIDTH),
        .AXIS_TDEST_WIDTH(AXIS_TDEST_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH)
    ) my_type_t;


    localparam COMPONENT_NAME = "Axis Driver Result Transaction";

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      tdata = other_transaction.tdata;
      tid   = other_transaction.tid;
      tdest = other_transaction.tdest;
      tuser = other_transaction.tuser;
      tkeep = other_transaction.tkeep;
      tstrb = other_transaction.tstrb;
    endfunction

    function string convert2string();
      string s;
      s = $sformatf(
          "Tdata %x Tid %x Tdest %d Tuser %x tkeep %x tstrb %x",
          tdata,
          tid,
          tdest,
          tuser,
          tkeep,
          tstrb
      );
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (tdata != other_transaction.tdata) begin
        `uvm_error(COMPONENT_NAME, $sformatf(
                   "tdata does not match! %x vs %x", tdata, other_transaction.tdata));
        return 0;
      end

      if (tdest !== other_transaction.tdest) begin
        `uvm_error(COMPONENT_NAME, "tdest does not match!");
        return 0;
      end

      if (tid !== other_transaction.tid) begin
        `uvm_error(COMPONENT_NAME, "tid does not match!");
        return 0;
      end

      if (tuser !== other_transaction.tuser) begin
        `uvm_error(COMPONENT_NAME, "tuser does not match!");
        return 0;
      end

      if (tkeep !== other_transaction.tkeep) begin
        `uvm_error(COMPONENT_NAME, "tkeep does not match!");
        return 0;
      end

      if (tstrb !== other_transaction.tstrb) begin
        `uvm_error(COMPONENT_NAME, "tstrb does not match!");
        return 0;
      end

      return 1;
    endfunction

  endclass

  class AxiLiteResultTransaction #(
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_DATA_WIDTH = -1
  ) extends uvm_sequence_item;

    typedef AxiLiteResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) my_type_t;

    axi_test_request_type_t request_type;
    axi_resp_t response;

    logic [AXI_DATA_WIDTH-1:0] read_data;

    function new(string name = "");
      super.new(name);
    endfunction


    localparam COMPONENT_NAME = "Axi Lite Driver Result Transaction";

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      request_type = other_transaction.request_type;
      response = other_transaction.response;
      read_data = other_transaction.read_data;

    endfunction

    function string convert2string();
      string s;
      s = $sformatf(
          "Request type %s response %s read data %x",
          request_type.name(),
          response.name(),
          read_data
      );
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      if (request_type !== other_transaction.request_type) begin
        `uvm_error(COMPONENT_NAME, "Request type does not match!");
        return 0;
      end

      if (response !== other_transaction.response) begin
        `uvm_error(COMPONENT_NAME, "Response does not match!");
        return 0;
      end

      if (read_data !== other_transaction.read_data) begin
        `uvm_error(COMPONENT_NAME, $sformatf(
                   "Read data do not match! My %x other %x", read_data, other_transaction.read_data
                   ));
        return 0;
      end

      return 1;
    endfunction
  endclass

  class RegInterfaceResultTransaction #(
      parameter AXI_DATA_WIDTH = -1,
      parameter NUM_REGS = -1
  ) extends uvm_sequence_item;

    typedef RegInterfaceResultTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .NUM_REGS(NUM_REGS)
    ) my_type_t;

    logic [AXI_DATA_WIDTH-1:0] current_data[NUM_REGS];

    function new(string name = "");
      super.new(name);
    endfunction


    localparam COMPONENT_NAME = "Register Interface Result Transaction";

    function void do_copy(uvm_object rhs);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      super.do_copy(rhs);

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      current_data = other_transaction.current_data;

    endfunction

    function string convert2string();
      string s;
      s = $sformatf("Current data %x", current_data);
      return s;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      my_type_t other_transaction;

      if (rhs == null) begin
        `uvm_fatal(COMPONENT_NAME, "RHS is null!");
      end

      if (super.do_compare(rhs, comparer) == 0) begin
        return 0;
      end

      if ($cast(other_transaction, rhs) == 0) begin
        `uvm_fatal(COMPONENT_NAME, "Failed cast!");
      end

      return current_data == other_transaction.current_data;
    endfunction
  endclass

endpackage : northcape_test

interface northcape_test_reset (
    input logic clk_i
);
  logic resetn;

  clocking reset_clocking @(posedge (clk_i));
    input clk_i;
    output resetn;
  endclocking

  modport ENV(clocking reset_clocking);
endinterface
