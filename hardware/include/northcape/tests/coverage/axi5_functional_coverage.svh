/**
  * Definitions for setup and evaluation of coverage points for AXI slaves and masters.
  */
`ifdef NORTHCAPE_TEST_COVERAGE
/* verilog_format: off */
`define AXI5_TEST_DECLARE_COVERAGE_GROUP(INST)                                                                      \
/* verilog_format: on */                                                                                            \
        covergroup ``INST``_coverage_group;                                                                         \
        axi_request_type: coverpoint INST.axi_request_type;                                                         \
        invalid_access: coverpoint INST.invalid_access;                                                             \
        /* omitting addresses due to large space and limited impact */                                              \
        /* we want to see a token of each KIND, however */                                                          \
        capability_token: coverpoint INST.capability_token {                                                        \
                                                                                                                    \
            wildcard bins offset_32 = {64'b00??????????????????????????????????????????????????????????????};       \
            wildcard bins offset_0 = {64'b01??????????????????????????????????????????????????????????????};        \
            wildcard bins offset_16 = {64'b10??????????????????????????????????????????????????????????????};       \
            wildcard bins offset_24 = {64'b11??????????????????????????????????????????????????????????????};       \
        }                                                                                                           \
                                                                                                                    \
        test_len: coverpoint INST.test_len;                                                                         \
        burst_type: coverpoint INST.burst_type {                                                                    \
            ignore_bins reserved = {BURST_RESERVED};                                                                \
        }                                                                                                           \
        test_size: coverpoint INST.test_size;                                                                       \
        test_lock: coverpoint INST.test_lock;                                                                       \
        test_cache: coverpoint INST.test_cache;                                                                     \
        test_prot: coverpoint INST.test_prot;                                                                       \
        test_qos: coverpoint INST.test_qos;                                                                         \
        test_region: coverpoint INST.test_region;                                                                   \
                                                                                                                    \
        /* ID 0 and not 0 interesting, specific values of ID do not change the behavior, however */                 \
        test_id: coverpoint INST.test_id {                                                                          \
            wildcard bins id_0 = {32'h0};                                                                           \
            wildcard bins id_not_0 = {32'h????????};                                                                \
        }                                                                                                           \
                                                                                                                    \
        atomic_type: coverpoint INST.atomic_type;                                                                   \
        /* given_response mimics expected_response or is ignored */                                                 \
        expected_response: coverpoint INST.expected_response;                                                       \
                                                                                                                    \
                                                                                                                    \
        regression_ready_before_valid: coverpoint INST.regression_ready_before_valid;                               \
        regression_keep_valid_high: coverpoint INST.regression_keep_valid_high;                                     \
                                                                                                                    \
        /* delays excluded, as there are too many combinations */                                                   \
                                                                                                                    \
        /* atomic_type is ignored for read, but allowed to be set to anything - test this in coverage*/             \
        /* segment_length has large space, and is always 0 for invalid access - excluded from cross cover group */  \
                                                                                                                    \
        /* TODO coverpoint for response segment length causes crash in Vivado compiler */                           \
        /* all variations/ types of AXI request relevant to control flow */                                         \
        cross test_len, burst_type, test_size, atomic_type;                                                         \
        /* valid and failing requests in both read and write channels */                                            \
        cross axi_request_type, invalid_access, capability_token, expected_response;                                \
                                                                                                                    \
    endgroup                                                                                                        
/* verilog_format: off */
`define AXI5_TEST_INIT_COVERAGE_GROUP(INST) ``INST``_coverage_group = new;                                                                      
/* verilog_format: on */
`define AXI5_TEST_SAMPLE_COVERAGE_GROUP(INST) ``INST``_coverage_group.sample()

/* verilog_format: off */
`define AXI5_LITE_TEST_DECLARE_COVERAGE_GROUP(INST)                                                                 \
/* verilog_format: on */                                                                                            \
        covergroup ``INST``_coverage_group;                                                                         \
        /* omitting addresses due to large space and limited impact */                                              \
        /* we want to see a token of each KIND, however */                                                          \
        araddr: coverpoint INST.araddr;                                                                             \
        arprot: coverpoint INST.arprot;                                                                             \
                                                                                                                    \
        awaddr: coverpoint INST.awaddr;                                                                             \
        awprot: coverpoint INST.awprot;                                                                             \
                                                                                                                    \
        wdata: coverpoint INST.wdata;                                                                               \
        wstrb: coverpoint INST.wstrb;                                                                               \
                                                                                                                    \
        bresp: coverpoint INST.bresp;                                                                               \
                                                                                                                    \
        rdata: coverpoint INST.rdata;                                                                               \
        rresp: coverpoint INST.rresp;                                                                               \
    endgroup                                                                                                        \
    ``INST``_coverage_group ``INST``_cg = new;                                                                      

`define AXI5_LITE_TEST_SAMPLE_COVERAGE_GROUP(INST) ``INST``_cg.sample()

`else
`define AXI5_TEST_DECLARE_COVERAGE_GROUP(INST) /* Nothing */
`define AXI5_TEST_INIT_COVERAGE_GROUP(INST) /* Nothing */
`define AXI5_TEST_SAMPLE_COVERAGE_GROUP(INST) /* Nothing */

`define AXI5_LITE_TEST_DECLARE_COVERAGE_GROUP(INST) /* Nothing */
`define AXI5_LITE_TEST_SAMPLE_COVERAGE_GROUP(INST) /* Nothing */
`endif
