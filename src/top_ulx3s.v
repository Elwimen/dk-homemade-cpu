`default_nettype none

module top_ulx3s (
    input  wire       clk_25mhz,
    input  wire       rst,       // btn[0] PWRn — active-low
    input  wire       uart_rx,   // ftdi_txd → FPGA (pin M1)
    output wire       uart_tx,   // FPGA → ftdi_rxd (pin L4)

    // Onboard LEDs — active-high
    output wire [7:0] led,       // [0]=cpu, [1]=tx, [2]=rx, [7]=heartbeat
);
    // 25 MHz / 9600 baud
    parameter CLKS_PER_BIT = 2604;

    localparam OUT2_OFF   = 8'h00,
               OUT2_PRINT = 8'h01,
               OUT2_ECHO  = 8'h02,
               OUT2_HALT  = 8'hFF;

    // -----------------------------------------------------------------------
    // Reset synchroniser — btn[0] PWRn is active-low, invert + double-flop
    // -----------------------------------------------------------------------
    reg rst_s0, rst_s1;
    always @(posedge clk_25mhz) begin
        rst_s0 <= ~rst;
        rst_s1 <= rst_s0;
    end
    wire rst_sync = rst_s1;

    // -----------------------------------------------------------------------
    // UART RX
    // -----------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_pulse;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk_25mhz),
        .rst   (rst_sync),
        .rx    (uart_rx),
        .data  (rx_byte),
        .valid (rx_pulse)
    );

    reg [7:0] rx_buf;
    reg       rx_buf_valid;
    wire      in2_rd;

    localparam CR = 8'h0D, LF = 8'h0A;
    wire [7:0] rx_byte_xlat = (rx_byte == CR) ? LF : rx_byte;

    always @(posedge clk_25mhz) begin
        if (rst_sync) begin
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
        .clk  (clk_25mhz),
        .rst  (rst_sync),
        .data (cpu_out1_next),
        .stb  (tx_stb),
        .tx   (uart_tx),
        .busy (tx_busy)
    );

    // -----------------------------------------------------------------------
    // CPU
    // -----------------------------------------------------------------------
    cpu u_cpu (
        .clk       (clk_25mhz),
        .rst       (rst_sync),
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
    always @(posedge clk_25mhz) blink_cnt <= blink_cnt + 24'd1;
    wire blink = blink_cnt[23];

    wire cpu_halted = rst_sync || (cpu_out2 == OUT2_HALT);
    wire cpu_error  = !cpu_halted &&
                      (cpu_out2 != OUT2_OFF)   &&
                      (cpu_out2 != OUT2_PRINT) &&
                      (cpu_out2 != OUT2_ECHO);

    assign led[0]   = cpu_halted ? 1'b0 :   // off when halted
                      cpu_error  ? blink :   // blink on error
                                   1'b1;     // on when running
    assign led[1]   = ~uart_tx;             // activity on TX
    assign led[2]   = ~uart_rx;             // activity on RX
    assign led[6:3] = 4'b0;
    assign led[7]   = blink_cnt[22];        // ~6 Hz heartbeat

endmodule
