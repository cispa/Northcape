`timescale 1ps/100fs
/**
  * Testbench for entire capability soc project - clock and reset generator, memory simulator
  * Based on MIG's example testbench project
  */
module vivado_top;
    //***************************************************************************
    // The following parameters refer to width of various ports
    //***************************************************************************
    parameter COL_WIDTH             = 10;
                                        // # of memory Column Address bits.
    parameter CS_WIDTH              = 1;
                                        // # of unique CS outputs to memory.
    parameter DM_WIDTH              = 4;
                                        // # of DM (data mask)
    parameter DQ_WIDTH              = 32;
                                        // # of DQ (data)
    parameter DQS_WIDTH             = 4;
    parameter DQS_CNT_WIDTH         = 2;
                                        // = ceil(log2(DQS_WIDTH))
    parameter DRAM_WIDTH            = 8;
                                        // # of DQ per DQS
    parameter ECC                   = "OFF";
    parameter RANKS                 = 1;
                                        // # of Ranks.
    parameter ODT_WIDTH             = 1;
                                        // # of ODT outputs to memory.
    parameter ROW_WIDTH             = 15;
                                        // # of memory Row Address bits.
    parameter ADDR_WIDTH            = 29;
                                        // # = RANK_WIDTH + BANK_WIDTH
                                        //     + ROW_WIDTH + COL_WIDTH;
                                        // Chip Select is always tied to low for
                                        // single rank devices
    //***************************************************************************
    // The following parameters are mode register settings
    //***************************************************************************
    parameter BURST_MODE            = "8";
                                        // DDR3 SDRAM:
                                        // Burst Length (Mode Register 0).
                                        // # = "8", "4", "OTF".
                                        // DDR2 SDRAM:
                                        // Burst Length (Mode Register).
                                        // # = "8", "4".
    parameter CA_MIRROR             = "OFF";
                                        // C/A mirror opt for DDR3 dual rank
    
    //***************************************************************************
    // The following parameters are multiplier and divisor factors for PLLE2.
    // Based on the selected design frequency these parameters vary.
    //***************************************************************************
    parameter CLKIN_PERIOD          = 5000;
                                        // Input Clock Period


    //***************************************************************************
    // Simulation parameters
    //***************************************************************************
    parameter SIM_BYPASS_INIT_CAL   = "FAST";
                                        // # = "SIM_INIT_CAL_FULL" -  Complete
                                        //              memory init &
                                        //              calibration sequence
                                        // # = "SKIP" - Not supported
                                        // # = "FAST" - Complete memory init & use
                                        //              abbreviated calib sequence

    //***************************************************************************
    // IODELAY and PHY related parameters
    //***************************************************************************
    parameter TCQ                   = 100;
    //***************************************************************************
    // IODELAY and PHY related parameters
    //***************************************************************************
    parameter RST_ACT_LOW           = 1;
                                        // =1 for active low reset,
                                        // =0 for active high.

    //***************************************************************************
    // Referece clock frequency parameters
    //***************************************************************************
    parameter REFCLK_FREQ           = 200.0;
                                        // IODELAYCTRL reference clock frequency
    //***************************************************************************
    // System clock frequency parameters
    //***************************************************************************
    parameter tCK                   = 1250;
                                        // memory tCK paramter.
                        // # = Clock Period in pS.
    parameter nCK_PER_CLK           = 4;
                                        // # of memory CKs per fabric CLK

    
    //***************************************************************************
    // AXI4 Shim parameters
    //***************************************************************************
    parameter C_S_AXI_ID_WIDTH              = 9;
                                                // Width of all master and slave ID signals.
                                                // # = >= 1.
    parameter C_S_AXI_ADDR_WIDTH            = 30;
                                                // Width of S_AXI_AWADDR, S_AXI_ARADDR, M_AXI_AWADDR and
                                                // M_AXI_ARADDR for all SI/MI slots.
                                                // # = 32.
    parameter C_S_AXI_DATA_WIDTH            = 256;
                                                // Width of WDATA and RDATA on SI slot.
                                                // Must be <= APP_DATA_WIDTH.
                                                // # = 32, 64, 128, 256.
    parameter C_S_AXI_SUPPORTS_NARROW_BURST = 1;
                                                // Indicates whether to instatiate upsizer
                                                // Range: 0, 1


    //***************************************************************************
    // Debug and Internal parameters
    //***************************************************************************
    parameter DEBUG_PORT            = "OFF";
                                        // # = "ON" Enable debug signals/controls.
                                        //   = "OFF" Disable debug signals/controls.
    //***************************************************************************
    // Debug and Internal parameters
    //***************************************************************************
    parameter DRAM_TYPE             = "DDR3";

    

    //**************************************************************************//
    // Local parameters Declarations
    //**************************************************************************//

    localparam real TPROP_DQS          = 0.00;
                                        // Delay for DQS signal during Write Operation
    localparam real TPROP_DQS_RD       = 0.00;
                        // Delay for DQS signal during Read Operation
    localparam real TPROP_PCB_CTRL     = 0.00;
                        // Delay for Address and Ctrl signals
    localparam real TPROP_PCB_DATA     = 0.00;
                        // Delay for data signal during Write operation
    localparam real TPROP_PCB_DATA_RD  = 0.00;
                        // Delay for data signal during Read operation

    localparam MEMORY_WIDTH            = 16;
    localparam NUM_COMP                = DQ_WIDTH/MEMORY_WIDTH;
    localparam ECC_TEST 		   	= "OFF" ;
    localparam ERR_INSERT = (ECC_TEST == "ON") ? "OFF" : ECC ;
    

    localparam real REFCLK_PERIOD = (1000000.0/(2*REFCLK_FREQ));
    localparam RESET_PERIOD = 200000; //in pSec  
    localparam real SYSCLK_PERIOD = tCK;


    logic sys_clk_i;
    logic sys_clk_n;
    logic sys_clk_p;
    logic clk_ref_i;
    logic rst_ni;


    wire                               ddr3_reset_n;
    wire [DQ_WIDTH-1:0]                ddr3_dq_fpga;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_p_fpga;
    wire [DQS_WIDTH-1:0]               ddr3_dqs_n_fpga;
    wire [ROW_WIDTH-1:0]               ddr3_addr_fpga;
    wire [3-1:0]                       ddr3_ba_fpga;
    wire                               ddr3_ras_n_fpga;
    wire                               ddr3_cas_n_fpga;
    wire                               ddr3_we_n_fpga;
    wire [1-1:0]                       ddr3_cke_fpga;
    wire [1-1:0]                       ddr3_ck_p_fpga;
    wire [1-1:0]                       ddr3_ck_n_fpga;
    wire [(CS_WIDTH*1)-1:0]            ddr3_cs_n_fpga;
    wire [DM_WIDTH-1:0]                ddr3_dm_fpga;
    wire [ODT_WIDTH-1:0]               ddr3_odt_fpga;
        
    
    reg [(CS_WIDTH*1)-1:0]            ddr3_cs_n_sdram_tmp;
        
    reg [DM_WIDTH-1:0]                ddr3_dm_sdram_tmp;
        
    reg [ODT_WIDTH-1:0]               ddr3_odt_sdram_tmp;
        

    
    wire [DQ_WIDTH-1:0]                 ddr3_dq_sdram;
    reg [ROW_WIDTH-1:0]                 ddr3_addr_sdram [0:1];
    reg [3-1:0]                         ddr3_ba_sdram [0:1];
    reg                                 ddr3_ras_n_sdram;
    reg                                 ddr3_cas_n_sdram;
    reg                                 ddr3_we_n_sdram;
    wire [(CS_WIDTH*1)-1:0]             ddr3_cs_n_sdram;
    wire [ODT_WIDTH-1:0]                ddr3_odt_sdram;
    reg [1-1:0]                         ddr3_cke_sdram;
    wire [DM_WIDTH-1:0]                 ddr3_dm_sdram;
    wire [DQS_WIDTH-1:0]                ddr3_dqs_p_sdram;
    wire [DQS_WIDTH-1:0]                ddr3_dqs_n_sdram;
    reg [1-1:0]                         ddr3_ck_p_sdram;
    reg [1-1:0]                         ddr3_ck_n_sdram;

    // Clock generation
    initial
        sys_clk_i = 1'b0;
    always
        sys_clk_i = #(CLKIN_PERIOD/2.0) ~sys_clk_i;

    assign sys_clk_p = sys_clk_i;
    assign sys_clk_n = ~sys_clk_i;

    initial
        clk_ref_i = 1'b0;
    always
        clk_ref_i = #REFCLK_PERIOD ~clk_ref_i;
    // Reset generation
    initial begin
        rst_ni = 1'b0;         // Assert reset
        #RESET_PERIOD rst_ni = 1'b1;     // Deassert reset after 10 ns
    end

     always @( * ) begin
    ddr3_ck_p_sdram      <=  #(TPROP_PCB_CTRL) ddr3_ck_p_fpga;
    ddr3_ck_n_sdram      <=  #(TPROP_PCB_CTRL) ddr3_ck_n_fpga;
    ddr3_addr_sdram[0]   <=  #(TPROP_PCB_CTRL) ddr3_addr_fpga;
    ddr3_addr_sdram[1]   <=  #(TPROP_PCB_CTRL) (CA_MIRROR == "ON") ?
                                                 {ddr3_addr_fpga[ROW_WIDTH-1:9],
                                                  ddr3_addr_fpga[7], ddr3_addr_fpga[8],
                                                  ddr3_addr_fpga[5], ddr3_addr_fpga[6],
                                                  ddr3_addr_fpga[3], ddr3_addr_fpga[4],
                                                  ddr3_addr_fpga[2:0]} :
                                                 ddr3_addr_fpga;
    ddr3_ba_sdram[0]     <=  #(TPROP_PCB_CTRL) ddr3_ba_fpga;
    ddr3_ba_sdram[1]     <=  #(TPROP_PCB_CTRL) (CA_MIRROR == "ON") ?
                                                 {ddr3_ba_fpga[3-1:2],
                                                  ddr3_ba_fpga[0],
                                                  ddr3_ba_fpga[1]} :
                                                 ddr3_ba_fpga;
    ddr3_ras_n_sdram     <=  #(TPROP_PCB_CTRL) ddr3_ras_n_fpga;
    ddr3_cas_n_sdram     <=  #(TPROP_PCB_CTRL) ddr3_cas_n_fpga;
    ddr3_we_n_sdram      <=  #(TPROP_PCB_CTRL) ddr3_we_n_fpga;
    ddr3_cke_sdram       <=  #(TPROP_PCB_CTRL) ddr3_cke_fpga;
  end
    

  always @( * )
    ddr3_cs_n_sdram_tmp   <=  #(TPROP_PCB_CTRL) ddr3_cs_n_fpga;
  assign ddr3_cs_n_sdram =  ddr3_cs_n_sdram_tmp;
    

  always @( * )
    ddr3_dm_sdram_tmp <=  #(TPROP_PCB_DATA) ddr3_dm_fpga;//DM signal generation
  assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;
    

  always @( * )
    ddr3_odt_sdram_tmp  <=  #(TPROP_PCB_CTRL) ddr3_odt_fpga;
  assign ddr3_odt_sdram =  ddr3_odt_sdram_tmp;
    

    // Controlling the bi-directional BUS

    genvar dqwd;
    generate
        for (dqwd = 1;dqwd < DQ_WIDTH;dqwd = dqwd+1) begin : dq_delay
        WireDelay #
        (
            .Delay_g    (TPROP_PCB_DATA),
            .Delay_rd   (TPROP_PCB_DATA_RD),
            .ERR_INSERT ("OFF")
        )
        u_delay_dq
        (
            .A             (ddr3_dq_fpga[dqwd]),
            .B             (ddr3_dq_sdram[dqwd]),
            .reset         (sys_rst_n),
            .phy_init_done (init_calib_complete)
        );
        end
            WireDelay #
        (
            .Delay_g    (TPROP_PCB_DATA),
            .Delay_rd   (TPROP_PCB_DATA_RD),
            .ERR_INSERT ("OFF")
        )
        u_delay_dq_0
        (
            .A             (ddr3_dq_fpga[0]),
            .B             (ddr3_dq_sdram[0]),
            .reset         (sys_rst_n),
            .phy_init_done (init_calib_complete)
        );
    endgenerate

    genvar dqswd;
    generate
        for (dqswd = 0;dqswd < DQS_WIDTH;dqswd = dqswd+1) begin : dqs_delay
        WireDelay #
        (
            .Delay_g    (TPROP_DQS),
            .Delay_rd   (TPROP_DQS_RD),
            .ERR_INSERT ("OFF")
        )
        u_delay_dqs_p
        (
            .A             (ddr3_dqs_p_fpga[dqswd]),
            .B             (ddr3_dqs_p_sdram[dqswd]),
            .reset         (sys_rst_n),
            .phy_init_done (init_calib_complete)
        );

        WireDelay #
        (
            .Delay_g    (TPROP_DQS),
            .Delay_rd   (TPROP_DQS_RD),
            .ERR_INSERT ("OFF")
        )
        u_delay_dqs_n
        (
            .A             (ddr3_dqs_n_fpga[dqswd]),
            .B             (ddr3_dqs_n_sdram[dqswd]),
            .reset         (sys_rst_n),
            .phy_init_done (init_calib_complete)
        );
        end
    endgenerate


    //**************************************************************************//
    // Memory Models instantiations
    //**************************************************************************//

    genvar r,i;
    generate
        for (r = 0; r < CS_WIDTH; r = r + 1) begin: mem_rnk
        if(DQ_WIDTH/16) begin: mem
            for (i = 0; i < NUM_COMP; i = i + 1) begin: gen_mem
            ddr3_model u_comp_ddr3
                (
                .rst_n   (ddr3_reset_n),
                .ck      (ddr3_ck_p_sdram),
                .ck_n    (ddr3_ck_n_sdram),
                .cke     (ddr3_cke_sdram[r]),
                .cs_n    (ddr3_cs_n_sdram[r]),
                .ras_n   (ddr3_ras_n_sdram),
                .cas_n   (ddr3_cas_n_sdram),
                .we_n    (ddr3_we_n_sdram),
                .dm_tdqs (ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
                .ba      (ddr3_ba_sdram[r]),
                .addr    (ddr3_addr_sdram[r]),
                .dq      (ddr3_dq_sdram[16*(i+1)-1:16*(i)]),
                .dqs     (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
                .dqs_n   (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
                .tdqs_n  (),
                .odt     (ddr3_odt_sdram[r])
                );
            end
        end
        if (DQ_WIDTH%16) begin: gen_mem_extrabits
            ddr3_model u_comp_ddr3
            (
            .rst_n   (ddr3_reset_n),
            .ck      (ddr3_ck_p_sdram),
            .ck_n    (ddr3_ck_n_sdram),
            .cke     (ddr3_cke_sdram[r]),
            .cs_n    (ddr3_cs_n_sdram[r]),
            .ras_n   (ddr3_ras_n_sdram),
            .cas_n   (ddr3_cas_n_sdram),
            .we_n    (ddr3_we_n_sdram),
            .dm_tdqs ({ddr3_dm_sdram[DM_WIDTH-1],ddr3_dm_sdram[DM_WIDTH-1]}),
            .ba      (ddr3_ba_sdram[r]),
            .addr    (ddr3_addr_sdram[r]),
            .dq      ({ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)],
                        ddr3_dq_sdram[DQ_WIDTH-1:(DQ_WIDTH-8)]}),
            .dqs     ({ddr3_dqs_p_sdram[DQS_WIDTH-1],
                        ddr3_dqs_p_sdram[DQS_WIDTH-1]}),
            .dqs_n   ({ddr3_dqs_n_sdram[DQS_WIDTH-1],
                        ddr3_dqs_n_sdram[DQS_WIDTH-1]}),
            .tdqs_n  (),
            .odt     (ddr3_odt_sdram[r])
            );
        end
        end
    endgenerate

wire audio_codec_iic_scl_io;
wire audio_codec_iic_sda_io;

wire eth_mdio_mdc_mdc;
wire eth_mdio_mdc_mdio_io;

wire ja_pin1_io;
wire ja_pin2_io;
wire ja_pin3_io;
wire ja_pin4_io;
wire ja_pin7_io;
wire ja_pin8_io;
wire ja_pin9_io;

SoC_wrapper i_soc(
    // Audio
    .audio_codec_iic_scl_io(audio_codec_iic_scl_io),
    .audio_codec_iic_sda_io(audio_codec_iic_sda_io),

    // Ethernet
    .eth_mdio_mdc_mdc(eth_mdio_mdc_mdc),
    .eth_mdio_mdc_mdio_io(eth_mdio_mdc_mdio_io),
    .eth_rgmii_rd('0),
    .eth_rgmii_rx_ctl(1'b0),
    .eth_rgmii_rxc(1'b0),
    .eth_rgmii_td( /* open */ ),
    .eth_rgmii_tx_ctl( /* open */ ),
    .eth_rgmii_txc(/* open */),
    .phy_reset_out(/* open */),

    // DDR
    .ddr3_sdram_dq              (ddr3_dq_fpga),
    .ddr3_sdram_dqs_n           (ddr3_dqs_n_fpga),
    .ddr3_sdram_dqs_p           (ddr3_dqs_p_fpga),

    .ddr3_sdram_addr            (ddr3_addr_fpga),
    .ddr3_sdram_ba              (ddr3_ba_fpga),
    .ddr3_sdram_ras_n           (ddr3_ras_n_fpga),
    .ddr3_sdram_cas_n           (ddr3_cas_n_fpga),
    .ddr3_sdram_we_n            (ddr3_we_n_fpga),
    .ddr3_sdram_reset_n         (ddr3_reset_n),
    .ddr3_sdram_ck_p            (ddr3_ck_p_fpga),
    .ddr3_sdram_ck_n            (ddr3_ck_n_fpga),
    .ddr3_sdram_cke             (ddr3_cke_fpga),
    .ddr3_sdram_cs_n            (ddr3_cs_n_fpga),

    .ddr3_sdram_dm              (ddr3_dm_fpga),

    .ddr3_sdram_odt             (ddr3_odt_fpga),
    
    // fan
    .fan_tach(1'b0),
    
    // PMOD
    .ja_pin1_io(ja_pin1_io),
    .ja_pin2_io(ja_pin2_io),
    .ja_pin3_io(ja_pin3_io),
    .ja_pin4_io(ja_pin4_io),
    .ja_pin7_io(ja_pin7_io),
    .ja_pin8_io(ja_pin8_io),
    .ja_pin9_io(ja_pin9_io),

    .jtag_tck(1'b0),
    .jtag_tdi(1'b0),
    .jtag_tdo(/* open */),
    .jtag_tms(1'b0),

    .cpu_resetn(rst_ni),

    .spi_clk_o( /* open */ ),
    .spi_miso (1'b0),
    .spi_mosi( /* open */),
    .spi_ss(/* open */ ),

    .sys_diff_clock_clk_n(sys_clk_n),
    .sys_diff_clock_clk_p(sys_clk_p),

    .usb_uart_rxd(1'b0),
    .usb_uart_txd(/* open */ )




);

endmodule
