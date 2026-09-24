`timescale 1ns/1ps
// =============================================================================
// spi_slave_model.v
// Behavioral SPI slave model (simulation-only peripheral). Mode 0 (CPOL=0,
// CPHA=0): samples MOSI on SCK rising edge, drives MISO on SCK falling
// edge. Echoes back a known, checkable pattern: for the Nth byte of a
// chip-select assertion (N=0,1,2,...) it drives MISO = 8'hE0 + N, so the
// testbench can verify exactly which byte the bridge received.
// =============================================================================
module spi_slave_model (
    input  wire sck,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n
);

    reg [7:0] rx_shreg;
    reg [7:0] tx_shreg;
    reg [3:0] bit_cnt;
    reg [7:0] byte_idx;

    reg [7:0] last_rx_byte;
    reg       last_rx_valid;

    initial begin
        miso = 1'bz;
        byte_idx = 8'd0;
        last_rx_valid = 1'b0;
    end

    always @(negedge cs_n) begin
        byte_idx = 8'd0;
        bit_cnt  = 4'd0;
        tx_shreg = 8'hE0 + byte_idx;  // first response byte pattern
        miso     = tx_shreg[7];
    end

    always @(posedge cs_n) begin
        miso = 1'bz;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            rx_shreg = {rx_shreg[6:0], mosi};
            bit_cnt  = bit_cnt + 1'b1;
            if (bit_cnt == 4'd8) begin
                last_rx_byte  = rx_shreg;
                last_rx_valid = 1'b1;
                $display("[SPI_SLAVE] received byte = 0x%02h", rx_shreg);
            end
        end
    end

    always @(negedge sck) begin
        if (!cs_n) begin
            if (bit_cnt == 4'd8) begin
                byte_idx = byte_idx + 1'b1;
                bit_cnt  = 4'd0;
                tx_shreg = 8'hE0 + byte_idx;
            end else begin
                tx_shreg = {tx_shreg[6:0], 1'b0};
            end
            miso = tx_shreg[7];
        end
    end

endmodule
