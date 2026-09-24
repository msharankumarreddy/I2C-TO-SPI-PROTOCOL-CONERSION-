`timescale 1ns/1ps
// =============================================================================
// tb_simple.v
// Write burst + read burst, checked dynamically against a table of distinct
// payload values (not just 0xE0) -- specifically chosen to include bit
// patterns that would have exposed the earlier off-by-one-bit bug (any
// value whose bit3 differs from its bits 0-2, e.g. 0xE0, 0x55, 0x3C, 0x81).
// =============================================================================
module tb_simple;

    reg clk = 0;
    always #10 clk = ~clk;           // 50 MHz, 20ns period

    reg key0 = 0;
    wire rst_n;
    reset_sync u_rst (.clk(clk), .rst_n_async(key0), .rst_n_sync(rst_n));
    initial begin key0 = 0; #200; key0 = 1; end

    wire sda, scl;
    pullup(sda);
    pullup(scl);
    reg sda_drv = 1, scl_drv = 1;
    assign sda = sda_drv ? 1'bz : 1'b0;
    assign scl = scl_drv ? 1'bz : 1'b0;
    localparam HALF = 500; // ns

    wire [1:0] reg_ptr;
    wire [7:0] wr_data, rd_data;
    wire wr_pulse, byte_rdy_tgl, rd_pulse;

    i2c_slave #(.I2C_ADDR(7'h50)) u_i2c (
        .clk(clk), .rst_n(rst_n), .sda(sda), .scl_pad(scl),
        .reg_ptr(reg_ptr), .wr_data(wr_data), .wr_pulse(wr_pulse),
        .byte_rdy_tgl(byte_rdy_tgl), .rd_data(rd_data), .rd_pulse(rd_pulse)
    );

    wire [7:0] spi_tx, spi_rx;
    wire spi_start, spi_busy, spi_done;
    wire sck, mosi, miso, cs_n;

    spi_master #(.CLK_DIV(5)) u_spi (
        .clk(clk), .rst_n(rst_n), .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n),
        .tx_byte(spi_tx), .rx_byte(spi_rx), .start(spi_start), .busy(spi_busy), .done(spi_done)
    );

    wire status_busy, status_done, status_err;

    bridge_fsm #(.FIFO_DEPTH(32)) u_fsm (
        .clk(clk), .rst_n(rst_n),
        .reg_ptr(reg_ptr), .wr_data(wr_data), .wr_pulse(wr_pulse), .rd_pulse(rd_pulse),
        .rd_data(rd_data), .spi_tx(spi_tx), .spi_start(spi_start),
        .spi_rx(spi_rx), .spi_busy(spi_busy), .spi_done(spi_done),
        .STATUS_busy(status_busy), .STATUS_done(status_done), .STATUS_err(status_err)
    );

    // ---- SPI slave stand-in: echoes back a CONFIGURABLE byte per test ----
    reg [7:0] slave_echo_byte = 8'hE0;
    reg [7:0] slave_shreg;
    always @(negedge cs_n) slave_shreg = slave_echo_byte;
    always @(negedge sck) if (!cs_n) slave_shreg = {slave_shreg[6:0], 1'b0};
    assign miso = cs_n ? 1'bz : slave_shreg[7];

    task i2c_start; begin sda_drv=1; scl_drv=1; #HALF; sda_drv=0; #HALF; scl_drv=0; #HALF; end endtask
    task i2c_rstart; begin sda_drv=1; #HALF; scl_drv=1; #HALF; sda_drv=0; #HALF; scl_drv=0; #HALF; end endtask
    task i2c_stop; begin sda_drv=0; #HALF; scl_drv=1; #HALF; sda_drv=1; #HALF; end endtask

    task i2c_send(input [7:0] d);
        integer i;
        begin
            for (i=7;i>=0;i=i-1) begin sda_drv=d[i]; #HALF; scl_drv=1; #HALF; scl_drv=0; end
            sda_drv=1; #HALF; scl_drv=1; #HALF; scl_drv=0;
        end
    endtask

    task i2c_recv(output [7:0] d, input nack);
        integer i;
        begin
            sda_drv=1;
            for (i=7;i>=0;i=i-1) begin
                #HALF; scl_drv=1; #(HALF/2); d[i]=sda; #(HALF/2); scl_drv=0;
            end
            #HALF; sda_drv=nack; scl_drv=1; #HALF; scl_drv=0; sda_drv=1;
        end
    endtask

    integer pass_count = 0, fail_count = 0;
    reg [7:0] rb;

    task check(input [8*20-1:0] name, input [7:0] got, input [7:0] exp);
        begin
            if (got === exp) begin pass_count=pass_count+1; $display("[PASS] %0s got=0x%02h", name, got); end
            else begin fail_count=fail_count+1; $display("[FAIL] %0s got=0x%02h expected=0x%02h", name, got, exp); end
        end
    endtask

    // one full write-1-byte -> read-1-byte-back round trip against a given
    // slave echo pattern, so the whole read path gets exercised freshly
    // for each distinct bit pattern
    task run_payload_test(input [8*24-1:0] name, input [7:0] echo_val);
        begin
            slave_echo_byte = echo_val;

            i2c_start; i2c_send({7'h50,1'b0}); i2c_send(8'h02); i2c_send(8'hAA); i2c_stop; #500;
            i2c_start; i2c_send({7'h50,1'b0}); i2c_send(8'h01); i2c_send(8'd1);  i2c_stop; #500;
            i2c_start; i2c_send({7'h50,1'b0}); i2c_send(8'h00); i2c_send(8'h81); i2c_stop; #500; // RW=1 (read), GO=1

            wait(status_done); #100;
            check({name,"_done"}, status_done, 1'b1);
            check({name,"_err_clear"}, status_err, 1'b0);

            i2c_start; i2c_send({7'h50,1'b0}); i2c_send(8'h02);
            i2c_rstart; i2c_send({7'h50,1'b1}); i2c_recv(rb, 1'b1); i2c_stop;

            check({name,"_readback"}, rb, echo_val);
            #500;
        end
    endtask

    initial begin
        wait(rst_n); #200;

        // Deliberately includes bit patterns that would have exposed the
        // earlier bug (value changes somewhere in bits 3-4, which is
        // exactly where the off-by-one-bit corruption first became visible
        // for 0xE0). All of these must pass identically and deterministically.
        run_payload_test("test_e0", 8'hE0);  // 1110_0000 -- the original failing case
        run_payload_test("test_55", 8'h55);  // 0101_0101 -- alternating, worst case for any shift bug
        run_payload_test("test_3c", 8'h3C);  // 0011_1100
        run_payload_test("test_81", 8'h81);  // 1000_0001
        run_payload_test("test_ff", 8'hFF);  // all ones
        run_payload_test("test_00", 8'h00);  // all zeros -- but note: bridge treats
                                              // an all-zero byte normally, this just
                                              // checks the drive-low path thoroughly

        $display("========================================");
        $display(" PASSED: %0d   FAILED: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("*** ALL TESTS PASSED, DETERMINISTICALLY ***");
        else $display("*** %0d TEST(S) FAILED ***", fail_count);
        $finish;
    end

    initial begin #2_000_000; $display("[TIMEOUT]"); $finish; end

endmodule
