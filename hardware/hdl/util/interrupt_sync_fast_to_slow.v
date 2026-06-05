`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/29/2025 09:12:46 AM
// Design Name: 
// Module Name: interrupt_sync_fast_to_slow
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module interrupt_sync_fast_to_slow
(
    input clk_fast_i,
    input rst_fast_ni,
    input clk_slow_i,
    input rst_slow_ni,
    input irq_fast_i,
    output irq_slow_o
);
    
    reg irq_q1, irq_q2, irq_q3, irq_q4;
    reg irq_inhibit_q1,irq_inhibit_q2, irq_inhibit_q3; 
    wire irq_d1, irq_d2, irq_d3, irq_d4, irq_handshake_d;
    wire irq_inhibit_d1,irq_inhibit_d2, irq_inhibit_d3;
    
    // fast side: keep interrupt req stable long enough for slow side to read and handshake
    always @(posedge(clk_fast_i), negedge(rst_fast_ni))
    begin
        if(!rst_fast_ni)
        begin
            irq_q1 <= 1'b0;
        end
        else
        begin
            irq_q1 <= irq_d1;
        end
    end
    
    // irq_handshake_q is in the slower clock domain
    assign irq_d1 = irq_fast_i || (irq_q1 && irq_handshake_d == 1'b0);
    
    // slow side: 2FF-synchronize the interrupt, make sure to only hold it for 1 cycle 
    always @(posedge(clk_slow_i), negedge(rst_slow_ni))
    begin
        if(!rst_slow_ni)
        begin
            irq_q2 <= 1'b0;
            irq_q3 <= 1'b0;
            irq_q4 <= 1'b0;
            irq_inhibit_q1 <= 1'b0;
            irq_inhibit_q2 <= 1'b0;
            irq_inhibit_q3 <= 1'b0;
        end
        else
        begin
            irq_q2 <= irq_d2;
            irq_q3 <= irq_d3;
            irq_q4 <= irq_d4;
            irq_inhibit_q1 <= irq_inhibit_d1;
            irq_inhibit_q2 <= irq_inhibit_d2;
            irq_inhibit_q3 <= irq_inhibit_d3;
        end
    end
    
    // 2FF synchronizer - 
    assign irq_d2 = irq_q1;
    assign irq_d3 = irq_q2;
    assign irq_d4 = irq_q3 && !(irq_inhibit_q1 || irq_inhibit_q2 || irq_inhibit_q3);
    assign irq_handshake_d = irq_q4;
    assign irq_inhibit_d1 = irq_d4;
    assign irq_inhibit_d2 = irq_inhibit_q1;
    assign irq_inhibit_d3 = irq_inhibit_q2;
    
    assign irq_slow_o = irq_q4;
    
    
endmodule
