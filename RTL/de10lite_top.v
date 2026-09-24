// =============================================================================
// de10lite_top.v
// Top level for the DE10-Lite board. Ties I2C slave, SPI master and the
// control FSM together, and maps LEDs to STATUS bits for live debug.
// =============================================================================
module de10lite_top (
    input  wire        MAX10_CLK1_50,   // onboard 50 MHz oscillator, PIN_P11
    input  wire         KEY0,            // active-low pushbutton reset, PIN_B8

    inout  wire         GPIO_0,          // SDA,  PIN_V10
    input  wire          GPIO_1,          // SCL,  PIN_W10
    output wire           GPIO_2,          // SCK,  PIN_V9
    output wire            GPIO_3,          // MOSI, PIN_W9
    input  wire             GPIO_4,          // MISO, PIN_V8
    output wire              GPIO_5,          // CS_N, PIN_W8

    output wire [2:0]         LEDR             // LEDR[0]=busy LEDR[1]=done LEDR[2]=err
);

    wire clk = MAX10_CLK1_50;
    wire rst_n;

    reset_sync u_rst (
        .clk         (clk),
        .rst_n_async (KEY0),
        .rst_n_sync  (rst_n)
    );

    // ---- I2C slave <-> register file signals ----
    wire [7:0] wr_data, rd_data;
    wire       wr_pulse, byte_rdy_tgl, rd_pulse;

    i2c_slave #(.I2C_ADDR(7'h50)) u_i2c (
        .clk          (clk),
        .rst_n        (rst_n),
        .sda          (GPIO_0),
        .scl_pad      (GPIO_1),
        .reg_ptr      (reg_ptr),
        .wr_data      (wr_data),
        .wr_pulse     (wr_pulse),
        .byte_rdy_tgl (byte_rdy_tgl),
        .rd_data      (rd_data),
        .rd_pulse     (rd_pulse)
    );

    // ---- SPI master <-> control FSM signals ----
    wire [7:0] spi_tx, spi_rx;
    wire       spi_start, spi_busy, spi_done;

    spi_master #(.CLK_DIV(25)) u_spi (   // 50MHz/(2*25) = 1 MHz SCK
        .clk     (clk),
        .rst_n   (rst_n),
        .sck     (GPIO_2),
        .mosi    (GPIO_3),
        .miso    (GPIO_4),
        .cs_n    (GPIO_5),
        .tx_byte (spi_tx),
        .rx_byte (spi_rx),
        .start   (spi_start),
        .busy    (spi_busy),
        .done    (spi_done)
    );

    // ---- control FSM + register file ----
    wire status_busy, status_done, status_err;

    bridge_fsm u_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .reg_ptr      (reg_ptr),
        .wr_data      (wr_data),
        .wr_pulse     (wr_pulse),
        .rd_pulse     (rd_pulse),
        .rd_data      (rd_data),
        .spi_tx       (spi_tx),
        .spi_start    (spi_start),
        .spi_rx       (spi_rx),
        .spi_busy     (spi_busy),
        .spi_done     (spi_done),
        .STATUS_busy  (status_busy),
        .STATUS_done  (status_done),
        .STATUS_err   (status_err)
    );

    assign LEDR[0] = status_busy;
    assign LEDR[1] = status_done;
    assign LEDR[2] = status_err;

endmodule
