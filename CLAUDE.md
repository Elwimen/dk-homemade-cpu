# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A homemade 8-bit Harvard architecture CPU designed in Logisim, implemented in Verilog RTL, and accompanied by a full toolchain (assembler, disassembler, netlist extractor). The CPU has 12-bit instructions, an 8-bit data path, 13 instructions, no adder (NAND only), and runs a shell-like ROM program called "Useless OS".

## Running the Assembler

```bash
python3 assembler.py <source.asm>            # outputs <source.hex>
python3 assembler.py <source.asm> -o out.hex
```

Two-pass assembler. Supports labels, comments (`;`), hex literals (`0xff`), decimal, and character literals (`'A'`, `'\n'`). Output is Logisim `v2.0 raw` hex format.

`useless_OS_clean.asm` is the canonical labelled source; it assembles identically to `useless_OS.hex`.

## Running the Disassembler

```bash
python3 disassembler.py                          # default: useless_OS.hex → useless_OS.asm
python3 disassembler.py <input.hex>
python3 disassembler.py <input.hex> -o out.asm
```

## Running the Netlist Extractor

```bash
python3 extract_netlist.py                           # → cpu_netlist.json
python3 extract_netlist.py CPU_design.circ -o out.json
python3 extract_netlist.py --summary                 # also print net summary to stdout
netlistsvg cpu_netlist.json -o cpu_netlist.svg       # render to SVG
```

Parses the Logisim `.circ` file, flood-fills wire segments into nets, decodes Splitter pin geometry, and emits a netlistsvg-compatible JSON with 11 high-level cells. `netlistsvg` is installed globally via npm.

## Running the Python Simulator (Interactive)

```bash
python3 cpu_sim.py                    # interactive shell with useless_OS.hex
python3 cpu_sim.py <rom.hex>          # load a specific ROM image
python3 cpu_sim.py --trace            # trace every instruction to stderr
python3 cpu_sim.py --max-cycles N     # stop after N cycles
```

Pure-Python cycle-accurate simulator. Runs in raw terminal mode — characters reach the CPU immediately. Blocks on stdin only when the CPU polls `in1` (opcode 0x2) and the buffer is empty.

## Running the Verilog Simulation

```bash
cd verilog
make        # generate rom_init.mem, compile with iverilog, run simulation
make wave   # open cpu_sim.vcd in GTKWave
make clean
```

Or manually:
```bash
cd verilog && iverilog -g2012 -Wall -o sim tb_cpu.v cpu.v && ./sim
```

Expected output includes the welcome banner, `Shell:>` prompt, keyboard input "help\n", and the help response.

## ISA (Instruction Set Architecture)

Instructions are 12 bits: 4-bit opcode (bits 11-8) + 8-bit operand (bits 7-0).

| Opcode | Mnemonic | Operation |
|--------|----------|-----------|
| 0x0 | `mov out1, imm` | out1 ← imm |
| 0x1 | `mov out2, imm` | out2 ← imm |
| 0x2 | `mov a, in1` | a ← in1 (kbd ready flag) |
| 0x3 | `mov a, in2` | a ← in2 (kbd character) |
| 0x4 | `mov a, [addr]` | a ← RAM[addr] |
| 0x5 | `mov [addr], a` | RAM[addr] ← a |
| 0x6 | `mov out1, a` | out1 ← a |
| 0x7 | `mov a, imm` | a ← imm |
| 0x8 | `nand a, imm` | a ← ~(a & imm) |
| 0x9 | `cmp a, imm` | eq_flag ← (a == imm) |
| 0xA | `jmp addr` | PC ← addr |
| 0xB | `je addr` | if eq_flag: PC ← addr |
| 0xC | `jne addr` | if !eq_flag: PC ← addr |

## Hex File Format

Logisim hex format: first line is `v2.0 raw`, followed by space-separated 3-digit hex values (12-bit words). `useless_OS.hex` is the ROM image.

`verilog/rom_init.mem` is the same data converted to one value per line for `$readmemh`.

## Architecture Notes

- Harvard: separate ROM (program) and RAM (data) — both 256 locations, 8-bit addresses
- Single-cycle: every posedge clk fetches, decodes, executes, and writes back
- Data bus: 8-bit, driven by 5 tri-state sources per bit (modelled as a case-mux in Verilog)
- `out2` controls TTY mode: 0=off, 1=print out1, 2=echo keyboard
- `in1` = keyboard ready flag, `in2` = keyboard character
- Equal Flag: 1-bit D flip-flop set by `cmp`; read by `je`/`jne` on the following clock
- NAND unit: 8 two-input NAND gates, bitwise on accumulator and operand
- CMP unit: 8 XOR gates + 8-input NOR gate → feeds Equal Flag FF
- ROM limited to 256 instructions (8-bit PC)
- Only the first character of input is used for command dispatch in the OS

## Key Implementation Files

| File | Purpose |
|------|---------|
| `CPU_design.circ` | Logisim circuit (ground truth) |
| `assembler.py` | .asm → Logisim .hex |
| `disassembler.py` | Logisim .hex → .asm |
| `extract_netlist.py` | Logisim .circ → netlistsvg JSON |
| `cpu_sim.py` | Interactive Python CPU simulator |
| `verilog/cpu.v` | Verilog RTL |
| `verilog/tb_cpu.v` | Simulation testbench |
| `useless_OS_clean.asm` | Annotated OS source |
