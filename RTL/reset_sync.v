`timescale 1ns/1ps
// =============================================================================
// reset_sync.v
// Async assert, synchronous deassert reset, per the reset/CDC discussion.
// =============================================================================
module reset_sync (
    input  wire clk,
    input  wire rst_n_async,   // e.g. KEY[0], active low, bouncy/async
    output wire rst_n_sync
);
    reg ff1, ff2;
    always @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            ff1 <= 1'b0;
            ff2 <= 1'b0;
        end else begin
            ff1 <= 1'b1;
            ff2 <= ff1;
        end
    end
    assign rst_n_sync = ff2;
endmodule
