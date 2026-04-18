`default_nettype none

module top (
    input  wire clk,
    input  wire rst_n,      // active-low onboard button (PIN_144)
    input  wire uart_rx,    // UART RX  (PIN_74)
    output wire uart_tx,    // UART TX  (PIN_73)

    // Onboard LEDs — active-low
    output wire led_cpu,    // PIN_3:  off=halted, on=running, blink=error
    output wire led_tx,     // PIN_7:  mirrors UART TX line
    output wire led_rx      // PIN_9:  mirrors UART RX line
);
    // UART baud divisor: 50 MHz / 9600 (override via parameter for other clocks)
    parameter CLKS_PER_BIT = 5208;

    // out2 mode values
    localparam OUT2_OFF   = 8'h00,
               OUT2_PRINT = 8'h01,
               OUT2_ECHO  = 8'h02,
               OUT2_HALT  = 8'hFF;
    // -----------------------------------------------------------------------
    // Reset synchroniser — invert active-low button, double-flop
    // -----------------------------------------------------------------------
    reg rst_s0, rst_s1;
    always @(posedge clk) begin
        rst_s0 <= ~rst_n;
        rst_s1 <= rst_s0;
    end
    wire rst = rst_s1;

    // -----------------------------------------------------------------------
    // UART RX
    // -----------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_pulse;    // 1-cycle: new byte arrived

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk),
        .rst   (rst),
        .rx    (uart_rx),
        .data  (rx_byte),
        .valid (rx_pulse)
    );

    // RX buffer: hold the byte until the CPU reads in2
    reg [7:0] rx_buf;
    reg       rx_buf_valid;
    wire      in2_rd;       // from cpu: mov a, in2 executed this cycle

    // Translate CR (0x0D) → LF (0x0A) so a standard Enter key works with the
    // firmware's 0x0A end-of-line check
    localparam CR = 8'h0D, LF = 8'h0A;
    wire [7:0] rx_byte_xlat = (rx_byte == CR) ? LF : rx_byte;

    always @(posedge clk) begin
        if (rst) begin
            rx_buf       <= 8'h00;
            rx_buf_valid <= 1'b0;
        end else begin
            // CPU consume takes priority first so a simultaneous new byte wins
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

    // Fire TX every time the CPU executes a mov-out1 in print mode.
    // Use out1_next (combinational pre-register) so the UART latches the
    // correct byte at the same clock edge the CPU writes it.
    wire tx_stb = cpu_out1_wr && (cpu_out2 == OUT2_PRINT);

    // Stall the CPU when it wants to print but the UART is still busy.
    wire cpu_stall = (cpu_out2 == OUT2_PRINT) &&
                     (cpu_out1_wr || tx_busy) && tx_busy;

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
    // LEDs  (active-low)
    // -----------------------------------------------------------------------

    // ~3 Hz blink for error indication
    reg [23:0] blink_cnt;
    always @(posedge clk) blink_cnt <= blink_cnt + 24'd1;
    wire blink = blink_cnt[23];

    // CPU status: halted when rst asserted or out2==HALT
    // Error when out2 holds an unrecognised value
    wire cpu_halted = rst || (cpu_out2 == OUT2_HALT);
    wire cpu_error  = !cpu_halted &&
                      (cpu_out2 != OUT2_OFF)   &&
                      (cpu_out2 != OUT2_PRINT) &&
                      (cpu_out2 != OUT2_ECHO);

    assign led_cpu = cpu_halted ? 1'b1 :   // off
                     cpu_error  ? ~blink :  // blink
                                  1'b0;     // on

    // UART LEDs mirror the line directly — idle-high, low during bits
    // Active-low LEDs match: line low = LED on = activity visible
    assign led_tx = uart_tx;
    assign led_rx = uart_rx;

endmodule
