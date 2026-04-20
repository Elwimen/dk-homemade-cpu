set root /home/dmj/code/fpga/dkcpu

create_project dkcpu $root/vivado -part xc7a100tcsg324-2 -force

add_files [file normalize $root/top_arty.v]
add_files [file normalize $root/top.v]
add_files [file normalize $root/cpu.v]
add_files [file normalize $root/uart_rx.v]
add_files [file normalize $root/uart_tx.v]
add_files -fileset constrs_1 [file normalize $root/constrs/arty_a7_100.xdc]

set_property top top_arty [current_fileset]
update_compile_order -fileset sources_1

set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED           false [get_runs impl_1]
set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED            false [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]

set_property AUTO_INCREMENTAL_CHECKPOINT 1 [get_runs impl_1]

close_project
puts "Project initialised. Run build.tcl to compile."
