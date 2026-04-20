`default_nettype none

module top_arty (
    input  wire clk,        // 100 MHz oscillator
    input  wire rst_btn,    // BTN0, active-high
    input  wire uart_rx,
    output wire uart_tx,

    // Onboard LEDs — active-high
    output wire led_cpu,    // LD0: off=halted, on=running, blink=error
    output wire led_tx,     // LD1: activity on TX line
    output wire led_rx      // LD2: activity on RX line
);
    parameter CLKS_PER_BIT = 10416;  // 100 MHz / 9600 baud

    localparam OUT2_OFF   = 8'h00,
               OUT2_PRINT = 8'h01,
               OUT2_ECHO  = 8'h02,
               OUT2_HALT  = 8'hFF;

    // -----------------------------------------------------------------------
    // Reset synchroniser — double-flop active-high button
    // -----------------------------------------------------------------------
    reg rst_s0, rst_s1;
    always @(posedge clk) begin
        rst_s0 <= rst_btn;
        rst_s1 <= rst_s0;
    end
    wire rst = rst_s1;

    // -----------------------------------------------------------------------
    // UART RX
    // -----------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_pulse;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk),
        .rst   (rst),
        .rx    (uart_rx),
        .data  (rx_byte),
        .valid (rx_pulse)
    );

    reg [7:0] rx_buf;
    reg       rx_buf_valid;
    wire      in2_rd;

    localparam CR = 8'h0D, LF = 8'h0A;
    wire [7:0] rx_byte_xlat = (rx_byte == CR) ? LF : rx_byte;

    always @(posedge clk) begin
        if (rst) begin
            rx_buf       <= 8'h00;
            rx_buf_valid <= 1'b0;
        end else begin
            if (in2_rd)
                rx_buf_valid <= 1'b0;
            if (rx_pulse) begin
                rx_buf       <= rx_byte_xlat;
                rx_buf_valid <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // UART TX
    // -----------------------------------------------------------------------
    wire [7:0] cpu_out1, cpu_out2, cpu_out1_next;
    wire       cpu_out1_wr;
    wire       tx_busy;

    wire tx_stb   = cpu_out1_wr && (cpu_out2 == OUT2_PRINT);
    wire cpu_stall = (cpu_out2 == OUT2_PRINT) && tx_busy;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk  (clk),
        .rst  (rst),
        .data (cpu_out1_next),
        .stb  (tx_stb),
        .tx   (uart_tx),
        .busy (tx_busy)
    );

    // -----------------------------------------------------------------------
    // CPU
    // -----------------------------------------------------------------------
    cpu u_cpu (
        .clk       (clk),
        .rst       (rst),
        .in1       (rx_buf_valid),
        .in2       (rx_buf),
        .out1      (cpu_out1),
        .out2      (cpu_out2),
        .out1_next (cpu_out1_next),
        .out1_wr   (cpu_out1_wr),
        .in2_rd    (in2_rd),
        .stall     (cpu_stall)
    );

    // -----------------------------------------------------------------------
    // LEDs  (active-high)
    // -----------------------------------------------------------------------
    reg [23:0] blink_cnt;
    always @(posedge clk) blink_cnt <= blink_cnt + 24'd1;
    wire blink = blink_cnt[23];

    wire cpu_halted = rst || (cpu_out2 == OUT2_HALT);
    wire cpu_error  = !cpu_halted &&
                      (cpu_out2 != OUT2_OFF)   &&
                      (cpu_out2 != OUT2_PRINT) &&
                      (cpu_out2 != OUT2_ECHO);

    assign led_cpu = cpu_halted ? 1'b0 :   // off
                     cpu_error  ? blink  :  // blink
                                  1'b1;     // on

    // UART lines are idle-high; invert so LED lights on activity
    assign led_tx = ~uart_tx;
    assign led_rx = ~uart_rx;

endmodule
