hsi open_hw_design vitis_tmp/SoC_wrapper.xsa

hsi set_repo_path "./device-tree-xlnx"

set procs [hsi get_cells -hier -filter {IP_TYPE==PROCESSOR}]

puts "List of processors found in XSA is $procs"

hsi create_sw_design device-tree -os device_tree -proc $procs

hsi generate_target -dir vitis_tmp/device_tree

hsi close_hw_design [hsi current_hw_design]

exit