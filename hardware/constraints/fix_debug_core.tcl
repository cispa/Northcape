# forces the debug hub to use a usable clock
puts "Fixing debug core"

# disconnect_net -net clk -pinlist [get_pins -of_objects [get_cells dbg_hub]]
# connect_net -hierarchical -net SoC_i/clk_wiz_0_clk_out1 -objects dbg_hub/clk

# connect_debug_port dbg_hub/clk [get_nets SoC_i/clk_wiz_0_clk_out1]
# we use the 50 MHz CPU clock as a free-running clock
# set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
