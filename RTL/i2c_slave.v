`timescale 1ns/1ps
// =============================================================================
// i2c_slave.v
// I2C slave interface, oversampled by the 50 MHz system clock.
// Fixed 7-bit address 0x50. Register-pointer addressing:
//   first data byte after the address = reg_ptr (00=CMD,01=COUNT,02=DATA,03=STATUS)
//   subsequent bytes = data at that pointer.
// Supports repeated START: reg_ptr is preserved, only bit/byte framing resets.
//
// ---------------------------------------------------------------------------
// ROOT CAUSE OF THE READ-BACK BUG (now fixed) -- explained in detail:
//
// The read-back path (S_TXBYTE) shifts one byte out over SDA, MSB first.
// The very first version transitioned straight into S_TXBYTE and relied on
// a level-check ("if bit_cnt==0 && !sda_oe && scl_s==0") to latch the byte.
// That check raced against the SCL input synchronizer's own shift register
// in a way that gave different results depending on unrelated simulation
// scheduling (proven by re-running with/without debug $display statements
// and seeing the captured byte change) -- a genuine delta-cycle race.
//
// The fix below replaces that with a single dedicated clock-driven state,
// S_TX_ARM, which depends only on `clk` (never on scl_s), eliminating the
// race entirely. But a first attempt at S_TX_ARM introduced a DIFFERENT,
// purely logical bug: it loaded shreg <= rd_data directly and armed sda_oe
// from rd_data[7], then let the normal S_TXBYTE scl_fall handler run
// "sda_oe <= ~shreg[7]" on the very next real falling edge. Since shreg was
// unchanged since the arm, that first scl_fall re-derived the SAME bit
// (bit0) instead of advancing to bit1 -- a wasted "slot" that pushed every
// subsequent bit one position late. For the test byte 0xE0 (1110_0000) the
// first three bits are all '1', so bits 0-2 accidentally read correctly
// even with this bug (repeating '1' looks the same as advancing to the next
// '1'); the corruption only became visible at bit 3, where the value
// changes from 1 to 0 -- explaining exactly the observed 0xF0 result and
// why it looked byte-pattern-dependent.
//
// The correct fix: S_TX_ARM pre-shifts shreg by one position during the
// arm itself (shreg <= {rd_data[6:0], 1'b0}), so shreg[7] already holds
// bit1 by the time the first real scl_fall fires. sda_oe for bit0 is armed
// directly from rd_data[7], independent of shreg. This makes the ARM state
// and the normal per-bit S_TXBYTE handler consistent with each other from
// the very first bit, with no special-cased first iteration and no
// redundant re-drive. Verified by hand-tracing all 8 bits of 0xE0 and by
// simulation across multiple distinct byte values (see testbench).
// ---------------------------------------------------------------------------
module i2c_slave #(
    parameter [6:0] I2C_ADDR = 7'h50
)(
    input  wire        clk,
    input  wire         rst_n,

    inout  wire          sda,
    input  wire           scl_pad,

    output reg  [1:0]  reg_ptr,
    output reg  [7:0]   wr_data,
    output reg            wr_pulse,
    output reg              byte_rdy_tgl,
    input  wire [7:0]         rd_data,
    output reg                  rd_pulse
);

    reg sda_oe;
    wire sda_in;
    assign sda    = sda_oe ? 1'b0 : 1'bz;
    assign sda_in = sda;

    reg [2:0] sda_sync, scl_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_sync <= 3'b111;
            scl_sync <= 3'b111;
        end else begin
            sda_sync <= {sda_sync[1:0], sda_in};
            scl_sync <= {scl_sync[1:0], scl_pad};
        end
    end
    wire sda_s = sda_sync[2];
    wire scl_s = scl_sync[2];
    wire scl_rise = (scl_sync[2:1] == 2'b01);
    wire scl_fall = (scl_sync[2:1] == 2'b10);

    reg sda_s_d;
    always @(posedge clk) sda_s_d <= sda_s;
    wire start_cond = scl_s && sda_s_d && !sda_s;
    wire stop_cond  = scl_s && !sda_s_d && sda_s;

    localparam S_IDLE=0, S_ADDR=1, S_ACK_ADDR=2, S_RXBYTE=3, S_ACK_RX=4,
               S_TXBYTE=5, S_ACK_TX=6, S_WAIT_STOP=7, S_TX_ARM=8;
    reg [3:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shreg;
    reg       rw_bit;
    reg       first_byte;
    reg       addr_match_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            sda_oe       <= 1'b0;
            reg_ptr      <= 2'd0;
            wr_pulse     <= 1'b0;
            rd_pulse     <= 1'b0;
            byte_rdy_tgl <= 1'b0;
            first_byte   <= 1'b1;
        end else begin
            wr_pulse <= 1'b0;
            rd_pulse <= 1'b0;

            if (start_cond) begin
                state      <= S_ADDR;
                bit_cnt    <= 4'd0;
                sda_oe     <= 1'b0;
                first_byte <= 1'b1;
            end else if (stop_cond) begin
                state  <= S_IDLE;
                sda_oe <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: sda_oe <= 1'b0;

                    S_ADDR: if (scl_rise) begin
                        shreg <= {shreg[6:0], sda_s};
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd7)
                            rw_bit <= sda_s;
                    end else if (scl_fall && bit_cnt == 4'd8) begin
                        if (shreg[7:1] == I2C_ADDR) begin
                            sda_oe       <= 1'b1;
                            addr_match_r <= 1'b1;
                        end else begin
                            addr_match_r <= 1'b0;
                        end
                        state <= S_ACK_ADDR;
                    end

                    S_ACK_ADDR: if (scl_fall) begin
                        sda_oe  <= 1'b0;
                        bit_cnt <= 4'd0;
                        state   <= addr_match_r ? (rw_bit ? S_TX_ARM : S_RXBYTE) : S_IDLE;
                    end

                    S_RXBYTE: if (scl_rise) begin
                        shreg <= {shreg[6:0], sda_s};
                        bit_cnt <= bit_cnt + 1'b1;
                    end else if (scl_fall && bit_cnt==4'd8) begin
                        sda_oe <= 1'b1;
                        state  <= S_ACK_RX;
                    end

                    S_ACK_RX: if (scl_fall) begin
                        sda_oe <= 1'b0;
                        if (first_byte) begin
                            reg_ptr    <= shreg[1:0];
                            first_byte <= 1'b0;
                        end else begin
                            wr_data  <= shreg;
                            wr_pulse <= 1'b1;
                            if (reg_ptr == 2'd2)
                                byte_rdy_tgl <= ~byte_rdy_tgl;
                        end
                        bit_cnt <= 4'd0;
                        state   <= S_RXBYTE;
                    end

                    // S_TX_ARM: dedicated single clock-driven state -- fires
                    // exactly once, one cycle after entry, depends only on
                    // clk (not scl_s), eliminating the earlier race. Also
                    // pre-shifts shreg so the normal per-bit handler below
                    // is correct from the very first real scl_fall onward
                    // (see the detailed comment at the top of this file).
                    S_TX_ARM: begin
                        shreg   <= {rd_data[6:0], 1'b0}; // pre-shift: bit1 now at shreg[7]
                        sda_oe  <= ~rd_data[7];           // bit0 armed directly, not via shreg
                        bit_cnt <= 4'd0;
                        state   <= S_TXBYTE;
                    end

                    S_TXBYTE: begin
                        if (scl_fall) begin
                            sda_oe  <= ~shreg[7];
                            shreg   <= {shreg[6:0], 1'b0};
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                        if (bit_cnt == 4'd8) begin
                            sda_oe <= 1'b0;
                            state  <= S_ACK_TX;
                        end
                    end

                    S_ACK_TX: if (scl_rise) begin
                        rd_pulse <= 1'b1;
                        if (sda_s) begin
                            state <= S_WAIT_STOP;
                        end else begin
                            state <= S_TX_ARM;
                        end
                    end

                    S_WAIT_STOP: ;

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
