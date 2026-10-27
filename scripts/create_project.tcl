# Recreate the Vivado project from the sources in this repository.
#
#   vivado -mode batch -source scripts/create_project.tcl
#
# The project is created in build/rfsoc4x2_ibert (ignored by git). Tested with Vivado 2023.2.

set repo_dir  [file normalize [file join [file dirname [info script]] ..]]
set proj_name rfsoc4x2_ibert
set proj_dir  [file join $repo_dir build $proj_name]
set part      xczu48dr-ffvg1517-2-e

create_project $proj_name $proj_dir -part $part -force

# Board files are optional; only the part is needed to build.
set board [lindex [get_board_parts -quiet -latest_file_version {realdigital.org:rfsoc4x2:*}] 0]
if {$board ne ""} {
    set_property board_part $board [current_project]
}
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---------------------------------------------------------------- sources
add_files -norecurse -fileset sources_1 [glob [file join $repo_dir rtl *.v]]

# ---------------------------------------------------------------- IP
# gt_qsfp (the four transceivers, 25.78125 Gb/s from the board's 156.25 MHz reference, fractional-N), isi_qsfp (In-System
# IBERT), vio_ibert
foreach ip_tcl [lsort [glob [file join $repo_dir ip *.tcl]]] {
    source $ip_tcl
}
generate_target all [get_ips]

set_property top fpga [get_filesets sources_1]

# ---------------------------------------------------------------- constraints
add_files -norecurse -fileset constrs_1 [file join $repo_dir constraints fpga.xdc]
set_property target_constrs_file [file join $repo_dir constraints fpga.xdc] [get_filesets constrs_1]

# ---------------------------------------------------------------- runs

update_compile_order -fileset sources_1
puts "Project created: [file join $proj_dir $proj_name.xpr]"
