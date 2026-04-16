// cpu.v — Homemade 8-bit Harvard CPU in Verilog
//
// Architecture
//   Harvard: separate 256×12-bit ROM (program) and 256×8-bit RAM (data)
//   8-bit data path, 8-bit PC, 12-bit instructions (4-bit opcode + 8-bit operand)
//   Single-cycle execution: fetch, decode, execute all in one clock cycle
//   No adder — only NAND available for bitwise logic
//
// ISA
//   0x0  mov out1, imm     out1 ← imm
//   0x1  mov out2, imm     out2 ← imm
//   0x2  mov a, in1        a    ← in1 (keyboard-ready flag)
//   0x3  mov a, in2        a    ← in2 (keyboard character)
//   0x4  mov a, [addr]     a    ← RAM[addr]
//   0x5  mov [addr], a     RAM[addr] ← a
//   0x6  mov out1, a       out1 ← a
//   0x7  mov a, imm        a    ← imm
//   0x8  nand a, imm       a    ← ~(a & imm)
//   0x9  cmp  a, imm       eq_flag ← (a == imm)
//   0xA  jmp  addr         pc   ← addr
//   0xB  je   addr         pc   ← addr  if eq_flag
//   0xC  jne  addr         pc   ← addr  if !eq_flag
//
// I/O
//   in1  — keyboard-ready flag (1 = character available)
//   in2  — keyboard character (ASCII)
//   out1 — TTY character
//   out2 — TTY mode: 0=off, 1=print out1, 2=echo keyboard char, 0xFF=halt

`timescale 1ns/1ps
`default_nettype none

module cpu (
    input  wire       clk,
    input  wire       rst,

    // Keyboard interface
    input  wire       in1,      // keyboard-ready flag
    input  wire [7:0] in2,      // keyboard character

    // TTY interface
    output reg  [7:0] out1,     // character to display
    output reg  [7:0] out2      // TTY mode control
);

    // -----------------------------------------------------------------------
    // Program Counter (8-bit, wraps at 256)
    // -----------------------------------------------------------------------
    reg [7:0] pc;

    // -----------------------------------------------------------------------
    // Program ROM: 256 × 12-bit  (async read, initialised from file)
    // -----------------------------------------------------------------------
    reg [11:0] rom [0:255];
    initial $readmemh("rom_init.mem", rom);

    wire [11:0] instr   = rom[pc];
    wire [3:0]  opcode  = instr[11:8];
    wire [7:0]  operand = instr[7:0];

    // -----------------------------------------------------------------------
    // Data RAM: 256 × 8-bit  (async read, sync write)
    // -----------------------------------------------------------------------
    reg [7:0] ram [0:255];
    wire [7:0] ram_rdata = ram[operand];   // combinational read

    // -----------------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------------
    reg [7:0] reg_a;      // accumulator
    reg       eq_flag;    // equality flag, written by CMP

    // -----------------------------------------------------------------------
    // Data-bus mux (combinational)
    //
    // The Logisim design uses 8 tri-state controlled buffers per bit (one per
    // source), enabled by the instruction decoder.  Here we model the same
    // selection as a priority-encoded mux.
    // -----------------------------------------------------------------------
    reg [7:0] data_bus;
    always @(*) begin
        case (opcode)
            4'h0: data_bus = operand;             // mov out1, imm
            4'h1: data_bus = operand;             // mov out2, imm
            4'h2: data_bus = {7'b0, in1};         // mov a, in1  (zero-extend 1→8)
            4'h3: data_bus = in2;                 // mov a, in2
            4'h4: data_bus = ram_rdata;           // mov a, [addr]
            4'h6: data_bus = reg_a;               // mov out1, a
            4'h7: data_bus = operand;             // mov a, imm
            4'h8: data_bus = ~(reg_a & operand);  // nand a, imm
            default: data_bus = 8'h00;
        endcase
    end

    // -----------------------------------------------------------------------
    // Sequential logic: PC update, register writes, RAM write
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pc      <= 8'h00;
            reg_a   <= 8'h00;
            out1    <= 8'h00;
            out2    <= 8'h00;
            eq_flag <= 1'b0;
        end else begin

            // ---- Program Counter ----------------------------------------
            case (opcode)
                4'hA: pc <= operand;                              // jmp
                4'hB: pc <= eq_flag  ? operand : pc + 8'd1;     // je
                4'hC: pc <= !eq_flag ? operand : pc + 8'd1;     // jne
                default: pc <= pc + 8'd1;
            endcase

            // ---- Register and RAM writes ---------------------------------
            case (opcode)
                4'h0: out1  <= data_bus;             // mov out1, imm
                4'h1: out2  <= data_bus;             // mov out2, imm
                4'h2: reg_a <= data_bus;             // mov a, in1
                4'h3: reg_a <= data_bus;             // mov a, in2
                4'h4: reg_a <= data_bus;             // mov a, [addr]
                4'h5: ram[operand] <= reg_a;         // mov [addr], a
                4'h6: out1  <= data_bus;             // mov out1, a
                4'h7: reg_a <= data_bus;             // mov a, imm
                4'h8: reg_a <= data_bus;             // nand a, imm
                4'h9: eq_flag <= (reg_a == operand); // cmp  a, imm
                default: ;
            endcase

        end
    end

endmodule
