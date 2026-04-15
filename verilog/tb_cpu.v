// tb_cpu.v — Testbench for the homemade CPU
//
// Simulates a terminal session:
//   - Captures TTY output (out2=1, out1!=0) and prints to stdout
//   - Injects keyboard input "help\n" character by character
//   - Terminates after 12 000 clock cycles (enough for banner + help response)
//
// Run with:
//   iverilog -g2012 -o sim tb_cpu.v cpu.v && ./sim

`timescale 1ns/1ps
`default_nettype none

module tb_cpu;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg        clk = 0;
    reg        rst = 1;
    reg        in1 = 0;
    reg  [7:0] in2 = 8'h00;
    wire [7:0] out1;
    wire [7:0] out2;

    cpu dut (
        .clk (clk),
        .rst (rst),
        .in1 (in1),
        .in2 (in2),
        .out1(out1),
        .out2(out2)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // TTY output capture
    //
    // The CPU sets out2=1 (print mode) and loads out1 with each character.
    // One character per clock cycle flows through out1 while out2=1.
    // The null byte (0x00) is used as a separator/flush; we skip it.
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && out2 == 8'h01 && out1 != 8'h00)
            $write("%c", out1);
    end

    // -----------------------------------------------------------------------
    // Keyboard input: "help\n"
    //
    // Protocol (from the assembly):
    //   1. CPU polls in1 with "mov a, in1"  (opcode 0x2) in a tight loop.
    //   2. When in1==1, it reads the character with "mov a, in2"  (opcode 0x3).
    //   3. After reading, the CPU processes the character and loops back.
    //
    // We detect opcode 0x3 via hierarchical reference to advance the buffer.
    // -----------------------------------------------------------------------
    localparam KBD_LEN = 5;
    reg [7:0] kbd [0:KBD_LEN-1];
    reg [3:0] kbd_ptr = 0;

    initial begin
        kbd[0] = "h";
        kbd[1] = "e";
        kbd[2] = "l";
        kbd[3] = "p";
        kbd[4] = 8'h0a;   // '\n'
    end

    // Expose CPU opcode for testbench logic (hierarchical reference)
    wire [3:0] cpu_op = dut.opcode;

    always @(posedge clk) begin
        if (rst) begin
            in1 <= 0;
            in2 <= 8'h00;
            kbd_ptr <= 0;
        end else begin
            if (cpu_op == 4'h3 && in1) begin
                // CPU just executed "mov a, in2" — character was consumed
                in1 <= 0;
                in2 <= 8'h00;
                kbd_ptr <= kbd_ptr + 1;
            end else if (!in1 && kbd_ptr < KBD_LEN) begin
                // Present the next character
                in1 <= 1;
                in2 <= kbd[kbd_ptr];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Simulation control
    // -----------------------------------------------------------------------
    integer cycle_count = 0;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    initial begin
        $dumpfile("cpu_sim.vcd");
        $dumpvars(0, tb_cpu);

        // Hold reset for 4 cycles, release on a falling edge for clean startup
        rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        $display("--- simulation start ---\n");

        // Run long enough to see: welcome banner + prompt + "help" command + response
        // Banner: ~58 instructions
        // Prompt: ~14 instructions
        // read_loop spin: ~3 per char × 5 chars + processing = ~200 cycles
        // Help text: ~80 instructions
        repeat(12000) @(posedge clk);

        $display("\n\n--- simulation done at cycle %0d ---", cycle_count);
        $finish;
    end

endmodule
