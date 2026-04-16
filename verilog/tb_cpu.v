// tb_cpu.v — Testbench for the homemade CPU
//
// Simulates a terminal session:
//   - Captures TTY output (out2=1, out1!=0) and prints to stdout
//   - Injects keyboard input "help\n" then "exit\n" character by character
//   - Terminates when CPU asserts out2=0xFF (halt signal from exit command)
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
    // Cycle counter (used by halt and timeout messages)
    // -----------------------------------------------------------------------
    integer cycle_count = 0;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    // -----------------------------------------------------------------------
    // TTY output capture
    //
    // The CPU sets out2=1 (print mode) and loads out1 with each character.
    // One character per clock cycle flows through out1 while out2=1.
    // The null byte (0x00) is used as a separator/flush; we skip it.
    // out2=0xFF is the halt signal — stop the simulation.
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && out2 == 8'hFF) begin
            $display("\n--- halt (exit) at cycle %0d ---", cycle_count);
            $finish;
        end
        if (!rst && out2 == 8'h01 && out1 != 8'h00)
            $write("%c", out1);
    end

    // -----------------------------------------------------------------------
    // Keyboard input: "help\n" then "exit\n"
    //
    // Protocol (from the assembly):
    //   1. CPU polls in1 with "mov a, in1"  (opcode 0x2) in a tight loop.
    //   2. When in1==1, it reads the character with "mov a, in2"  (opcode 0x3).
    //   3. After reading, the CPU processes the character and loops back.
    //
    // We detect opcode 0x3 via hierarchical reference to advance the buffer.
    // -----------------------------------------------------------------------
    localparam KBD_LEN = 10;
    reg [7:0] kbd [0:KBD_LEN-1];
    reg [3:0] kbd_ptr = 0;

    initial begin
        kbd[0] = "h";
        kbd[1] = "e";
        kbd[2] = "l";
        kbd[3] = "p";
        kbd[4] = 8'h0a;   // '\n'
        kbd[5] = "e";
        kbd[6] = "x";
        kbd[7] = "i";
        kbd[8] = "t";
        kbd[9] = 8'h0a;   // '\n'
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
    initial begin
        $dumpfile("cpu_sim.vcd");
        $dumpvars(0, tb_cpu);

        // Hold reset for 4 cycles, release on a falling edge for clean startup
        rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        $display("--- simulation start ---\n");

        // Safety timeout — normally the CPU halts itself via out2=0xFF (exit command)
        repeat(500000) @(posedge clk);

        $display("\n\n--- timeout at cycle %0d ---", cycle_count);
        $finish;
    end

endmodule
