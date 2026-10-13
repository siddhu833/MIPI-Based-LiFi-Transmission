# package_ip.tcl
# Vivado script to package the pixel_unpack module as an IP block

# Create a temporary project for packaging
create_project -force tmp_ip_project ./tmp_ip_project -part xc7z020clg484-1

# Add the source Verilog file
add_files ./pixel_unpack.v
update_compile_order -fileset sources_1

# Package the project as an IP and import the files into the IP directory
ipx::package_project -root_dir ./ip_repo/pixel_unpack -import_files -vendor custom_lifi -library user -taxonomy /UserIP

# Customize IP properties
set_property name pixel_unpack [ipx::current_core]
set_property display_name "LiFi Pixel Unpacker" [ipx::current_core]
set_property description "Unpacks MIPI CSI-2 RAW8, RAW10, RAW12, and RAW24 camera data streams into pixels." [ipx::current_core]
set_property vendor_display_name "LiFi Project" [ipx::current_core]
set_property company_url "http://lifi-mipi.org" [ipx::current_core]

# Generate GUI files for custom configuration in IP Integrator
ipx::create_xgui_files [ipx::current_core]

# Save and finalize the IP
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]

# Close the temporary project and delete its temporary files
close_project -delete
puts "================================================="
puts " IP Packaging completed successfully with imported files!"
puts " IP location: ./ip_repo/pixel_unpack"
puts "================================================="
