transcript on
if {[file exists gate_work]} {
	vdel -lib gate_work -all
}
vlib gate_work
vmap work gate_work

vlog  -work work +incdir+. {de10lite_top.vo}

vlog  -work work +incdir+D:/DOWNLOADS/FPGA_Project/RTL/../TESTBENCH {D:/DOWNLOADS/FPGA_Project/RTL/../TESTBENCH/tb_simple.v}

vsim -t 1ps -L altera_ver -L altera_lnsim_ver -L fiftyfivenm_ver -L gate_work -L work -voptargs="+acc"  tb_simple

add wave *
view structure
view signals
run -all
