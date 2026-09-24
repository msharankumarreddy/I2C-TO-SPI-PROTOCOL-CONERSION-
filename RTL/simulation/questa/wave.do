# Clear existing cluttered waves
delete wave *

# 1. System Signals
add wave -noupdate -divider "SYSTEM"
add wave -noupdate /tb_simple/clk
add wave -noupdate /tb_simple/rst_n

# 2. I2C Bus (Input to Bridge)
add wave -noupdate -divider "I2C BUS"
add wave -noupdate /tb_simple/scl
add wave -noupdate /tb_simple/sda

# 3. Internal Bridge Data (What goes in/out of the registers)
add wave -noupdate -divider "BRIDGE DATA"
add wave -noupdate -radix hex /tb_simple/reg_ptr
add wave -noupdate -radix hex /tb_simple/wr_data
add wave -noupdate -radix hex /tb_simple/rd_data

# 4. SPI Bus (Output from Bridge)
add wave -noupdate -divider "SPI BUS"
add wave -noupdate /tb_simple/cs_n
add wave -noupdate /tb_simple/sck
add wave -noupdate /tb_simple/mosi
add wave -noupdate /tb_simple/miso

# 5. Verification Status (Pass/Fail Checks)
add wave -noupdate -divider "VERIFICATION"
add wave -noupdate /tb_simple/status_done
add wave -noupdate /tb_simple/status_err
add wave -noupdate -radix unsigned /tb_simple/pass_count
add wave -noupdate -radix unsigned /tb_simple/fail_count