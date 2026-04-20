set part xc7a100tcsg324-2

read_verilog ../../src/top_arty.v
read_verilog ../../src/cpu.v
read_verilog ../../src/uart_rx.v
read_verilog ../../src/uart_tx.v
read_xdc arty_a7_100.xdc

synth_design -top top_arty -part $part
opt_design
place_design
route_design
write_bitstream -force dkcpu.bit

puts "Build complete: dkcpu.bit"
