# Data word size
word_size = 256
# Number of words in the memory
num_words = 16

num_rw_ports=2

# Technology to use in $OPENRAM_TECH
tech_name = "sky130"
# Process corners to characterize
process_corners = [ "TT", "FF", "SS" ]
# Voltage corners to characterize
supply_voltages = [ 1.6, 1.8, 1.95 ]
# Temperature corners to characterize
temperatures = [ 0, 25, 40, 100]

# Output directory for the results
output_path = "temp"
# Output file base name
output_name = "sram_northcape_256x16"

# Disable analytical models for full characterization (WARNING: slow!)
# analytical_delay = False

# To force this to use magic and netgen for DRC/LVS/PEX
# Could be calibre for FreePDK45
drc_name = "magic"
lvs_name = "netgen"
pex_name = "magic"
