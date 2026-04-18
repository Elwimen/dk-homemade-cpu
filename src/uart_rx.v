`default_nettype none

// 8N1 UART receiver.
// Samples at bit-center using a simple baud counter.
// valid pulses for exactly one clock when a byte is ready.
module uart_rx #(
    parameter CLKS_PER_BIT = 5208   // 50 MHz / 9600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    // Two-flop synchroniser for async rx pin
    reg rx_s0, rx_s1;
    always @(posedge clk) begin
        rx_s0 <= rx;
        rx_s1 <= rx_s0;
    end

    localparam [12:0] BIT_FULL = CLKS_PER_BIT - 1;
    localparam [12:0] BIT_HALF = CLKS_PER_BIT / 2;

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0]  state;
    reg [12:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            state   <= IDLE;
            cnt     <= 0;
            bit_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (!rx_s1) begin       // falling edge = start bit
                        cnt   <= BIT_HALF;  // advance to mid-start-bit
                        state <= START;
                    end
                end

                START: begin
                    if (cnt == 0) begin
                        if (!rx_s1) begin   // start bit still low — valid
                            cnt     <= BIT_FULL;
                            bit_idx <= 0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE;  // glitch — abort
                        end
                    end else
                        cnt <= cnt - 13'd1;
                end

                DATA: begin
                    if (cnt == 0) begin
                        shift[bit_idx] <= rx_s1;
                        cnt <= BIT_FULL;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        cnt <= cnt - 13'd1;
                end

                STOP: begin
                    if (cnt == 0) begin
                        if (rx_s1) begin    // valid stop bit
                            data  <= shift;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else
                        cnt <= cnt - 13'd1;
                end
            endcase
        end
    end

endmodule
