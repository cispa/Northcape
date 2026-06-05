puts "Opening project"
open_project project/RVSoC.xpr
puts "Resetting last run"
reset_run impl_1
puts "Generating output products"
set script_file [info script]
set script_dir [file dirname [file normalize "$script_file"]]
set bd [get_files  $script_dir/project/RVSoC.srcs/sources_1/bd/SoC/SoC.bd]
generate_target all $bd 
create_ip_run $bd
set runs [get_runs *synth*]
set strategy "Vivado Synthesis Defaults"
puts "Setting synthesis strategy $strategy for runs $runs"
set_property strategy $strategy $runs
puts "Make sure there are no implementation reports"
set_property report_strategy {No Reports} [get_runs impl_1]
puts "Launching runs"
launch_runs impl_1 -jobs 8
puts "Waiting for runs to complete"
wait_on_runs impl_1
puts "Generating bitstream"
launch_runs impl_1 -to_step write_bitstream
puts "Waiting for runs to complete"
wait_on_runs impl_1
