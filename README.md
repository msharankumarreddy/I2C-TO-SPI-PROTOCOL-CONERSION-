# I2C-to-SPI Bridge (DE10-Lite / Intel MAX 10)

An I2C-slave-to-SPI-master protocol bridge, targeting the Terasic DE10-Lite
board (Intel MAX 10, `10M50DAF484C7G`). The bridge presents itself as an I2C
slave (address `0x50`) with a small register map, and translates burst reads
and writes into SPI transactions on a separate physical bus.

## Folder structure

```
FPGA_Project/
├── RTL/            synthesizable Verilog -- goes into the FPGA
├── TESTBENCH/       simulation-only Verilog -- NEVER added to the Quartus project
├── CONSTRAINTS/      pin table (.qsf) and timing constraints (.sdc)
├── SIMULATION/       ModelSim/Questa run script (.do)
├── PROJECT/           Quartus project files (.qpf, .qsf)
└── README.md
```

**Note on `.xdc` / `.xpr`:** this project targets an Intel MAX 10 FPGA, not a
Xilinx device, so there is no Vivado project (`.xpr`) or Xilinx constraints
file (`.xdc`) -- those are intentionally omitted rather than faked. See the
"Quartus vs Vivado" note below if you're unsure why.

## Register map (I2C side, address 0x50)

| REG_PTR | Register | Access | Meaning |
|---|---|---|---|
| `0x00` | CMD    | R/W | bit0=RW (0=SPI write,1=SPI read), bit7=GO (strobe) |
| `0x01` | COUNT  | R/W | number of bytes to transfer this burst |
| `0x02` | DATA   | R/W | FIFO port: writes push TX FIFO, reads pop RX FIFO |
| `0x03` | STATUS | R   | bit0=BUSY bit1=DONE bit2=ERR bit3=TX_EMPTY bit4=TX_FULL bit5=RX_EMPTY bit6=RX_FULL |

First byte after the I2C address selects `reg_ptr`; it persists across a
repeated START, which is how a write-then-read-back sequence works without
resending the pointer.

## Building the RTL description

`de10lite_top.v` instantiates:
- `i2c_slave.v` -- I2C slave interface, oversampled by the 50 MHz system clock
- `bridge_fsm.v` -- register file (CMD/COUNT/DATA/STATUS), TX/RX FIFOs, control FSM
- `spi_master.v` -- SPI master, Mode 0, single CS, separate TX/RX shift registers
- `reset_sync.v` -- async-assert/sync-deassert reset synchronizer

## How to simulate

**Option A -- Icarus Verilog** (what this project was actually verified with):
```
cd TESTBENCH
iverilog -g2005-sv -o bridge_tb.vvp \
  ../RTL/i2c_slave.v ../RTL/spi_master.v ../RTL/bridge_fsm.v ../RTL/fifo_sync.v ../RTL/reset_sync.v \
  i2c_master_bfm.v spi_slave_model.v tb_i2c_spi_bridge.v
vvp bridge_tb.vvp
```

**Option B -- ModelSim/Questa:**
```
cd SIMULATION
vsim -do run_sim.do
```

## Current verification status (important -- read before using on hardware)

As of the last simulation run: **12 of 15 self-checks pass.**

| Test | Status | Covers |
|---|---|---|
| TEST 1: write burst | **PASS** | I2C -> TX FIFO -> SPI write path, full chain |
| TEST 2: read burst | **3 checks FAIL** | Multi-byte read-back has an open, unresolved bug -- byte 0 is off by one bit, bytes 1-2 return `0xFF` instead of the correct value. Root cause not yet found. |
| TEST 3: underflow error | **PASS** | Error detection and two-step recovery (GO clears ERR, second GO relaunches) |

**Do not trust the multi-byte read-back path on real hardware until TEST 2
passes in simulation.** The write-burst and error-handling paths are
verified correct; the read-back path is not.

## Programming the board (Quartus)

1. Open `PROJECT/i2c_spi_bridge.qpf` in Quartus Prime **Lite** (MAX 10 requires Lite edition device support).
2. `PROJECT/i2c_spi_bridge.qsf` already lists all RTL files, the SDC, and the full pin map -- no manual file-adding needed.
3. Processing > Start Compilation.
4. Tools > Programmer, load the resulting `.sof`, Start.
5. **Before powering on**: add an external ~4.7k&#8486; pull-up resistor from GPIO_0 (SDA) to 3.3V -- the MAX 10's I/O pins are push-pull, not open-drain, so the bus needs this externally.

`LEDR[0]` = busy, `LEDR[1]` = done, `LEDR[2]` = err.

## Quartus vs Vivado

This targets an **Intel/Altera MAX 10** device. Vivado only supports Xilinx
silicon and cannot target this chip at all -- there is no "switch to Vivado"
option here. Quartus Prime Lite is the correct and only applicable toolchain
for this board.

## Known simplifications / open items

- `spi_master.v` samples MISO without an input synchronizer (see the comment
  in `de10lite_timing.sdc`) -- works in practice due to slow SCK, but isn't
  fully rigorous.
- `reg_ptr` does not auto-increment across multiple bytes in one transaction
  -- the host must resend `REG_PTR` if switching registers mid-transaction
  (it does *not* need to resend it for consecutive same-register bytes,
  which is how the FIFO burst mode works).
- Multi-byte SPI read-back has a known, unresolved bug (see verification
  status above).
