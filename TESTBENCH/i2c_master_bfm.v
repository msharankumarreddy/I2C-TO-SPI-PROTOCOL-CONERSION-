`timescale 1ns/1ps
// =============================================================================
// i2c_master_bfm.v
// Behavioral I2C master model (simulation-only peripheral). Drives SDA as
// open-drain, generates START/STOP/repeated-START, sends/receives bytes
// with ACK/NACK, at a configurable half-period. Used by the testbench to
// stand in for the real host MCU.
// =============================================================================
module i2c_master_bfm #(
    parameter HALF_PERIOD_NS = 5000   // 5000ns half period = 100kHz SCL
)(
    inout  wire sda,
    inout  wire scl
);

    reg sda_drv, scl_drv;
    assign sda = sda_drv ? 1'bz : 1'b0;
    assign scl = scl_drv ? 1'bz : 1'b0;

    initial begin
        sda_drv = 1'b1;
        scl_drv = 1'b1;
    end

    task automatic i2c_idle;
        begin
            sda_drv = 1'b1;
            scl_drv = 1'b1;
        end
    endtask

    task automatic i2c_start;
        begin
            sda_drv = 1'b1; scl_drv = 1'b1; #HALF_PERIOD_NS;
            sda_drv = 1'b0;                 #HALF_PERIOD_NS;  // SDA falls while SCL high
            scl_drv = 1'b0;                 #HALF_PERIOD_NS;
        end
    endtask

    task automatic i2c_rep_start;
        begin
            sda_drv = 1'b1; #HALF_PERIOD_NS;
            scl_drv = 1'b1; #HALF_PERIOD_NS;
            sda_drv = 1'b0; #HALF_PERIOD_NS;   // START again
            scl_drv = 1'b0; #HALF_PERIOD_NS;
        end
    endtask

    task automatic i2c_stop;
        begin
            sda_drv = 1'b0; #HALF_PERIOD_NS;
            scl_drv = 1'b1; #HALF_PERIOD_NS;
            sda_drv = 1'b1;                 #HALF_PERIOD_NS;  // SDA rises while SCL high
        end
    endtask

    // sends one byte MSB-first, returns 1 if slave ACKed
    task automatic i2c_send_byte(input [7:0] data, output ack);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                sda_drv = data[i];
                #HALF_PERIOD_NS;
                scl_drv = 1'b1;
                #HALF_PERIOD_NS;
                scl_drv = 1'b0;
            end
            // release SDA, sample ACK
            sda_drv = 1'b1;
            #HALF_PERIOD_NS;
            scl_drv = 1'b1;
            ack = ~sda;   // slave pulls low = ACK
            #HALF_PERIOD_NS;
            scl_drv = 1'b0;
        end
    endtask

    // receives one byte MSB-first, master drives ack_bit (0=ACK,1=NACK)
    task automatic i2c_recv_byte(output [7:0] data, input ack_bit);
        integer i;
        begin
            sda_drv = 1'b1; // release for slave to drive
            for (i = 7; i >= 0; i = i - 1) begin
                #HALF_PERIOD_NS;
                scl_drv = 1'b1;
                #(HALF_PERIOD_NS/2);
                data[i] = sda;
                #(HALF_PERIOD_NS/2);
                scl_drv = 1'b0;
            end
            #HALF_PERIOD_NS;
            sda_drv = ack_bit;  // 0=ACK, 1=NACK
            scl_drv = 1'b1;
            #HALF_PERIOD_NS;
            scl_drv = 1'b0;
            sda_drv = 1'b1;
        end
    endtask

    // convenience: full "write to register" transaction
    task automatic i2c_write_reg(input [6:0] addr, input [7:0] reg_ptr, input [7:0] data);
        reg ack;
        begin
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack);
            i2c_send_byte(reg_ptr, ack);
            i2c_send_byte(data, ack);
            i2c_stop;
        end
    endtask

    // convenience: write reg_ptr + N bytes in one transaction (for FIFO bursts)
    task automatic i2c_write_burst(input [6:0] addr, input [7:0] reg_ptr,
                                    input [7:0] d0, input [7:0] d1, input [7:0] d2);
        reg ack;
        begin
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack);
            i2c_send_byte(reg_ptr, ack);
            i2c_send_byte(d0, ack);
            i2c_send_byte(d1, ack);
            i2c_send_byte(d2, ack);
            i2c_stop;
        end
    endtask

    // convenience: set reg_ptr then repeated-start read one byte
    task automatic i2c_read_reg(input [6:0] addr, input [7:0] reg_ptr, output [7:0] data);
        reg ack;
        begin
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack);
            i2c_send_byte(reg_ptr, ack);
            i2c_rep_start;
            i2c_send_byte({addr, 1'b1}, ack);
            i2c_recv_byte(data, 1'b1);  // NACK after last byte
            i2c_stop;
        end
    endtask

endmodule
