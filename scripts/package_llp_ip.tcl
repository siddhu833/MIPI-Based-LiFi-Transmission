# package_llp_ip.tcl
# Vivado script to package the csi2_rx_llp_sf IP and the axis_asyncc_fifo IP

# =========================================================================
# 1. Package the CSI-2 LLP Receiver IP (csi2_rx_llp_sf)
# =========================================================================
create_project -force tmp_llp_project ./tmp_llp_project -part xc7z020clg484-1

# Add modules for LLP block (includes internal sync_fifo)
add_files ./csi2_rx_ecc_crc.v ./csi2_ecc_rx.v ./crc.v ./sync_fifo.v
update_compile_order -fileset sources_1

# Package the project as an IP
ipx::package_project -root_dir ./ip_repo/csi2_rx_llp_sf -import_files -vendor xilinx.com -library user -taxonomy /UserIP

# Customize properties
set_property name csi2_rx_llp_sf [ipx::current_core]
set_property display_name "LiFi CSI-2 LLP SF" [ipx::current_core]
set_property description "MIPI CSI-2 Low Level Protocol (LLP) Receiver with ECC, CRC and Store-and-Forward (SF) AXI-Stream output." [ipx::current_core]
set_property vendor_display_name "LiFi Project" [ipx::current_core]
set_property company_url "http://lifi-mipi.org" [ipx::current_core]

# Generate GUI files, save and close
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
close_project -delete

# =========================================================================
# 2. Package the standalone AXI-Stream Asynchronous FIFO IP (axis_asyncc_fifo)
# =========================================================================
create_project -force tmp_fifo_project ./tmp_fifo_project -part xc7z020clg484-1

# Add modules for AXI-Stream Async FIFO block
add_files ./axis_asyncc_fifo.v ./asyncc_fifo.v ./2ff_sync.v ./D_flipflop.v ./w_ptr_handler.v ./rd_ptr_hdlr.v
update_compile_order -fileset sources_1

# Package the project as an IP
ipx::package_project -root_dir ./ip_repo/axis_asyncc_fifo -import_files -vendor xilinx.com -library user -taxonomy /UserIP

# Customize properties
set_property name axis_asyncc_fifo [ipx::current_core]
set_property display_name "LiFi AXI-Stream Async FIFO Bridge" [ipx::current_core]
set_property description "Stall-proof, 100% throughput AXI-Stream Clock Domain Crossing (CDC) bridge using a 9-bit Asynchronous FIFO." [ipx::current_core]
set_property vendor_display_name "LiFi Project" [ipx::current_core]
set_property company_url "http://lifi-mipi.org" [ipx::current_core]

# Generate GUI files, save and close
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
close_project -delete

puts "================================================="
puts " IP Packaging completed successfully for both blocks!"
puts " IP repo directories:"
puts "   - ./ip_repo/csi2_rx_llp_sf"
puts "   - ./ip_repo/axis_asyncc_fifo"
puts "================================================="
