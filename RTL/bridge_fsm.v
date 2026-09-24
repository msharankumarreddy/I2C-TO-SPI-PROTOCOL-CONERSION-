`timescale 1ns/1ps
// =============================================================================
// bridge_fsm.v
// Register map: 0x00 CMD (bit0=RW, bit7=GO), 0x01 COUNT, 0x02 DATA (FIFO port),
// 0x03 STATUS (bit0=BUSY bit1=DONE bit2=ERR bit3=TX_EMPTY bit4=TX_FULL
// bit5=RX_EMPTY bit6=RX_FULL). States: IDLE/LOAD/START/WAIT/DONE/ERROR.
// =============================================================================
module bridge_fsm #(
    parameter FIFO_DEPTH = 32
)(
    input  wire        clk,
    input  wire         rst_n,

    input  wire [1:0]  reg_ptr,
    input  wire [7:0]   wr_data,
    input  wire          wr_pulse,
    input  wire           rd_pulse,

    output reg  [7:0]     rd_data,

    output reg  [7:0]      spi_tx,
    output reg               spi_start,
    input  wire [7:0]         spi_rx,
    input  wire                 spi_busy,
    input  wire                  spi_done,

    output wire STATUS_busy,
    output wire STATUS_done,
    output wire STATUS_err
);

    localparam S_IDLE=0, S_LOAD=1, S_START=2, S_WAIT=3, S_DONE_ST=4, S_ERROR=5;
    reg [2:0] state;

    reg [7:0] CMD, COUNT;
    reg       busy_bit, done_bit, err_bit;
    reg [7:0] xfer_cnt;

    assign STATUS_busy = busy_bit;
    assign STATUS_done = done_bit;
    assign STATUS_err  = err_bit;

    wire go_pulse = wr_pulse && (reg_ptr==2'd0) && wr_data[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            CMD <= 8'h00; COUNT <= 8'h00;
        end else if (wr_pulse) begin
            case (reg_ptr)
                2'd0: CMD   <= wr_data;
                2'd1: COUNT <= wr_data;
                default: ;
            endcase
        end
    end

    wire        tx_wr_en = wr_pulse && (reg_ptr==2'd2);
    wire [7:0]  tx_wdata = wr_data;
    wire [7:0]  tx_rdata;
    wire        tx_full, tx_empty;
    wire        tx_rd_en = (state==S_LOAD) && !CMD[0] && !tx_empty;

    fifo_sync #(.DEPTH(FIFO_DEPTH), .DW(8)) u_tx_fifo (
        .clk(clk), .rst_n(rst_n), .wr_en(tx_wr_en), .wdata(tx_wdata),
        .rd_en(tx_rd_en), .rdata(tx_rdata), .full(tx_full), .empty(tx_empty)
    );

    wire [7:0]  rx_rdata;
    wire        rx_full, rx_empty;
    wire        rx_wr_en = (state==S_WAIT) && spi_done && CMD[0] && !rx_full;
    wire [7:0]  rx_wdata = spi_rx;
    wire        rx_rd_en = rd_pulse && (reg_ptr==2'd2);

    fifo_sync #(.DEPTH(FIFO_DEPTH), .DW(8)) u_rx_fifo (
        .clk(clk), .rst_n(rst_n), .wr_en(rx_wr_en), .wdata(rx_wdata),
        .rd_en(rx_rd_en), .rdata(rx_rdata), .full(rx_full), .empty(rx_empty)
    );

    always @(*) begin
        case (reg_ptr)
            2'd0: rd_data = CMD;
            2'd1: rd_data = COUNT;
            2'd2: rd_data = rx_rdata;
            2'd3: rd_data = {rx_full, rx_empty, tx_full, tx_empty,
                              err_bit, done_bit, busy_bit, 1'b0};
            default: rd_data = 8'h00;
        endcase
    end

    reg [15:0] watchdog;
    localparam WATCHDOG_MAX = 16'd2000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; busy_bit<=1'b0; done_bit<=1'b0; err_bit<=1'b0;
            spi_start<=1'b0; spi_tx<=8'h00; watchdog<=16'd0; xfer_cnt<=8'd0;
        end else begin
            spi_start <= 1'b0;
            case (state)
                S_IDLE: if (go_pulse) begin
                    busy_bit<=1'b1; done_bit<=1'b0; xfer_cnt<=8'd0; state<=S_LOAD;
                end

                S_LOAD: begin
                    watchdog <= 16'd0;
                    if (CMD[0]) begin
                        spi_tx <= 8'hFF; state <= S_START;
                    end else if (!tx_empty) begin
                        spi_tx <= tx_rdata; state <= S_START;
                    end else begin
                        err_bit <= 1'b1; state <= S_ERROR;
                    end
                end

                S_START: begin spi_start<=1'b1; state<=S_WAIT; end

                S_WAIT: begin
                    watchdog <= watchdog + 1'b1;
                    if (spi_done) begin
                        if (CMD[0] && rx_full) begin
                            err_bit <= 1'b1; state <= S_ERROR;
                        end else begin
                            xfer_cnt <= xfer_cnt + 1'b1;
                            state <= (xfer_cnt + 1'b1 == COUNT) ? S_DONE_ST : S_LOAD;
                        end
                    end else if (watchdog == WATCHDOG_MAX) begin
                        err_bit <= 1'b1; state <= S_ERROR;
                    end
                end

                S_DONE_ST: begin busy_bit<=1'b0; done_bit<=1'b1; state<=S_IDLE; end

                S_ERROR: begin
                    busy_bit <= 1'b0;
                    if (go_pulse) begin err_bit<=1'b0; state<=S_IDLE; end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
