transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/spi_master.v}
vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/reset_sync.v}
vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/i2c_slave.v}
vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/fifo_sync.v}
vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/de10lite_top.v}
vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL {D:/DOWNLOADS/FPGA_Project/RTL/bridge_fsm.v}

vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL/../TESTBENCH {D:/DOWNLOADS/FPGA_Project/RTL/../TESTBENCH/tb_simple.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L fiftyfivenm_ver -L rtl_work -L work -voptargs="+acc"  tb_simple

add wave *
view structure
view signals
run -all
