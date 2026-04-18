`default_nettype none

// 8N1 UART transmitter.
// Assert stb for one clock to start a transmission.
// busy is high while transmitting; a stb during busy is ignored.
module uart_tx #(
    parameter CLKS_PER_BIT = 5208   // 50 MHz / 9600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       stb,
    output reg        tx,
    output wire       busy
);
    localparam [12:0] BIT_FULL = CLKS_PER_BIT - 1;

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0]  state;
    reg [12:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx    <= 1'b1;
            cnt   <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (stb) begin
                        shift <= data;
                        cnt   <= BIT_FULL;
                        state <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;
                    if (cnt == 0) begin
                        cnt     <= BIT_FULL;
                        bit_idx <= 0;
                        state   <= DATA;
                    end else
                        cnt <= cnt - 13'd1;
                end

                DATA: begin
                    tx <= shift[bit_idx];
                    if (cnt == 0) begin
                        cnt <= BIT_FULL;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        cnt <= cnt - 13'd1;
                end

                STOP: begin
                    tx <= 1'b1;
                    if (cnt == 0)
                        state <= IDLE;
                    else
                        cnt <= cnt - 13'd1;
                end
            endcase
        end
    end

endmodule
