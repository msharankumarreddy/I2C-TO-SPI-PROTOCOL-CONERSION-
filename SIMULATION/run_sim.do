# =============================================================================
# SIMULATION/run_sim.do
# ModelSim / Questa macro to compile and run the testbench. Run from within
# the SIMULATION/ directory:
#     vsim -do run_sim.do
# or, for a batch (no GUI) run:
#     vsim -c -do run_sim.do
#
# This is the ModelSim/Questa equivalent of the iverilog/vvp commands used
# elsewhere in this project -- use whichever simulator you have available,
# both compile the same RTL + testbench files.
# =============================================================================

# fresh work library each run
if [file exists work] { vdel -lib work -all }
vlib work
vmap work work

# compile RTL (synthesizable) first, then the testbench models
vlog -sv +incdir+../RTL \
    ../RTL/i2c_slave.v \
    ../RTL/spi_master.v \
    ../RTL/bridge_fsm.v \
    ../RTL/fifo_sync.v \
    ../RTL/reset_sync.v

vlog -sv +incdir+../TESTBENCH \
    ../TESTBENCH/i2c_master_bfm.v \
    ../TESTBENCH/spi_slave_model.v \
    ../TESTBENCH/tb_i2c_spi_bridge.v

# elaborate and run
vsim -voptargs=+acc work.tb_i2c_spi_bridge

# log everything to the wave window if running with GUI
add wave -radix hex sim:/tb_i2c_spi_bridge/*

run -all

# in batch mode (vsim -c), uncomment to auto-exit after the run:
# quit -f
