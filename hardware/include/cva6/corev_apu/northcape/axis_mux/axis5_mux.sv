package axis5_mux;
    typedef enum logic { ARBITRATION_STATIC, ARBITRATION_RR } axis5_mux_arbitration_type_t;
endpackage

/**
  * Simple n:1 AXI5 Stream multiplexer w/ static priority defined by port order or round-robin arbitration.
  */

module Axis5Mux#(
    // 16 ports MAX
    parameter bit[3:0] NUMBER_IN_PORTS = -1,
    parameter axis5_mux::axis5_mux_arbitration_type_t ARBITRATION_TYPE=axis5_mux::ARBITRATION_STATIC
)(
    input logic clk_i,
    input logic rst_ni,
    
    Axis5.RECEIVER in_ports[NUMBER_IN_PORTS],
    Axis5.TRANSMITTER out_port
);
    typedef enum logic { IDLE, FORWARDING } axis_mux_state_t;
    `include "northcape_unread.vh"
    import axis5_mux::*;

    localparam MAX_PORTS=16;

    logic[3:0] arbitration_grant_q, arbitration_grant_d;
    logic have_grant_q, have_grant_d;

    logic[MAX_PORTS-1:0] arb_request, arb_request_shifted, arb_out_oh, arb_request_tmp;
    logic[2*MAX_PORTS-1:0] arb_out_tmp;

    axis_mux_state_t state_q, state_d;

    logic [NUMBER_IN_PORTS-1:0] clocks, resets;

    logic [$clog2(NUMBER_IN_PORTS)-1:0] rr_count_d, rr_count_q;

    function logic[$clog2(MAX_PORTS)-1:0] onehot_to_binary(input logic[MAX_PORTS-1:0] in_val);
        unique case(in_val)
            1<<0:
                return 16'h0;
            1<<1:
                return 16'h1;
            1<<2:
                return 16'h2;
            1<<3:
                return 16'h3;
            1<<4:
                return 16'h4;
            1<<5:
                return 16'h5;
            1<<6:
                return 16'h6;
            1<<7:
                return 16'h7;
            1<<8:
                return 16'h8;
            1<<9:
                return 16'h9;
            1<<10:
                return 16'h10;
            1<<11:
                return 16'h11;
            1<<12:
                return 16'h12;
            1<<13:
                return 16'h13;
            1<<14:
                return 16'h14;
            1<<15:
                return 16'h15;
            default:
                return 16'h0;
        endcase
    endfunction

    always_ff @( posedge(clk_i), negedge(rst_ni) ) begin : stateFF
        if(rst_ni == 0)
        begin
            state_q <= IDLE;
            if(ARBITRATION_TYPE == ARBITRATION_RR)
            begin
                rr_count_q <= '0;
            end
        end
        else
        begin
            state_q <= state_d;
            if(ARBITRATION_TYPE == ARBITRATION_RR)
            begin
                rr_count_q <= rr_count_d;
            end
        end
    end

    always_ff @( posedge(clk_i), negedge(rst_ni) ) begin : arbitrationFF
        if(rst_ni == 0)
        begin
            arbitration_grant_q <= 0;
            have_grant_q <= 0;
        end
        else
        begin
            unique case(state_q)
                IDLE:
                begin
                    arbitration_grant_q <= arbitration_grant_d;
                    have_grant_q <= have_grant_d;
                end
                default:
                begin
                    // maintain old values
                end
            endcase
        end
    end

    genvar used_port, unused_port;

    generate
        for(used_port = 0; used_port < NUMBER_IN_PORTS; used_port++)
        begin
            assign arb_request[MAX_PORTS-used_port-1] = in_ports[used_port].tvalid;
            assign clocks[used_port] = in_ports[used_port].clk_i;
            assign resets[used_port] = in_ports[used_port].rst_ni;
        end
        for(unused_port = NUMBER_IN_PORTS; unused_port < MAX_PORTS; unused_port++)
        begin
            assign arb_request[MAX_PORTS-unused_port-1] = 0;
        end

    endgenerate

    always_comb begin: arbRequestShiftLogic
        // simple barrel-shift
        arb_request_tmp = {2{arb_request}} >> rr_count_q;
        unique case(ARBITRATION_TYPE)
            ARBITRATION_RR:
            begin
                arb_request_shifted =  arb_request_tmp[MAX_PORTS-1:0];
            end
            default:
            begin
                arb_request_shifted = arb_request;
            end
        endcase
    end: arbRequestShiftLogic

    always_comb begin: arbRRCountLogic
        rr_count_d = rr_count_q;
        // in case we are transitioning away from IDLE (e.g., no tready), need to maintain mask stable
        if(ARBITRATION_TYPE == ARBITRATION_RR && state_d == IDLE)
        begin
            rr_count_d = rr_count_q + (|arb_request);
        end
    end: arbRRCountLogic

    always_comb begin : arbiterLogic
        // in case we are holding
        arbitration_grant_d = arbitration_grant_q;
        have_grant_d = have_grant_q;
        arb_out_oh = '0;
        arb_out_tmp = '0;
        if(state_q == IDLE)
        begin

            have_grant_d = 1;
            priority casex(arb_request_shifted)
                16'b1000000000000000:
                begin
                    arbitration_grant_d = 0;
                end
                16'b?100000000000000: arbitration_grant_d = 1;
                16'b??10000000000000: arbitration_grant_d = 2;
                16'b???1000000000000: arbitration_grant_d = 3;
                16'b????100000000000: arbitration_grant_d = 4;
                16'b?????10000000000: arbitration_grant_d = 5;
                16'b??????1000000000: arbitration_grant_d = 6;
                16'b???????100000000: arbitration_grant_d = 7;
                16'b????????10000000: arbitration_grant_d = 8;
                16'b?????????1000000: arbitration_grant_d = 9;
                16'b??????????100000: arbitration_grant_d = 10;
                16'b???????????10000: arbitration_grant_d = 11;
                16'b????????????1000: arbitration_grant_d = 12;
                16'b?????????????100: arbitration_grant_d = 13;
                16'b??????????????10: arbitration_grant_d = 14;
                16'b???????????????1: arbitration_grant_d = 15;
                default:
                begin
                    arbitration_grant_d = 0;
                    have_grant_d = 0;
                end
                
            endcase

            if(ARBITRATION_TYPE == ARBITRATION_RR)
            begin
                arb_out_oh = 1<<arbitration_grant_d;
                // have to shift in the same direction as the request here, as the priority mask inverses the bits
                arb_out_tmp = {2{arb_out_oh}} >> rr_count_q;
                arb_out_oh = arb_out_tmp[MAX_PORTS-1:0];
                arbitration_grant_d = onehot_to_binary(arb_out_oh);
            end

        end
        
        if(|arb_request)
        begin
            assert(arb_request[arbitration_grant_d]);
        end
    end: arbiterLogic

    `define MUX_ARBITRATION_CASE(PORT_NUM)                                                              \
        PORT_NUM:                                                                                       \
        begin                                                                                           \
            if(PORT_NUM < NUMBER_IN_PORTS)                                                              \
            begin                                                                                       \
                if(have_grant_d)                                                                        \
                begin                                                                                   \
                    out_port.tvalid = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tvalid;         \
                end                                                                                     \
                else                                                                                    \
                begin                                                                                   \
                    out_port.tvalid = 0;                                                                \
                end                                                                                     \
                /* tvalid 0 w/out grant - can forward garbage data */                                   \
                out_port.tdata   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tdata;             \
                out_port.tstrb   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tstrb;             \
                out_port.tkeep   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tkeep;             \
                out_port.tlast   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tlast;             \
                out_port.tid     = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tid;               \
                out_port.tdest   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tdest;             \
                out_port.tuser   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tuser;             \
                out_port.twakeup   = in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].twakeup;         \
                                                                                                        \
                in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tready = out_port.tready;             \
            end                                                                                         \
        end
    
    `define DEFAULT_TREADY_CASE(PORT_NUM)                                       \
        if(PORT_NUM < NUMBER_IN_PORTS)                                          \
        begin                                                                   \
            in_ports[PORT_NUM < NUMBER_IN_PORTS ? PORT_NUM:0].tready = 0;       \
        end

    
    always_comb begin: forwardLogic
        `DEFAULT_TREADY_CASE(0)
        `DEFAULT_TREADY_CASE(1)
        `DEFAULT_TREADY_CASE(2)
        `DEFAULT_TREADY_CASE(3)
        `DEFAULT_TREADY_CASE(4)
        `DEFAULT_TREADY_CASE(5)
        `DEFAULT_TREADY_CASE(6)
        `DEFAULT_TREADY_CASE(7)
        `DEFAULT_TREADY_CASE(8)
        `DEFAULT_TREADY_CASE(9)
        `DEFAULT_TREADY_CASE(10)
        `DEFAULT_TREADY_CASE(11)
        `DEFAULT_TREADY_CASE(12)
        `DEFAULT_TREADY_CASE(13)
        `DEFAULT_TREADY_CASE(14)
        `DEFAULT_TREADY_CASE(15)

        out_port.tvalid = 0;
        out_port.tdata = '0;
        out_port.tstrb = '0;
        out_port.tkeep = '0;
        out_port.tlast = 0;
        out_port.tid   = '0;
        out_port.tdest = '0;
        out_port.tuser = 0;
        
        /* easier than to figure out if we need to set it */
        /* and not used in Northcape */                        
        out_port.twakeup = 1;                                  

        unique case(arbitration_grant_d)
            `MUX_ARBITRATION_CASE(0)
            `MUX_ARBITRATION_CASE(1)
            `MUX_ARBITRATION_CASE(2)
            `MUX_ARBITRATION_CASE(3)
            `MUX_ARBITRATION_CASE(4)
            `MUX_ARBITRATION_CASE(5)
            `MUX_ARBITRATION_CASE(6)
            `MUX_ARBITRATION_CASE(7)
            `MUX_ARBITRATION_CASE(8)
            `MUX_ARBITRATION_CASE(9)
            `MUX_ARBITRATION_CASE(10)
            `MUX_ARBITRATION_CASE(11)
            `MUX_ARBITRATION_CASE(12)
            `MUX_ARBITRATION_CASE(13)
            `MUX_ARBITRATION_CASE(14)
            `MUX_ARBITRATION_CASE(15)
            default:
            begin
                // impossible
`ifndef ASIC
                $fatal(1);
`endif
            end  
        endcase
        
    end: forwardLogic

    always_comb begin: fsmLogic
        state_d = state_q;

        unique case(state_q)
            IDLE:
            begin
                /* no need to transition into FORWARDING and block if can forward in this cycle */
                if(arb_request != '0 && !(out_port.tready && out_port.tlast))
                begin
                    state_d = FORWARDING;
                end
            end
            FORWARDING:
            begin
                if(out_port.tvalid && out_port.tlast && out_port.tready)
                begin
                    state_d = IDLE;
                end
            end
            default: ;
        endcase
    end:fsmLogic

    `NORTHCAPE_UNREAD(clocks);
    `NORTHCAPE_UNREAD(resets);

    `NORTHCAPE_UNREAD(out_port.clk_i);
    `NORTHCAPE_UNREAD(out_port.rst_ni);
    
endmodule
