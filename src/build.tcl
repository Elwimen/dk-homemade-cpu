open_project /home/dmj/code/fpga/dkcpu/vivado/dkcpu.xpr

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream: /home/dmj/code/fpga/dkcpu/vivado/dkcpu.runs/impl_1/top_arty.bit"
close_project
