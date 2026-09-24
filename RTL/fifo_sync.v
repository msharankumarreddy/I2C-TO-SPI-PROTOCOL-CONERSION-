`timescale 1ns/1ps
// =============================================================================
// fifo_sync.v
// Simple synchronous FIFO, look-ahead read (rdata = head, valid whenever
// !empty, no separate "read latency"). Single clock domain design, so no
// gray-code pointers or CDC needed here -- see bridge_fsm.v for usage.
// =============================================================================
module fifo_sync #(
    parameter DEPTH = 8,
    parameter DW    = 8
)(
    input  wire          clk,
    input  wire           rst_n,

    input  wire            wr_en,
    input  wire [DW-1:0]    wdata,

    input  wire              rd_en,
    output wire [DW-1:0]      rdata,

    output wire                full,
    output wire                 empty
);

    localparam AW = $clog2(DEPTH);

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wptr, rptr;
    reg [AW:0]   cnt;   // one extra bit: counts 0..DEPTH inclusive

    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    assign rdata = mem[rptr];   // look-ahead: always shows current head

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= {AW{1'b0}};
            rptr <= {AW{1'b0}};
            cnt  <= {(AW+1){1'b0}};
        end else begin
            if (do_wr) begin
                mem[wptr] <= wdata;
                wptr      <= wptr + 1'b1;
            end
            if (do_rd) begin
                rptr <= rptr + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: cnt <= cnt;        // 00: no change, 11: push+pop cancels out
            endcase
        end
    end

endmodule
