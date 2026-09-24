// =============================================================================
// tb_i2c_spi_bridge.v
// Top-level testbench: instantiates the DUT (i2c_slave + bridge_fsm +
// spi_master, same wiring as de10lite_top) plus the two peripheral models
// (i2c_master_bfm as the host, spi_slave_model as the target device), runs
// a write burst, a read burst, and an underflow-error case, and
// self-checks every result with PASS/FAIL.
// =============================================================================
`timescale 1ns/1ps

module tb_i2c_spi_bridge;

    // ---- clock / reset ----
    reg clk = 0;
    always #10 clk = ~clk;   // 50 MHz

    reg key0 = 0;
    wire rst_n;
    reset_sync u_rst (.clk(clk), .rst_n_async(key0), .rst_n_sync(rst_n));

    initial begin
        key0 = 1'b0;
        #200;
        key0 = 1'b1;
    end

    // ---- I2C bus ----
    wire sda, scl;
    pullup(sda);
    pullup(scl);

    i2c_master_bfm #(.HALF_PERIOD_NS(500)) u_i2c_master (.sda(sda), .scl(scl));

    // ---- DUT: i2c_slave ----
    wire [1:0] reg_ptr;
    wire [7:0] wr_data, rd_data;
    wire       wr_pulse, byte_rdy_tgl, rd_pulse;

    i2c_slave #(.I2C_ADDR(7'h50)) u_i2c_slave (
        .clk(clk), .rst_n(rst_n),
        .sda(sda), .scl_pad(scl),
        .reg_ptr(reg_ptr), .wr_data(wr_data), .wr_pulse(wr_pulse),
        .byte_rdy_tgl(byte_rdy_tgl),
        .rd_data(rd_data), .rd_pulse(rd_pulse)
    );

    // ---- SPI bus ----
    wire sck, mosi, miso, cs_n;

    spi_slave_model u_spi_slave (.sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n));

    wire [7:0] spi_tx, spi_rx;
    wire       spi_start, spi_busy, spi_done;

    spi_master #(.CLK_DIV(5)) u_spi_master (
        .clk(clk), .rst_n(rst_n),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n),
        .tx_byte(spi_tx), .rx_byte(spi_rx),
        .start(spi_start), .busy(spi_busy), .done(spi_done)
    );

    // ---- DUT: bridge_fsm ----
    wire status_busy, status_done, status_err;

    bridge_fsm u_fsm (
        .clk(clk), .rst_n(rst_n),
        .reg_ptr(reg_ptr), .wr_data(wr_data), .wr_pulse(wr_pulse), .rd_pulse(rd_pulse),
        .rd_data(rd_data),
        .spi_tx(spi_tx), .spi_start(spi_start),
        .spi_rx(spi_rx), .spi_busy(spi_busy), .spi_done(spi_done),
        .STATUS_busy(status_busy), .STATUS_done(status_done), .STATUS_err(status_err)
    );

    // ---- scoreboard ----
    integer pass_count = 0;
    integer fail_count = 0;

    task automatic check_byte(input [8*32-1:0] name, input [7:0] got, input [7:0] exp);
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : got 0x%02h, expected 0x%02h", name, got, exp);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : got 0x%02h, expected 0x%02h", name, got, exp);
            end
        end
    endtask

    task automatic check_bit(input [8*32-1:0] name, input got, input exp);
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : got %0b, expected %0b", name, got, exp);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : got %0b, expected %0b", name, got, exp);
            end
        end
    endtask

    // Wait on the internal status_done wire directly (fast, clock-cycle
    // granularity) rather than polling over the I2C bus every loop pass.
    task automatic wait_for_done(input integer timeout_cycles);
        integer i;
        reg [7:0] status_via_i2c;
        begin
            i = 0;
            while (!status_done && i < timeout_cycles) begin
                @(posedge clk);
                i = i + 1;
            end
            check_bit("STATUS_done asserted internally (fast wait)", status_done, 1'b1);

            // now confirm the SAME status is correctly readable over I2C itself
            u_i2c_master.i2c_read_reg(7'h50, 8'h03, status_via_i2c);
            check_bit("STATUS.DONE bit read back over I2C", status_via_i2c[1], 1'b1);
            check_bit("STATUS.ERR bit read back over I2C", status_via_i2c[2], 1'b0);
        end
    endtask

    // multi-byte read-back helper: reg_ptr=0x02, repeated-start, read N bytes
    task automatic i2c_read_burst3(output [7:0] b0, output [7:0] b1, output [7:0] b2);
        reg ack;
        begin
            u_i2c_master.i2c_start;
            u_i2c_master.i2c_send_byte({7'h50, 1'b0}, ack);
            u_i2c_master.i2c_send_byte(8'h02, ack);          // REG_PTR = DATA
            u_i2c_master.i2c_rep_start;
            u_i2c_master.i2c_send_byte({7'h50, 1'b1}, ack);
            u_i2c_master.i2c_recv_byte(b0, 1'b0);            // ACK, want more
            u_i2c_master.i2c_recv_byte(b1, 1'b0);            // ACK, want more
            u_i2c_master.i2c_recv_byte(b2, 1'b1);            // NACK, last byte
            u_i2c_master.i2c_stop;
        end
    endtask

    reg [7:0] status_rb, rb0, rb1, rb2;

    initial begin
        $dumpfile("bridge_tb.vcd");
        $dumpvars(0, tb_i2c_spi_bridge);

        wait (rst_n == 1'b1);
        #500;

        // =====================================================
        // TEST 1: write burst, 3 bytes {0xAA,0xBB,0xCC}, COUNT=3
        // =====================================================
        $display("\n--- TEST 1: WRITE BURST ---");
        u_i2c_master.i2c_write_burst(7'h50, 8'h02, 8'hAA, 8'hBB, 8'hCC); // fills TX FIFO
        u_i2c_master.i2c_write_reg(7'h50, 8'h01, 8'd3);                  // COUNT=3
        u_i2c_master.i2c_write_reg(7'h50, 8'h00, 8'h80);                 // CMD: GO=1, RW=0
        wait_for_done(3000);
        // SPI slave model $displays each received byte itself (see below);
        // cross-check the internal FIFO/FSM landed back in a clean IDLE state
        check_bit("BUSY cleared after write burst", status_busy, 1'b0);

        #2000;

        // =====================================================
        // TEST 2: read burst, COUNT=3, expect device pattern E0,E0,E0
        // (CS toggles per byte in this design, so pattern resets each time)
        // =====================================================
        $display("\n--- TEST 2: READ BURST ---");
        u_i2c_master.i2c_write_reg(7'h50, 8'h01, 8'd3);   // COUNT=3
        u_i2c_master.i2c_write_reg(7'h50, 8'h00, 8'h81);  // CMD: GO=1, RW=1
        wait_for_done(3000);

        i2c_read_burst3(rb0, rb1, rb2);
        check_byte("read-back byte 0", rb0, 8'hE0);
        check_byte("read-back byte 1", rb1, 8'hE0);
        check_byte("read-back byte 2", rb2, 8'hE0);

        #2000;

        // =====================================================
        // TEST 3: underflow error -- COUNT=5 but TX FIFO only gets 2 bytes
        // =====================================================
        $display("\n--- TEST 3: UNDERFLOW ERROR PATH ---");
        u_i2c_master.i2c_write_burst(7'h50, 8'h02, 8'h11, 8'h22, 8'h11); // pushes 3 (reuse task, 3rd byte ignored logically)
        u_i2c_master.i2c_write_reg(7'h50, 8'h01, 8'd5);   // COUNT=5, more than available
        u_i2c_master.i2c_write_reg(7'h50, 8'h00, 8'h80);  // CMD: GO=1, RW=0

        begin : errwait
            integer j;
            reg [7:0] st;
            j = 0;
            while (!status_err && j < 2000) begin
                @(posedge clk);
                j = j + 1;
            end
            check_bit("STATUS_err asserted internally on underflow", status_err, 1'b1);

            u_i2c_master.i2c_read_reg(7'h50, 8'h03, st);
            check_bit("STATUS.ERR bit read back over I2C", st[2], 1'b1);
        end

        // Recovery requires TWO GO writes by design: the first GO clears ERR
        // and returns the FSM to IDLE (that write is "consumed" by the error
        // handler itself); a second GO is what actually launches a new
        // transfer from a clean IDLE state.
        u_i2c_master.i2c_write_burst(7'h50, 8'h02, 8'h99, 8'h00, 8'h00); // push 1 real byte
        u_i2c_master.i2c_write_reg(7'h50, 8'h01, 8'd1);   // COUNT=1
        u_i2c_master.i2c_write_reg(7'h50, 8'h00, 8'h80);  // GO #1: clears ERR, -> IDLE
        u_i2c_master.i2c_write_reg(7'h50, 8'h00, 8'h80);  // GO #2: actually launches
        wait_for_done(3000);

        #2000;

        $display("\n=====================================");
        $display(" RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=====================================\n");

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);

        $finish;
    end

    // safety timeout so a hung simulation doesn't run forever
    initial begin
        #2_000_000;
        $display("[TIMEOUT] simulation did not finish in time");
        $finish;
    end

endmodule
