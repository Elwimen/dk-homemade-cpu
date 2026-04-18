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
    output reg  [7:0] out1,      // character to display
    output reg  [7:0] out2,      // TTY mode control

    // Combinational: value being written to out1 this cycle (valid when out1_wr=1)
    // Use this as UART TX data so the transceiver latches the correct byte
    output wire [7:0] out1_next,
    output wire       out1_wr,   // high for one clock when out1 is being written

    // Handshake: pulses for one clock when mov a, in2 executes
    output wire       in2_rd,

    // Stall: hold PC and suppress all writes while high
    input  wire       stall
);

    // -----------------------------------------------------------------------
    // Program Counter (8-bit, wraps at 256)
    // -----------------------------------------------------------------------
    // Opcode encoding
    localparam OP_MOV_OUT1_IMM = 4'h0,
               OP_MOV_OUT2_IMM = 4'h1,
               OP_MOV_A_IN1    = 4'h2,
               OP_MOV_A_IN2    = 4'h3,
               OP_MOV_A_MEM    = 4'h4,
               OP_MOV_MEM_A    = 4'h5,
               OP_MOV_OUT1_A   = 4'h6,
               OP_MOV_A_IMM    = 4'h7,
               OP_NAND         = 4'h8,
               OP_CMP          = 4'h9,
               OP_JMP          = 4'hA,
               OP_JE           = 4'hB,
               OP_JNE          = 4'hC;

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
    reg [7:0] ram_rdata;                   // registered read — enables M4K block RAM inference
    always @(posedge clk)
        ram_rdata <= ram[operand];

    // -----------------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------------
    reg [7:0] reg_a;      // accumulator
    reg       eq_flag;    // equality flag, written by CMP
    reg       load_pending; // stall flag: reg_a ← ram_rdata next cycle

    assign in2_rd    = !rst && !load_pending && !stall && (opcode == OP_MOV_A_IN2);
    assign out1_wr   = !rst && !load_pending && !stall &&
                       (opcode == OP_MOV_OUT1_IMM || opcode == OP_MOV_OUT1_A);
    assign out1_next = data_bus;

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
            OP_MOV_OUT1_IMM: data_bus = operand;
            OP_MOV_OUT2_IMM: data_bus = operand;
            OP_MOV_A_IN1:    data_bus = {7'b0, in1};
            OP_MOV_A_IN2:    data_bus = in2;
            OP_MOV_A_MEM:    data_bus = ram_rdata;
            OP_MOV_OUT1_A:   data_bus = reg_a;
            OP_MOV_A_IMM:    data_bus = operand;
            OP_NAND:         data_bus = ~(reg_a & operand);
            default:         data_bus = 8'h00;
        endcase
    end

    // -----------------------------------------------------------------------
    // Sequential logic: PC update, register writes, RAM write
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pc           <= 8'h00;
            reg_a        <= 8'h00;
            out1         <= 8'h00;
            out2         <= 8'h00;
            eq_flag      <= 1'b0;
            load_pending <= 1'b0;
        end else if (stall) begin
            // freeze: UART TX is busy, wait for it to drain
        end else if (load_pending) begin
            // Stall cycle: RAM read has settled, commit to reg_a and resume
            reg_a        <= ram_rdata;
            load_pending <= 1'b0;
            pc           <= pc + 8'd1;
        end else begin

            // ---- Program Counter ----------------------------------------
            case (opcode)
                OP_JMP:      pc <= operand;
                OP_JE:       pc <= eq_flag  ? operand : pc + 8'd1;
                OP_JNE:      pc <= !eq_flag ? operand : pc + 8'd1;
                OP_MOV_A_MEM: ;                              // stall: hold pc
                default:     pc <= pc + 8'd1;
            endcase

            // ---- Register and RAM writes ---------------------------------
            case (opcode)
                OP_MOV_OUT1_IMM: out1         <= data_bus;
                OP_MOV_OUT2_IMM: out2         <= data_bus;
                OP_MOV_A_IN1:    reg_a        <= data_bus;
                OP_MOV_A_IN2:    reg_a        <= data_bus;
                OP_MOV_A_MEM:    load_pending <= 1'b1;      // result arrives next cycle
                OP_MOV_MEM_A:    ram[operand] <= reg_a;
                OP_MOV_OUT1_A:   out1         <= data_bus;
                OP_MOV_A_IMM:    reg_a        <= data_bus;
                OP_NAND:         reg_a        <= data_bus;
                OP_CMP:          eq_flag      <= (reg_a == operand);
                default: ;
            endcase

        end
    end

endmodule
