set_property -dict {PACKAGE_PIN E3  IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

# ADXL362 accelerometer
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports ACL_MISO]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports ACL_MOSI]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports ACL_SCLK]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports ACL_CSN]

# USB-UART (FPGA TX -> PC)
set_property -dict {PACKAGE_PIN D4  IOSTANDARD LVCMOS33} [get_ports UART_RXD_OUT]

# LEDs
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports LED16_G]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports LED16_R]

# ADXL362 data-ready interrupt
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports ACL_INT1]
