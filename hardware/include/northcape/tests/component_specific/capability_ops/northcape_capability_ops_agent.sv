

/**
  * Agent, i.e., test orchestrator for Capability Ops.
  */
package northcape_capability_ops_agent;
  import axi5::*;
  import northcape_test::*;
  import northcape_types::*;
  import northcape_capability_ops_scoreboard::NorthcapeCapabilityOpsScoreboard;
  import northcape_capability_ops_transaction::*;
  import northcape_sequence::NorthcapeDirectSequence;
  import northcape_generic_checker::*;

  import northcape_reg_interface_transaction::NorthcapeRegInterfaceAxiLiteTransaction;
  import northcape_axi5_lite_driver::*;
  import northcape_capability_ops_sequence::*;
  import northcape_capability_ops_common::*;
  import northcape_capability_ops_csr_interface_driver::*;

  import northcape_rng_driver::NorthcapeRNGDriver;
  import northcape_bram_driver::*;


  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class automatic NorthcapeCapabilityOpsAgentConfig #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1
  );

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_CONSUMER cmt_interface_t;

    typedef virtual Axi5Lite #(
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
    ).TEST axi5_lite_t;

    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) transaction_axi_master_t;


    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef virtual NorthcapeInterruptInterface #(
        .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
    ).TEST_CONSUMER irq_interface_t;

    typedef virtual NorthcapeCurrentDeviceTaskInterface.TEST_PRODUCER device_task_interface_t;

    typedef virtual NorthcapeCapabilityOpsCsrIntf csr_intf_t;

    master_analysis_port_t ops_analysis_port, cache_analysis_port;



    logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base;
    int unsigned initial_cmt_size_clog2;

    axi5_lite_t mmio;

    csr_intf_t csr_intf;

    mailbox #(transaction_axi_master_t) requests_in_ops;
    mailbox #(transaction_axi_master_t) requests_in_cache;

    virtual northcape_test_reset reset_intf;

    cmt_interface_t cmt_intf;

    device_task_interface_t device_task_intf;

    irq_interface_t irq_intf;

    function new(cmt_interface_t cmt_intf, logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base,
                 int unsigned initial_cmt_size_clog2, axi5_lite_t mmio, csr_intf_t csr_intf,
                 mailbox#(transaction_axi_master_t) requests_in_ops,
                 master_analysis_port_t ops_analysis_port,
                 mailbox#(transaction_axi_master_t) requests_in_cache,
                 master_analysis_port_t cache_analysis_port,
                 virtual northcape_test_reset reset_intf, device_task_interface_t device_task_intf,
                 irq_interface_t irq_intf);

      this.initial_cmt_base = initial_cmt_base;
      this.initial_cmt_size_clog2 = initial_cmt_size_clog2;

      this.mmio = mmio;
      this.csr_intf = csr_intf;

      this.requests_in_ops = requests_in_ops;

      this.ops_analysis_port = ops_analysis_port;

      this.requests_in_cache = requests_in_cache;

      this.cache_analysis_port = cache_analysis_port;

      this.reset_intf = reset_intf;

      this.cmt_intf = cmt_intf;

      this.device_task_intf = device_task_intf;

      this.irq_intf = irq_intf;
    endfunction

  endclass

  class automatic NorthcapeCapabilityOpsAgent #(
      // parameters for AXI (master) interface
      parameter AXI_DATA_WIDTH = -1,
      parameter AXI_ADDR_WIDTH = -1,
      parameter AXI_ID_WIDTH   = -1,
      parameter AXI_USER_WIDTH = -1,

      // parameters for AXI LITE (slave) interface

      parameter AXI_LITE_DATA_WIDTH = -1,
      parameter AXI_LITE_ADDR_WIDTH = -1,

      parameter HASH_TYPE = -1,

      parameter bit [AXI_ADDR_WIDTH-1:0] INITIAL_CMT_BASE = -1,
      parameter int unsigned INITIAL_CMT_SIZE_CLOG2 = -1,


      parameter string CAPABILITY_OPS_AGENT_CONFIG_NAME = "",
      parameter string TRANSACTIONS_QUEUE_NAME_AGENT = "",

      parameter string AXI_LITE_INTERFACE_NAME = "",

      parameter bit CHECK_AXI_TRANSACTIONS = 1,

      parameter string RNG_INTERFACE_NAME = "",
      parameter bit PROVIDE_RNG_INTERFACE = 0,
      // use CBC MAC of CMT entry or a CTR of the nonce for the tag
      parameter northcape_capability_ops_tag_method_t OPS_TAG_METHOD = NORTHCAPE_CAPABILITY_OPS_CBC,

      parameter BRAM_DATA_WIDTH = -1,
      parameter BRAM_DATA_DEPTH = -1,
      parameter string BRAM_MODULE_INTERFACE_NAME = "NORTHCAPE_BRAM_MODULE_INTERFACE"
  ) extends uvm_agent;

    localparam NUM_REGS = 4;

    typedef virtual NorthcapeCurrentDeviceTaskInterface.TEST_PRODUCER device_task_interface_t;

    typedef Axi5LiteDriver#(
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS),
        .INTERFACE_NAME(AXI_LITE_INTERFACE_NAME)
    ) axi_lite_driver_t;

    typedef NorthcapeCapabilityOpsTransaction#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_t;

    typedef NorthcapeBRAMDriver#(
        .DATA_WIDTH(BRAM_DATA_WIDTH),
        .DATA_DEPTH(BRAM_DATA_DEPTH),
        .MODULE_INTERFACE_NAME(BRAM_MODULE_INTERFACE_NAME)
    ) bram_driver_t;



    typedef NorthcapeCapabilityOpsTransactionRNG#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_rng_t;

    typedef NorthcapeCapabilityOpsTransactionRNGInitial#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_rng_initial_t;


    typedef NorthcapeCapabilityOpsTransactionCMTZero#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_cmt_zero_t;

    typedef NorthcapeCapabilityOpsTransactionCreateCap#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_create_cap_t;

    typedef NorthcapeCapabilityOpsTransactionCMTReadInput#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_read_cmt_entry_t;

    typedef NorthcapeCapabilityOpsTransactionCMTWriteOutput#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_write_cmt_entry_t;

    typedef NorthcapeCapabilityOpsTransactionRevoke#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_revoke_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadHeader#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_header_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadCipherText#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_ciphertext_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadPlainText#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_plaintext_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealWriteInitialHash#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_write_initial_hash_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadPCR#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_pcr_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealWritePlainText#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_write_plaintext_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealWritePCR#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_write_pcr_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadAttestL#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_attestl_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadVerifLHash#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_verifl_hash_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadVerifLTag#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_verifl_tag_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealWriteAttestL#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_write_attestl_t;

    typedef NorthcapeCapabilityOpsTransactionUnsealReadHMAC#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) transaction_unseal_read_hmac_t;

    typedef uvm_analysis_port#(Axi5MasterDriverResultTransaction#(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    )) master_analysis_port_t;

    typedef virtual NorthcapeCMTInterface #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ).TEST_CONSUMER cmt_interface_t;

    typedef virtual Axi5Lite #(
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH)
    ).TEST axi5_lite_t;

    typedef virtual NorthcapeCapabilityOpsCsrIntf csr_intf_t;

    typedef INorthcapeAXITransactionMasterSide#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH)
    ) transaction_axi_master_t;

    typedef NorthcapeRNGDriver#(
        .RNG_DATA_WIDTH(NORTHCAPE_CAPABILITY_OPS_RNG_INTERFACE_BITS),
        .INTERFACE_NAME(RNG_INTERFACE_NAME),
        .SEQUENCE_ITEM_TYPE(transaction_rng_t),
        .IS_ACTIVE(1)
    ) rng_driver_t;

    typedef virtual NorthcapeInterruptInterface #(
        .NUMBER_INTERRUPT_PINS(NORTHCAPE_CAPABILITY_OPS_NUM_IRQS)
    ).TEST_CONSUMER irq_interface_t;

    irq_interface_t irq_intf;

    rng_driver_t rng_driver;



    logic [AXI_ADDR_WIDTH-1:0] initial_cmt_base;
    int unsigned initial_cmt_size_clog2;

    master_analysis_port_t ops_analysis_port;
    master_analysis_port_t cache_analysis_port;

    cmt_interface_t cmt_intf;

    virtual northcape_test_reset reset_intf;

    axi5_lite_t mmio;
    csr_intf_t csr_intf;

    typedef NorthcapeBRAMRequest#(
        .DATA_WIDTH(BRAM_DATA_WIDTH),
        .DATA_DEPTH(BRAM_DATA_DEPTH)
    ) bram_transaction_t;

    typedef uvm_sequencer#(NorthcapeRegInterfaceAxiLiteTransaction#(
        .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
    )) mmio_sequencer_t;
    typedef uvm_sequencer#(NorthcapeCapabilityOpsCSRInterfaceTransaction) csr_sequencer_t;

    typedef uvm_sequencer#(bram_transaction_t) bram_sequencer_t;

    mmio_sequencer_t sequencer_mmio;
    csr_sequencer_t sequencer_csr;
    bram_sequencer_t sequencer_bram;
    axi_lite_driver_t mmio_driver;
    bram_driver_t bram_driver;
    NorthcapeCapabilityOpsCSRInterfaceDriver csr_driver;

    mailbox #(transaction_axi_master_t) requests_in_ops;
    mailbox #(transaction_axi_master_t) requests_in_cache;

    localparam string COMPONENT_NAME = "Northcape Capability Ops Agent";

    localparam string TRANSACTIONS_QUEUE_NAME_SCOREBOARD = "capability_ops_transactions_scoreboard";
    localparam string TRANSACTIONS_QUEUE_NAME_RNG = "capability_ops_transactions_rng";
    localparam string TRANSACTIONS_QUEUE_NAME_BRAM = "capability_ops_transactioins_bram";

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_SCOREBOARD)
    ) scoreboard_sequence_t;

    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(bram_transaction_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_BRAM)
    ) bram_sequence_t;


    typedef NorthcapeDirectSequence#(
        .TRANSACTION_TYPE(transaction_rng_t),
        .TRANSACTION_QUEUE_NAME(TRANSACTIONS_QUEUE_NAME_RNG)
    ) rng_sequence_t;


    // sequence is always 1:1 between sequencer and driver
    scoreboard_sequence_t sequence_scoreboard;
    bram_sequence_t sequence_bram;
    uvm_sequencer #(transaction_t) sequencer_scoreboard;

    rng_sequence_t rng_sequence;
    uvm_sequencer #(transaction_rng_t) sequencer_rng;


    typedef NorthcapeCapabilityOpsScoreboard#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .HASH_TYPE(HASH_TYPE),


        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2),
        .TRANSACTIONS_QUEUE_NAME_SCOREBOARD(TRANSACTIONS_QUEUE_NAME_SCOREBOARD),

        .CHECK_AXI_TRANSACTIONS(CHECK_AXI_TRANSACTIONS),
        .OPS_TAG_METHOD(OPS_TAG_METHOD),
        .BRAM_DATA_WIDTH(BRAM_DATA_WIDTH),
        .BRAM_DATA_DEPTH(BRAM_DATA_DEPTH)
    ) scoreboard_t;
    scoreboard_t scoreboard;

    // actual checking is implemented with the transactions
    // generic checker implements this in a uniform way
    NorthcapeGenericChecker generic_checker;

    function new(string name = "", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    const int unsigned max_axi_transfer_bytes = AXI_DATA_WIDTH / 8 * AXI5_MAX_BURST_LEN;

    // Ops uses capabilities in sequential order
    capability_id_t current_capability_id;

    typedef NorthcapeCapabilityOpsAgentConfig#(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_USER_WIDTH(AXI_USER_WIDTH),

        .AXI_LITE_DATA_WIDTH(AXI_LITE_DATA_WIDTH),
        .AXI_LITE_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),

        .HASH_TYPE(HASH_TYPE),

        .INITIAL_CMT_BASE(INITIAL_CMT_BASE),
        .INITIAL_CMT_SIZE_CLOG2(INITIAL_CMT_SIZE_CLOG2)
    ) agent_config_t;

    device_task_interface_t device_task_intf;

    function void build_phase(uvm_phase phase);

      agent_config_t agent_config;


      `uvm_info(COMPONENT_NAME, $sformatf(
                "Retrieving Capability Ops Agent Config of type %s name %s into config DB!",
                $typename(
                    agent_config
                ),
                CAPABILITY_OPS_AGENT_CONFIG_NAME
                ), UVM_DEBUG);

      if (!uvm_config_db#(agent_config_t)::get(
              this, "", CAPABILITY_OPS_AGENT_CONFIG_NAME, agent_config
          )) begin
        `uvm_fatal(COMPONENT_NAME, "Failed to get config object!");
      end

      this.requests_in_ops = agent_config.requests_in_ops;
      this.requests_in_cache = agent_config.requests_in_cache;
      this.initial_cmt_base = agent_config.initial_cmt_base;
      this.initial_cmt_size_clog2 = agent_config.initial_cmt_size_clog2;
      this.cmt_intf = agent_config.cmt_intf;
      this.mmio = agent_config.mmio;
      this.csr_intf = agent_config.csr_intf;
      this.ops_analysis_port = agent_config.ops_analysis_port;
      this.cache_analysis_port = agent_config.cache_analysis_port;
      this.reset_intf = agent_config.reset_intf;
      this.device_task_intf = agent_config.device_task_intf;
      this.irq_intf = agent_config.irq_intf;

      this.scoreboard = new("scoreboard", this);
      this.sequence_scoreboard = new("scoreboard_sequence");
      this.sequencer_scoreboard = new("scoreboard_sequencer", this);

      this.generic_checker = new("checker", this);

      this.mmio_driver = new("MMIO driver", this);
      if (CHECK_AXI_TRANSACTIONS) begin
        this.bram_driver = new("BRAM driver", this);
      end
      this.sequencer_mmio = new("MMIO Sequencer", this);
      this.sequence_bram = new("bram_sequence");
      this.sequencer_bram = new("BRAM Sequencer", this);
      this.csr_driver = new("CSR driver", this.csr_intf, this);
      this.sequencer_csr = new("CSR Sequencer", this);

      // Root capability created during reset
      this.current_capability_id = NORTHCAPE_ROOT_CAPABILITY_ID + 1;

      if (PROVIDE_RNG_INTERFACE) begin
        this.rng_driver = new("RNG Driver", this);
        this.sequencer_rng = new("RNG sequencer", this);
        this.rng_sequence = new("RNG sequence");
      end

    endfunction

    function void connect_phase(uvm_phase phase);
      scoreboard.transaction_port.connect(sequencer_scoreboard.seq_item_export);

      if (CHECK_AXI_TRANSACTIONS) begin
        ops_analysis_port.connect(scoreboard.ops_result_fifo.analysis_export);
        cache_analysis_port.connect(scoreboard.cache_result_fifo.analysis_export);
      end

      scoreboard.checker_port.connect(generic_checker.analysis_export);

      mmio_driver.ap.connect(scoreboard.mmio_result_fifo.analysis_export);
      mmio_driver.seq_item_port.connect(sequencer_mmio.seq_item_export);
      csr_driver.ap.connect(scoreboard.csr_result_fifo.analysis_export);
      csr_driver.seq_item_port.connect(sequencer_csr.seq_item_export);
      if (CHECK_AXI_TRANSACTIONS) begin
        bram_driver.ap.connect(scoreboard.bram_result_fifo.analysis_export);
        bram_driver.seq_item_port.connect(sequencer_bram.seq_item_export);
      end

      if (PROVIDE_RNG_INTERFACE) begin
        rng_driver.seq_item_port.connect(sequencer_rng.seq_item_export);
      end
    endfunction

    typedef transaction_axi_master_t queue_of_transaction_axi_master[$];

    /**
      * Transactions that zero out the CMT, after reset and resize.
      */
    function queue_of_transaction_axi_master get_reset_transactions();
      bit [AXI_ADDR_WIDTH-1:0] current_cmt_base, cmt_end;
      transaction_axi_master_t ret[$];

      current_cmt_base = INITIAL_CMT_BASE;
      cmt_end = current_cmt_base + $bits(northcape_cmt_entry_t) / 8 * (1 << INITIAL_CMT_SIZE_CLOG2);

      while (current_cmt_base < cmt_end) begin
        transaction_cmt_zero_t transaction;
        // we need size and is last to determine the tst length for the driver to expect
        transaction = new(
            "zero_transaction",
            INITIAL_CMT_SIZE_CLOG2,
            (current_cmt_base + max_axi_transfer_bytes >= cmt_end)
        );
        ret.push_back(transaction);

        current_cmt_base += max_axi_transfer_bytes;
      end

      return ret;
    endfunction

    function transaction_axi_master_t get_root_capability_init_transaction();
      transaction_create_cap_t create_transaction;

      create_transaction = new("reset_transaction");

      return create_transaction;
    endfunction

    function void bram_process_id_allocation(
        input transaction_t current_transaction,
        input uvm_queue#(bram_transaction_t) bram_transactions);
      bram_transaction_t bram_transaction;
      // implicit mod
      logic [$clog2(
BRAM_DATA_WIDTH
)-1:0] successfull_lookup_index = current_transaction.unsuccessful_lookups;

      for (
          int row = 0; row < current_transaction.unsuccessful_lookups / BRAM_DATA_WIDTH; row++
      ) begin
        // fully occupied rows
        bram_transaction = new();
        bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
        // not used by driver
        bram_transaction.addr = '0;
        bram_transaction.data = '1;
        bram_transactions.push_back(bram_transaction);
      end

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Unsuccessful lookups: %d max length %d for type %s!",
                current_transaction.unsuccessful_lookups,
                get_max_capability_id(
                    current_transaction.intended_capability_type
                ),
                current_transaction.intended_capability_type.name()
                ), UVM_HIGH);

      if (current_transaction.unsuccessful_lookups <= get_max_capability_id(
              current_transaction.intended_capability_type
          )) begin
        // successful lookup
        bram_transaction = new();
        bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
        bram_transaction.addr = '0;
        bram_transaction.data = '1;
        bram_transaction.data[successfull_lookup_index] = 1'b0;
        bram_transactions.push_back(bram_transaction);
      end else begin
        `uvm_info(COMPONENT_NAME, "Skipping successfull check idle read!", UVM_HIGH);
      end

    endfunction

    // the ops will have to un-set the valid bit for any capabilities it invalidated during an operation
    // it will also have to set the valid bit for any capabilities that it newly created
    // will always set all occupied bits to 1 to make sure only the correct one is kicked
    function void bram_process_occupied_updates(
        input transaction_t current_transaction,
        input uvm_queue#(bram_transaction_t) bram_transactions);
      bram_transaction_t bram_transaction;

      // write of the new input capability (or update of the input for DROP)
      bram_transaction = new();
      bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
      bram_transaction.addr = '0;
      bram_transaction.data = '1;
      bram_transactions.push_back(bram_transaction);

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) begin
        // always finishes after the input write
        return;
      end

      // update of the input / parent capability
      if(current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP || current_transaction.drop_make_one_capability_invalid == 1'b0 || current_transaction.number_indirect_caps != 0)
      begin
        bram_transaction = new();
        bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
        bram_transaction.addr = '0;
        bram_transaction.data = '1;
        bram_transactions.push_back(bram_transaction);
      end

      // update of grandparent for drop
      if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER && !current_transaction.drop_make_one_capability_invalid && current_transaction.number_indirect_caps != 0)
      begin
        bram_transaction = new();
        bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
        bram_transaction.addr = '0;
        bram_transaction.data = '1;
        bram_transactions.push_back(bram_transaction);
      end

      // update of grandparent for lock/merge
      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE || (current_transaction.operation ==  NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK && current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT)) begin
        bram_transaction = new();
        bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
        bram_transaction.addr = '0;
        bram_transaction.data = '1;
        bram_transactions.push_back(bram_transaction);
      end

    endfunction

    /**
      * Accepts and checks transactions for CMT zero out, after reset and resize.
      */
    task process_zero_cmt(uvm_queue#(bram_transaction_t) bram_transactions);
      transaction_axi_master_t transactions_zero[$];
      bram_transaction_t bram_transaction;
      int unsigned number_transactions;


      transactions_zero   = get_reset_transactions();

      number_transactions = transactions_zero.size();

      while (transactions_zero.size() > 0) begin
        requests_in_ops.put(transactions_zero.pop_front());
      end

      requests_in_cache.put(get_root_capability_init_transaction());
      // at this point, the BRAM was reset
      bram_transaction = new();
      bram_transaction.transaction_type = NORTHCAPE_BRAM_READ;
      bram_transaction.addr = '0;
      bram_transaction.data = '0;
      bram_transactions.push_back(bram_transaction);


    endtask


    task process_revoke(const ref transaction_t current_transaction);
      transaction_revoke_t revoke_transaction;

      `uvm_info(COMPONENT_NAME, $sformatf(
                "Expecting %d revoke writes!", current_transaction.get_number_revoke_writes()),
                UVM_DEBUG);
      for (int unsigned i = 0; i < current_transaction.get_number_revoke_writes(); i++) begin
        revoke_transaction = new("revoke transaction", i);
        revoke_transaction.do_copy(current_transaction);
        requests_in_ops.put(revoke_transaction);
      end
    endtask

    // creates expected transactions for capability read/modify/write, as used in, e.g., create, derive, drop, ...
    task process_capability_rmw(const ref transaction_t current_transaction,
                                uvm_queue#(bram_transaction_t) transactions_bram);
      transaction_read_cmt_entry_t  read_transaction;
      transaction_write_cmt_entry_t write_transaction;

      // lookup of the input transaction
      read_transaction = new("read transaction", .is_right_input(0));
      read_transaction.do_copy(current_transaction);
      requests_in_cache.put(read_transaction);

      if(current_transaction.read_resp != OKAY || current_transaction.input_capability_allows_operation(
              1'b0) != NORTHCAPE_NO_ERROR) begin
        `uvm_info(COMPONENT_NAME, "Expecting immediate termination after input read!", UVM_HIGH);
        // will error out IMMEDIATELY
        return;
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE, NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT}) begin
        for (int unsigned i = 0; i < current_transaction.recursion_cmt_entries.size(); i++) begin
          // call zero was lookup of input above
          read_transaction = new("read transaction", i + 1);
          read_transaction.do_copy(current_transaction);
          requests_in_cache.put(read_transaction);

          if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP) begin
            // for non-unlock, drop only reads direct parent
            // if called on a lock-holder capability, it has to read until the direct capability or whatever the top of the hierarchie is
            if(current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_LOCK_HOLDER)
            begin
              break;
            end
          end
        end
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE}) begin
        read_transaction = new("read transaction second cap", .is_right_input(1));
        read_transaction.do_copy(current_transaction);
        requests_in_cache.put(read_transaction);

        if(current_transaction.read_resp != OKAY || current_transaction.input_capability_allows_operation(
                1'b1
            ) != NORTHCAPE_NO_ERROR) begin
          `uvm_info(COMPONENT_NAME,
                    "Read response error or operation not allowed - not expecting output write!",
                    UVM_HIGH);
          // will error out IMMEDIATELY
          return;
        end
      end

      if (!(current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT})) begin
        // DROP, RESTRICT only overwrite the existing capabilities
        // INSPECT has no writes
        bram_process_id_allocation(current_transaction, transactions_bram);
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT}) begin
        // nothing to do!
        return;
      end

      if (!current_transaction.valid_test) begin
        // no output
        return;
      end

      write_transaction =
          new("write transaction new (created/derived/overwritten/merged) capability");
      write_transaction.do_copy(current_transaction);
      requests_in_cache.put(write_transaction);

      bram_process_occupied_updates(current_transaction, transactions_bram);

      if (current_transaction.write_resp != OKAY) begin
        // will error out IMMEDIATELY
        return;
      end

      if (current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT) begin
        // only overwrites the input capability, no changes to parents done
        return;
      end

      // in case drop was done on a capability whose parent was revoked, there might not be an update write
      if(current_transaction.operation != NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP || current_transaction.drop_make_one_capability_invalid == 1'b0 || current_transaction.number_indirect_caps != 0)
      begin
        write_transaction = new("update transaction old capability");
        write_transaction.do_copy(current_transaction);
        requests_in_cache.put(write_transaction);
      end

      if(current_transaction.operation == NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP && current_transaction.input_cmt_entry.capability_type == NORTHCAPE_CMT_LOCK_HOLDER && !current_transaction.drop_make_one_capability_invalid && current_transaction.number_indirect_caps != 0)
      begin
        // this write resets the locked key of the direct parent
        write_transaction = new("update transaction direct capability base");
        write_transaction.do_copy(current_transaction);
        requests_in_cache.put(write_transaction);
      end

      if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE} || (current_transaction.operation ==  NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK && current_transaction.input_cmt_entry.capability_type != NORTHCAPE_CMT_DIRECT)) begin
        // overwrite for second input transaction (merge)
        // overwrite the locked key for the direct capability (lock) - only if direct parent and capability to overwrite are different
        write_transaction = new("update transaction old capability #2");
        write_transaction.do_copy(current_transaction);
        requests_in_cache.put(write_transaction);
      end

    endtask

    function bit [AXI_ADDR_WIDTH - 1 : 0] get_output_capability_token();
      return scoreboard.get_output_capability_token();
    endfunction


    semaphore ops_transactions_available;
    semaphore ops_finished;
    static task_id_t unseal_global_tid = 0;

    task run_phase(uvm_phase phase);
      transaction_t current_transaction;
      uvm_queue #(transaction_t) transactions, transactions_scoreboard;
      uvm_queue #(bram_transaction_t) transactions_bram;
      uvm_queue #(transaction_rng_t) transactions_rng;
      int unsigned test_id;
      transaction_rng_initial_t transaction_rng_initial;
      // auxilliary register one is shared between derive and merge
      bit [AXI_ADDR_WIDTH-1:0] aux1_input;
      NorthcapeCapabilityOpsEnableSequence #(
          .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
          .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
      ) enable_sequence;

      phase.raise_objection(this);


      enable_sequence =
          new(cmt_intf);

      `uvm_info(COMPONENT_NAME, "Agent reset phase start!", UVM_MEDIUM);

      device_task_intf.test_producer_clocking.active_device <= '0;
      device_task_intf.test_producer_clocking.active_task <= '0;
      device_task_intf.test_producer_clocking.device_specific_restriction <= '0;
      device_task_intf.test_producer_clocking.parsing_error <= 0;

      transactions_bram = new("BRAM transactions");
      uvm_config_db#(uvm_queue#(bram_transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_BRAM,
                                                          transactions_bram);

      fork
        begin
          enable_sequence.start(sequencer_mmio);
        end
        begin
          if (CHECK_AXI_TRANSACTIONS) begin
            // need to inform master that resets will arrive first
            process_zero_cmt(transactions_bram);

            // master needs a few cycles to process
            @(reset_intf.reset_clocking);
            @(reset_intf.reset_clocking);

            reset_intf.reset_clocking.resetn <= 0;
            @(reset_intf.reset_clocking);
            @(reset_intf.reset_clocking);

            reset_intf.reset_clocking.resetn <= 1;
            @(reset_intf.reset_clocking);
            @(reset_intf.reset_clocking);

          end

          transactions_rng = new("RNG constructions");
          uvm_config_db#(uvm_queue#(transaction_rng_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_RNG,
                                                             transactions_rng);

          // might only exist at run time
          if (!uvm_config_db#(uvm_queue#(transaction_t))::get(
                  null, "", TRANSACTIONS_QUEUE_NAME_AGENT, transactions
              )) begin
            `uvm_fatal(COMPONENT_NAME, "Failed to get transactions object!");
          end

          if (PROVIDE_RNG_INTERFACE) begin
            transaction_rng_initial = new("initial RNG transaction");
            if (transaction_rng_initial.randomize() == 0) begin
              `uvm_fatal(COMPONENT_NAME, "Could not randomize transaction!");
            end
            transactions_rng.push_back(transaction_rng_initial);

            scoreboard.set_initial_seed(transaction_rng_initial.initial_seed);

            // sequence should always be completed
            rng_sequence.start(sequencer_rng);
          end

          if (CHECK_AXI_TRANSACTIONS) begin
            sequence_bram.start(sequencer_bram);
          end

        end
      join

      `uvm_info(COMPONENT_NAME, "Agent reset phase complete!", UVM_MEDIUM);


      `uvm_info(COMPONENT_NAME, "Agent run phase start", UVM_MEDIUM);

      transactions_scoreboard = new("Scoreboard transactions");
      uvm_config_db#(uvm_queue#(transaction_t))::set(null, "", TRANSACTIONS_QUEUE_NAME_SCOREBOARD,
                                                     transactions_scoreboard);
      // have to wait for integration agent to complete setup, generate a transaction for us
      if (ops_transactions_available != null) begin
        `uvm_info(COMPONENT_NAME, "Waiting for lockstep sema", UVM_HIGH);
        ops_transactions_available.get();
        `uvm_info(COMPONENT_NAME, "Lockstep sema triggered", UVM_HIGH);
      end

      while (transactions.size() > 0) begin : transactionForward
        transaction_rng_t rng_transaction;

        NorthcapeCapabilityOpsStartSequence #(
            .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
            .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
        ) sequence_start;

        NorthcapeCapabilityOpsStopSequence #(
            .AXI_ADDR_WIDTH(AXI_LITE_ADDR_WIDTH),
            .AXI_DATA_WIDTH(AXI_LITE_DATA_WIDTH)
        ) sequence_stop;

        NorthcapeCapabilityOpsStartSequenceCSR sequence_start_csr;
        NorthcapeCapabilityOpsStopSequenceCSR sequence_stop_csr;

        current_transaction = transactions.pop_front();

        `uvm_info(COMPONENT_NAME, $sformatf(
                  "Got transaction %s", current_transaction.convert2string()), UVM_DEBUG);

        enable_sequence = new(
            cmt_intf
        );
        enable_sequence.start(sequencer_mmio);

        rng_transaction = new("RNG transaction");

        rng_transaction.do_copy(current_transaction);

        transactions_rng.push_back(rng_transaction);


        current_transaction.output_capability_id = current_capability_id + current_transaction.unsuccessful_lookups;

        transactions_scoreboard.push_back(current_transaction);

        device_task_intf.test_producer_clocking.active_device <= current_transaction.device_id_current;
        device_task_intf.test_producer_clocking.active_task <= current_transaction.task_id_current;

        if (CHECK_AXI_TRANSACTIONS && (current_transaction.valid_test || current_transaction.operation_is_supported())) begin
          unique case (current_transaction.operation)
            NORTHCAPE_CAPABILITY_OPS_OPERATION_CREATE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE,NORTHCAPE_CAPABILITY_OPS_OPERATION_DROP,NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE,NORTHCAPE_CAPABILITY_OPS_OPERATION_CLONE,NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE,NORTHCAPE_CAPABILITY_OPS_OPERATION_LOCK, NORTHCAPE_CAPABILITY_OPS_OPERATION_INSPECT, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
              process_capability_rmw(current_transaction, transactions_bram);
            end
            default: begin
              `uvm_fatal(COMPONENT_NAME, $sformatf(
                         "Invalid capability operation %x!", current_transaction.operation));
            end
          endcase
        end

        if (current_transaction.operation inside {NORTHCAPE_CAPABILITY_OPS_OPERATION_REVOKE}) begin
          // need to check write request(s) into main mem
          process_revoke(current_transaction);
        end



        if (PROVIDE_RNG_INTERFACE) begin
          fork
            rng_sequence.start(sequencer_rng);
          join_none
        end

        unique case (current_transaction.operation)
          NORTHCAPE_CAPABILITY_OPS_OPERATION_DERIVE, NORTHCAPE_CAPABILITY_OPS_OPERATION_RESTRICT: begin
            aux1_input = {32'h0, current_transaction.parent_offset};
          end
          NORTHCAPE_CAPABILITY_OPS_OPERATION_MERGE: begin
            aux1_input = current_transaction.input_token_right;
          end
          default: begin
            // this is abused as random number for the register
            // the register is ignored
            aux1_input = current_transaction.input_token_right;
          end
        endcase
        if (current_transaction.use_rcsr_interface) begin
          sequence_start_csr = new(
              "sequence start",
              current_transaction.input_token,
              current_transaction.get_encoded_restriction(),
              current_transaction.restriction_type,
              current_transaction.direction,
              current_transaction.new_segment_length,
              current_transaction.restriction_enabled,
              current_transaction.read_perm,
              current_transaction.write_perm,
              current_transaction.x_perm,
              current_transaction.lockable_perm,
              current_transaction.irq_accessible_perm,
              current_transaction.cacheable_tlb_perm,
              current_transaction.cacheable_access_perm,
              current_transaction.operation,
              current_transaction.intended_capability_type,
              aux1_input,
              current_transaction.use_isr_fsm,
              current_transaction.device_id_current,
              current_transaction.task_id_current,
              current_transaction.pcr_index
          );

          sequence_stop_csr = new(
              "sequence_stop",
              current_transaction.use_isr_fsm,
              current_transaction.device_id_current,
              current_transaction.task_id_current
          );
        end else begin
          sequence_start = new(
              "sequence start",
              current_transaction.input_token,
              current_transaction.get_encoded_restriction(),
              current_transaction.restriction_type,
              current_transaction.direction,
              current_transaction.new_segment_length,
              current_transaction.restriction_enabled,
              current_transaction.read_perm,
              current_transaction.write_perm,
              current_transaction.x_perm,
              current_transaction.lockable_perm,
              current_transaction.irq_accessible_perm,
              current_transaction.cacheable_tlb_perm,
              current_transaction.cacheable_access_perm,
              current_transaction.operation,
              current_transaction.intended_capability_type,
              aux1_input,
              current_transaction.use_isr_fsm,
              current_transaction.pcr_index
          );

          sequence_stop = new("sequence_stop", current_transaction.use_isr_fsm);

        end

        `uvm_info(COMPONENT_NAME, "Starting sequence initialized!", UVM_HIGH);
        if (current_transaction.use_rcsr_interface) begin
          sequence_start_csr.start(sequencer_csr);
        end else begin
          sequence_start.start(sequencer_mmio);
        end
        `uvm_info(COMPONENT_NAME, "Starting sequence done!", UVM_HIGH);

        if (CHECK_AXI_TRANSACTIONS) begin
          sequence_bram.start(sequencer_bram);
        end

        // last read in start sequence clears the interrupt
        `uvm_info(COMPONENT_NAME, "Starting scoreboard sequence!", UVM_HIGH);
        sequence_scoreboard.start(sequencer_scoreboard);

        if (current_transaction.valid_test || current_transaction.operation_is_supported()) begin
          `uvm_info(COMPONENT_NAME, "Waiting for operation complete interrupt!", UVM_HIGH);
          @(irq_intf.test_consumer_clocking iff irq_intf.test_consumer_clocking.irqs[0] == 1);
        end

        `uvm_info(COMPONENT_NAME, "Waiting a few cycles to allow RNG to catch up!", UVM_HIGH);

        // wait for RNG interface to generate new output
        repeat (AXI_LITE_DATA_WIDTH) begin
          @(cmt_intf.test_consumer_clocking);
          @(cmt_intf.test_consumer_clocking);
        end

        `uvm_info(COMPONENT_NAME,
                  "Completion IRQ high or invalid test - stopping sequence initialized!", UVM_HIGH);
        if (current_transaction.use_rcsr_interface) begin
          sequence_stop_csr.start(sequencer_csr);
        end else begin
          sequence_stop.start(sequencer_mmio);
        end
        `uvm_info(COMPONENT_NAME, "Stopping sequence done!", UVM_HIGH);

        test_id++;

        `uvm_info(COMPONENT_NAME, $sformatf("Finished transaction %d", test_id), UVM_MEDIUM);

        if (ops_finished != null) begin
          ops_finished.put();
        end

        // have to wait for integration agent to complete setup, generate a transaction for us
        if (ops_transactions_available != null) begin
          `uvm_info(COMPONENT_NAME, "Waiting for lockstep sema", UVM_HIGH);
          ops_transactions_available.get();
          `uvm_info(COMPONENT_NAME, "Lockstep sema triggered", UVM_HIGH);
        end

      end : transactionForward

      `uvm_info(COMPONENT_NAME, "Ops Agent completed - dropping objection!", UVM_MEDIUM);


      phase.drop_objection(this);


    endtask


  endclass

endpackage
