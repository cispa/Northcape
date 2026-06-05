# this script creates IPs that are not part of the block design, e.g., ILAs used within modules in the block design
#################################################################
# CHECK IPs
##################################################################

set bCheckIPs 1
set bCheckIPsPassed 1
if { $bCheckIPs == 1 } {
  set list_check_ips { xilinx.com:ip:ila:6.2 }
  set list_ips_missing ""
  common::send_msg_id "IPS_TCL-1001" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

  foreach ip_vlnv $list_check_ips {
  set ip_obj [get_ipdefs -all $ip_vlnv]
  if { $ip_obj eq "" } {
    lappend list_ips_missing $ip_vlnv
    }
  }

  if { $list_ips_missing ne "" } {
    catch {common::send_msg_id "IPS_TCL-105" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
    set bCheckIPsPassed 0
  }
}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "IPS_TCL-102" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 1
}

##################################################################
# CREATE IP mmu_mask_shift_debug_ila
##################################################################

set mmu_mask_shift_debug_ila [create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name mmu_mask_shift_debug_ila]

# User Parameters
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {15} \
  CONFIG.C_PROBE0_WIDTH {14} \
  CONFIG.C_PROBE10_WIDTH {32} \
  CONFIG.C_PROBE12_WIDTH {64} \
  CONFIG.C_PROBE13_WIDTH {64} \
  CONFIG.C_PROBE1_WIDTH {64} \
  CONFIG.C_PROBE2_WIDTH {64} \
  CONFIG.C_PROBE3_WIDTH {64} \
  CONFIG.C_PROBE4_WIDTH {8} \
  CONFIG.C_PROBE5_WIDTH {32} \
  CONFIG.C_PROBE6_WIDTH {64} \
  CONFIG.C_PROBE7_WIDTH {64} \
  CONFIG.C_PROBE8_WIDTH {64} \
  CONFIG.C_PROBE9_WIDTH {64} \
] [get_ips mmu_mask_shift_debug_ila]

# Runtime Parameters
set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {0}
} $mmu_mask_shift_debug_ila


set northcape_cva6_ila [create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name northcape_cva6_ila]

# User Parameters
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {64} \
  CONFIG.C_PROBE0_WIDTH {64} \
  CONFIG.C_PROBE2_WIDTH {3}  \
  CONFIG.C_PROBE3_WIDTH {64} \
  CONFIG.C_PROBE6_WIDTH {32} \
  CONFIG.C_PROBE7_WIDTH {32} \
  CONFIG.C_PROBE8_WIDTH {64} \
  CONFIG.C_PROBE10_WIDTH {3} \
  CONFIG.C_PROBE14_WIDTH {64} \
  CONFIG.C_PROBE17_WIDTH {12} \
  CONFIG.C_PROBE18_WIDTH {52} \
  CONFIG.C_PROBE19_WIDTH {52} \
  CONFIG.C_PROBE19_WIDTH {64} \
  CONFIG.C_PROBE22_WIDTH {64} \
  CONFIG.C_PROBE24_WIDTH {32} \
  CONFIG.C_PROBE25_WIDTH {32} \
  CONFIG.C_PROBE26_WIDTH {32} \
  CONFIG.C_PROBE28_WIDTH {32} \
  CONFIG.C_PROBE30_WIDTH {32} \
  CONFIG.C_PROBE32_WIDTH {64} \
  CONFIG.C_PROBE23_WIDTH {5} \
  CONFIG.C_PROBE35_WIDTH {64} \
  CONFIG.C_PROBE38_WIDTH {32} \
  CONFIG.C_PROBE40_WIDTH {12} \
  CONFIG.C_PROBE41_WIDTH {12} \
  CONFIG.C_PROBE42_WIDTH {52} \
  CONFIG.C_PROBE43_WIDTH {52} \
  CONFIG.C_PROBE48_WIDTH {4} \
  CONFIG.C_PROBE51_WIDTH {3} \
  CONFIG.C_PROBE52_WIDTH {64} \
  CONFIG.C_PROBE53_WIDTH {64} \
  CONFIG.C_PROBE56_WIDTH {32} \
  CONFIG.C_PROBE57_WIDTH {32} \
  CONFIG.C_PROBE58_WIDTH {3} \
  CONFIG.C_PROBE59_WIDTH {32} \
  CONFIG.C_PROBE60_WIDTH {32} \
] [get_ips northcape_cva6_ila]

# Runtime Parameters
set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {0}
} $northcape_cva6_ila


create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name cva6_icache_ila
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {24} \
  CONFIG.C_PROBE0_WIDTH {64} \
  CONFIG.C_PROBE10_WIDTH {32} \
  CONFIG.C_PROBE11_WIDTH {8} \
  CONFIG.C_PROBE3_WIDTH {64} \
  CONFIG.C_PROBE6_WIDTH {34} \
  CONFIG.C_PROBE8_WIDTH {4} \
  CONFIG.C_PROBE9_WIDTH {34} \
  CONFIG.C_PROBE13_WIDTH {32} \
  CONFIG.C_PROBE14_WIDTH {64} \
  CONFIG.C_PROBE15_WIDTH {64} \
  CONFIG.C_PROBE16_WIDTH {32} \
  CONFIG.C_PROBE17_WIDTH {64} \
  CONFIG.C_PROBE18_WIDTH {64} \
  CONFIG.C_PROBE19_WIDTH {64} \
] [get_ips cva6_icache_ila]

set northcape_capability_cache_ila [create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name northcape_capability_cache_ila]
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {16} \
  CONFIG.C_PROBE1_WIDTH {38} \
  CONFIG.C_PROBE2_WIDTH {16} \
  CONFIG.C_PROBE4_WIDTH {38} \
  CONFIG.C_PROBE5_WIDTH {16} \
  CONFIG.C_PROBE13_WIDTH {256} \
  CONFIG.C_PROBE15_WIDTH {256} \
] [get_ips northcape_capability_cache_ila]

set northcape_cva6_commit_ila [create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name northcape_cva6_commit_ila]
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {16} \
  CONFIG.C_PROBE0_WIDTH {2} \
  CONFIG.C_PROBE10_WIDTH {64} \
  CONFIG.C_PROBE11_WIDTH {64} \
  CONFIG.C_PROBE13_WIDTH {64} \
  CONFIG.C_PROBE15_WIDTH {2} \
  CONFIG.C_PROBE1_WIDTH {2} \
] [get_ips northcape_cva6_commit_ila]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name cva6_mmu_cache_ila
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {10} \
  CONFIG.C_PROBE0_WIDTH {38} \
  CONFIG.C_PROBE1_WIDTH {8} \
  CONFIG.C_PROBE2_WIDTH {3} \
  CONFIG.C_PROBE7_WIDTH {8} \
  CONFIG.C_PROBE8_WIDTH {3} \
] [get_ips cva6_mmu_cache_ila]

set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {0}
} $northcape_capability_cache_ila


set northcape_store_buffer_ila [create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name store_buffer_ila]
set_property -dict [list \
  CONFIG.C_ADV_TRIGGER {true} \
  CONFIG.C_EN_STRG_QUAL {1} \
  CONFIG.C_NUM_OF_PROBES {8} \
  CONFIG.C_PROBE0_WIDTH {38} \
  CONFIG.C_PROBE6_WIDTH {38} \
] [get_ips store_buffer_ila]

set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {0}
} $northcape_store_buffer_ila
