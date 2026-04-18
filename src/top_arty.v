`default_nettype none

// Arty A7-100T wrapper: adapts top for 100 MHz clock, active-high button/LEDs.
module top_arty (
    input  wire clk,
    input  wire rst_btn,    // BTN0, active-high
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_cpu,
    output wire led_tx,
    output wire led_rx
);
    wire led_cpu_n, led_tx_n, led_rx_n;

    top #(.CLKS_PER_BIT(10416)) u (   // 100 MHz / 9600 baud
        .clk    (clk),
        .rst_n  (~rst_btn),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led_cpu(led_cpu_n),
        .led_tx (led_tx_n),
        .led_rx (led_rx_n)
    );

    assign led_cpu = ~led_cpu_n;
    assign led_tx  = ~led_tx_n;
    assign led_rx  = ~led_rx_n;

endmodule
