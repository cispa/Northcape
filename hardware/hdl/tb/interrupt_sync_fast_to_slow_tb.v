`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/29/2025 09:36:14 AM
// Design Name: 
// Module Name: interrupt_sync_fast_to_slow_tb
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


module interrupt_sync_fast_to_slow_tb;


reg clk_fast, clk_slow;
reg reset_fast_n, reset_slow_n;

reg interrupt_fast;
wire interrupt_slow;

localparam NUMBER_ITS=10;
integer interrupts_seen = 0;

// clock generators
initial begin
    clk_fast = 0;
    forever
    begin
        #5 clk_fast = ~clk_fast;
    end
end

initial begin
    clk_slow = 0;
    forever
    begin
        #20 clk_slow = ~clk_slow;
    end
end

// reset generators
initial begin
    reset_fast_n = 0;
    #20 reset_fast_n = 1;
end

initial begin
    reset_slow_n = 0;
    #100 reset_slow_n = 1;
end

interrupt_sync_fast_to_slow i_dut(
    .clk_fast_i(clk_fast),
    .clk_slow_i(clk_slow),
    .rst_fast_ni(reset_fast_n),
    .rst_slow_ni(reset_slow_n),
    .irq_fast_i(interrupt_fast),
    .irq_slow_o(interrupt_slow)
);

// stimulus
initial begin
    interrupt_fast = 0;
    
    #200;
     
    repeat(NUMBER_ITS)
    begin
        @(posedge(clk_fast));
        interrupt_fast = 1'b1;
        @(posedge(clk_fast));
        interrupt_fast = 1'b0;
        
        repeat(10)
        begin
            @(posedge(clk_slow));
        end
    end
end

// checker
initial begin
    forever
    begin
        @(posedge(clk_slow));
        if(interrupt_slow == 1'b1)
        begin
            interrupts_seen = interrupts_seen + 1;
            $display("Saw interrupt %d - checking if it does go down after 1 cycle", interrupts_seen);
            repeat(5)
            begin
                @(posedge(clk_slow));
                if(interrupt_slow == 1'b1)
                begin
                    $error("Interrupt still high!");
                    $stop();
                end
            
            end
        end
        if(interrupts_seen == NUMBER_ITS)
        begin
            $display("Test success :-)");
            $finish(0);
        end
    end
end
endmodule
