// tb_interactive.v — Interactive terminal testbench for the homemade CPU
//
// Connects the CPU to stdin/stdout so you can type commands in real time.
//
// Characters typed on stdin are fed into the CPU's keyboard interface.
// Characters the CPU prints (out2=1, out1!=0) go to stdout.
//
// Build and run:
//   iverilog -g2012 -o isim tb_interactive.v cpu.v && ./isim
//
// The simulation runs until you press Ctrl-C or the CPU halts.
// Raw terminal mode is enabled so characters are sent immediately (no Enter
// needed to flush the line to the simulator).

`timescale 1ns/1ps
`default_nettype none

module tb_interactive;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    reg        clk = 0;
    reg        rst = 1;
    reg        in1 = 0;
    reg  [7:0] in2 = 8'h00;
    wire [7:0] out1;
    wire [7:0] out2;

    cpu dut (
        .clk (clk), .rst (rst),
        .in1 (in1), .in2 (in2),
        .out1(out1), .out2(out2)
    );

    // 10 ns clock
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // TTY output — print whenever out2=1 and out1 is a non-null character
    // out2=0xFF is the halt signal — stop the simulation immediately
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && out2 == 8'hFF) begin
            $write("\n");
            $finish;
        end
        if (!rst && out2 == 8'h01 && out1 != 8'h00)
            $write("%c", out1);
    end

    // -----------------------------------------------------------------------
    // Keyboard input — fed from a shared memory buffer written by $fgetc
    //
    // Icarus Verilog does not support truly asynchronous stdin reads inside
    // always blocks, but we can poll $fgetc in a timed loop.  We run the
    // stdin reader in a parallel initial block that fires every N cycles and
    // tries to read a byte.  When a byte is available it is placed in the
    // kbd_char register and kbd_valid is raised for the CPU to consume.
    // -----------------------------------------------------------------------
    reg [7:0] kbd_char  = 8'h00;
    reg       kbd_valid = 0;

    wire [3:0] cpu_op = dut.opcode;

    // CPU side: present kbd_char as in2/in1 until CPU reads it
    always @(posedge clk) begin
        if (rst) begin
            in1 <= 0;
            in2 <= 8'h00;
        end else begin
            if (cpu_op == 4'h3 && in1) begin
                // CPU executed "mov a, in2" — character consumed
                in1 <= 0;
                in2 <= 8'h00;
            end else if (kbd_valid && !in1) begin
                in1 <= 1;
                in2 <= kbd_char;
            end
        end
    end

    // -----------------------------------------------------------------------
    // stdin reader — polls $fgetc every 100 cycles (1 µs at 100 MHz sim time)
    // Non-blocking: $fgetc returns -1 when no data is available.
    // We use $fopen with fd=32'h8000_0000 (Icarus extension for stdin) or
    // the standard approach of reading from fd 0.
    // -----------------------------------------------------------------------
    integer ch;
    integer STDIN = 32'h8000_0000;   // Icarus Verilog stdin file descriptor

    // Track when CPU consumes the character so we can clear kbd_valid
    always @(posedge clk) begin
        if (rst) begin
            kbd_valid <= 0;
        end else if (cpu_op == 4'h3 && in1) begin
            kbd_valid <= 0;
        end
    end

    // Poll stdin in a separate thread
    initial begin
        // Wait for reset to clear
        @(negedge rst);
        forever begin
            // Read one character from stdin (non-blocking in Icarus)
            ch = $fgetc(STDIN);
            if ($feof(STDIN)) begin
                $display("\n[exit]");
                $finish;
            end
            if (ch != -1 && ch != 32'hFFFF_FFFF) begin
                // Wait until the CPU has consumed any previous character
                while (kbd_valid) @(posedge clk);
                kbd_char  <= ch[7:0];
                kbd_valid <= 1;
            end
            // Yield for 100 cycles before polling again
            repeat(100) @(posedge clk);
        end
    end

    // -----------------------------------------------------------------------
    // Simulation control
    // -----------------------------------------------------------------------
    initial begin
        // Reset for 4 cycles
        rst = 1;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Run until Ctrl-C or $finish called elsewhere
        // Cap at 100 million cycles to avoid infinite runs in non-interactive use
        repeat(100_000_000) @(posedge clk);
        $display("\n[timeout]");
        $finish;
    end

endmodule
