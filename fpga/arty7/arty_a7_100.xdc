## Flash / config
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4              [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_VOLTAGE 3.3             [current_design]
set_property CFGBVS VCCO                    [current_design]

## Clock 100 MHz
set_property -dict {PACKAGE_PIN E3  IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Reset — BTN0, active-high
set_property -dict {PACKAGE_PIN D9  IOSTANDARD LVCMOS33} [get_ports rst_btn]

## UART (USB-UART bridge FT2232)
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports uart_rx]

## LEDs (active-high)
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports led_cpu]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports led_tx]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports led_rx]
