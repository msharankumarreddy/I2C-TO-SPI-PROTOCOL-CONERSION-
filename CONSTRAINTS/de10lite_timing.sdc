# =============================================================================
# de10lite_timing.sdc
# Timing constraints for TimeQuest / Timing Analyzer targeting the DE10-Lite
# =============================================================================

# Primary Clock Definition: 50 MHz onboard oscillator (20.000 ns period)
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]

# Automatically derive clock uncertainties (jitter/PLL phase noise)
derive_clock_uncertainty

# =============================================================================
# Asynchronous Inputs: Set false paths to exclude from setup/hold analysis
# =============================================================================

# Pushbutton Reset (KEY0) - Handled internally via 2-flop synchronizer
set_false_path -from [get_ports KEY0]

# I2C Interface Pins (GPIO_0 = SDA, GPIO_1 = SCL) - Handled via 3-stage synchronizer
set_false_path -from [get_ports GPIO_0]
set_false_path -from [get_ports GPIO_1]

# SPI MISO Pin (GPIO_4) - Driven asynchronously by external SPI slave
set_false_path -from [get_ports GPIO_4]