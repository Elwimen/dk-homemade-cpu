set here    [file dirname [file normalize [info script]]]
set bitfile [file join $here dkcpu.bit]
set mcsfile [file join $here dkcpu.mcs]

write_cfgmem -format mcs -size 128 -interface SPIx4 \
             -loadbit "up 0x0 $bitfile" -file $mcsfile -force

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $device
refresh_hw_device $device

create_hw_cfgmem -hw_device $device \
    [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]

set cfgmem [get_property PROGRAM.HW_CFGMEM $device]
set_property PROGRAM.ADDRESS_RANGE          {use_file}  $cfgmem
set_property PROGRAM.FILES                  [list $mcsfile] $cfgmem
set_property PROGRAM.PRM_FILE               {}          $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BPI_RS_PINS            {none}      $cfgmem
set_property PROGRAM.BLANK_CHECK            0           $cfgmem
set_property PROGRAM.ERASE                  1           $cfgmem
set_property PROGRAM.CFG_PROGRAM            1           $cfgmem
set_property PROGRAM.VERIFY                 0           $cfgmem
set_property PROGRAM.CHECKSUM               0           $cfgmem

create_hw_bitstream -hw_device $device \
    [get_property PROGRAM.HW_CFGMEM_BITFILE $device]
program_hw_devices $device
refresh_hw_device $device

program_hw_cfgmem $cfgmem

puts "Done. Power cycle to boot from flash."
close_hw_target
disconnect_hw_server
