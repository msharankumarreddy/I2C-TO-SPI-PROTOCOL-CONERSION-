`timescale 1ns/1ps
// =============================================================================
// spi_master.v
// SPI master, Mode 0, MSB-first, single CS, separate tx_shreg/rx_shreg (a
// shared-register version corrupted both directions -- fixed by simulation).
// =============================================================================
module spi_master #(
    parameter CLK_DIV = 25
)(
    input  wire       clk,
    input  wire        rst_n,
    output wire        sck,
    output wire         mosi,
    input  wire          miso,
    output wire           cs_n,
    input  wire [7:0]     tx_byte,
    output reg  [7:0]     rx_byte,
    input  wire            start,
    output reg              busy,
    output reg               done
);
    localparam S_IDLE=0, S_SETUP=1, S_SHIFT=2, S_DONE=3;
    reg [1:0]  state;
    reg [4:0]  bit_cnt;
    reg [7:0]  tx_shreg;
    reg [7:0]  rx_shreg;
    reg [15:0] div_cnt;
    reg        sck_r, cs_r, mosi_r;

    assign sck  = sck_r;
    assign cs_n = cs_r;
    assign mosi = mosi_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; cs_r<=1'b1; sck_r<=1'b0; mosi_r<=1'b0; busy<=1'b0; done<=1'b0;
            div_cnt<=16'd0; bit_cnt<=5'd0; tx_shreg<=8'h00; rx_shreg<=8'h00;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    cs_r<=1'b1; sck_r<=1'b0;
                    if (start) begin
                        tx_shreg<=tx_byte; bit_cnt<=5'd0; cs_r<=1'b0; div_cnt<=16'd0; busy<=1'b1; state<=S_SETUP;
                    end
                end
                S_SETUP: begin
                    if (div_cnt==CLK_DIV-1) begin div_cnt<=16'd0; mosi_r<=tx_byte[7]; state<=S_SHIFT; end
                    else div_cnt<=div_cnt+1'b1;
                end
                S_SHIFT: begin
                    if (div_cnt==CLK_DIV-1) begin
                        div_cnt<=16'd0; sck_r<=~sck_r;
                        if (sck_r==1'b0) begin
                            rx_shreg<={rx_shreg[6:0],miso}; bit_cnt<=bit_cnt+1'b1;
                        end else begin
                            if (bit_cnt==5'd8) begin rx_byte<=rx_shreg; state<=S_DONE; end
                            else begin mosi_r<=tx_shreg[6]; tx_shreg<={tx_shreg[6:0],1'b0}; end
                        end
                    end else div_cnt<=div_cnt+1'b1;
                end
                S_DONE: begin cs_r<=1'b1; sck_r<=1'b0; busy<=1'b0; done<=1'b1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
