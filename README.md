# dkcpu

A hand-designed 8-bit Harvard architecture CPU, built to understand how CPUs work at every level — from logic gates to running software.

The CPU is designed and simulated in [Logisim](http://www.cburch.com/logisim/), implemented in Verilog RTL, and ships with a complete toolchain: assembler, disassembler, and netlist extractor.

![CPU Schematic](/design/CPU_schematic.png)

---

## Contents

- [Architecture](#architecture)
- [ISA Reference](#isa-reference)
- [Memory Map](#memory-map)
- [I/O Interface](#io-interface)
- [Useless OS](#useless-os)
- [Toolchain](#toolchain)
  - [Assembler](#assembler)
  - [Disassembler](#disassembler)
  - [Netlist Extractor](#netlist-extractor)
- [Verilog Implementation](#verilog-implementation)
  - [Simulating with Icarus Verilog](#simulating-with-icarus-verilog)
- [Logisim Simulation](#logisim-simulation)
- [Repository Layout](#repository-layout)

---

## Architecture

| Property | Value |
|----------|-------|
| Data path width | 8 bits |
| Instruction width | 12 bits |
| Address space | 8 bits (256 locations each for ROM and RAM) |
| Architecture | Harvard (separate program and data memory) |
| ALU | NAND only — no adder |
| Execution model | Single-cycle (one instruction per clock) |
| Instruction count | 13 |
| Program Counter | 8-bit, wraps at 256 |

The CPU is purely sequential: on every rising clock edge it fetches the instruction at `PC`, executes it, and advances (or jumps) `PC`. There is no pipeline, no cache, and no interrupt system.

**Block diagram:**

```
         ┌──────────┐  12-bit instr   ┌────────────────────┐
   PC ──▶│   ROM    │────────────────▶│  Instruction       │
         │ 256×12b  │                 │  Decoder           │
         └──────────┘                 │  (opcode → control)│
               ▲                      └────────┬───────────┘
               │ PC+1 / jump addr              │ control signals
               │                               ▼
         ┌─────┴────────────────────────────────────────────┐
         │                  8-bit DATA BUS                  │
         │   (tri-state mux: imm / RAM / IN1 / IN2 /        │
         │    REG_A / NAND result)                          │
         └──────┬──────┬──────┬──────┬────────────────┬────┘
                │      │      │      │                 │
             REG_A   OUT1   OUT2   RAM write       EQ_FLAG
           (accum)  (TTY)  (mode) (256×8b)       (CMP result)
                              │
                           ┌──┴───┐
                           │  TTY │◀── keyboard (IN1, IN2)
                           └──────┘
```

**Equality comparison** uses 8 XOR gates (one per bit) feeding an 8-input NOR gate. The output is latched into the 1-bit Equal Flag D flip-flop on the clock edge of a `cmp` instruction.

**NAND unit** uses 8 two-input NAND gates operating bitwise on the accumulator and the instruction operand.

---

## ISA Reference

Instructions are 12 bits: **opcode [11:8]** (4 bits) + **operand [7:0]** (8 bits).

| Opcode | Assembly syntax | Operation | Notes |
|--------|----------------|-----------|-------|
| `0x0` | `mov out1, imm` | `out1 ← imm` | Immediate to TTY char register |
| `0x1` | `mov out2, imm` | `out2 ← imm` | Immediate to TTY mode register |
| `0x2` | `mov a, in1` | `a ← in1` | Read keyboard-ready flag (1-bit, zero-extended) |
| `0x3` | `mov a, in2` | `a ← in2` | Read keyboard character |
| `0x4` | `mov a, [addr]` | `a ← RAM[addr]` | Load from data RAM |
| `0x5` | `mov [addr], a` | `RAM[addr] ← a` | Store to data RAM |
| `0x6` | `mov out1, a` | `out1 ← a` | Accumulator to TTY char register |
| `0x7` | `mov a, imm` | `a ← imm` | Load immediate into accumulator |
| `0x8` | `nand a, imm` | `a ← ~(a & imm)` | Bitwise NAND (only logic operation) |
| `0x9` | `cmp a, imm` | `eq_flag ← (a == imm)` | Compare; sets Equal Flag |
| `0xA` | `jmp addr` | `PC ← addr` | Unconditional jump |
| `0xB` | `je addr` | `if eq_flag: PC ← addr` | Jump if equal |
| `0xC` | `jne addr` | `if !eq_flag: PC ← addr` | Jump if not equal |

**Operand encoding:**

- `imm` — 8-bit immediate value in bits [7:0] of the instruction
- `addr` — 8-bit ROM or RAM address in bits [7:0]
- `in1` / `in2` / `out1` / `out2` — implicit; operand field unused or zero

**Assembly literals** (accepted by the assembler):

| Form | Example | Value |
|------|---------|-------|
| Decimal | `65` | 65 |
| Hex | `0x41` | 65 |
| Character | `'A'` | 65 |
| Escape | `'\n'` | 10 |

---

## Memory Map

| Space | Size | Width | Access |
|-------|------|-------|--------|
| ROM (program) | 256 words | 12 bits | Read-only; addressed by PC |
| RAM (data) | 256 bytes | 8 bits | Read/write via `mov a, [addr]` / `mov [addr], a` |

Both address spaces use 8-bit addresses (operand field of the instruction).  
ROM and RAM are completely separate — they do not alias.

---

## I/O Interface

### TTY output

The CPU talks to a terminal via two registers:

| Register | Role |
|----------|------|
| `out1` | Character to display (ASCII) |
| `out2` | TTY mode control |

`out2` mode values:

| Value | Meaning |
|-------|---------|
| `0x00` | TTY disabled |
| `0x01` | Print mode — display `out1` on every clock cycle while active |
| `0x02` | Echo mode — display the current keyboard character directly |

Characters are written by:
1. Setting `out2 = 0x01`
2. Loading successive ASCII values into `out1` with `mov out1, imm` or `mov out1, a`
3. Setting `out2 = 0x00` to stop

The null byte (`0x00`) in `out1` acts as a separator — it is loaded to prevent re-printing the last character when re-enabling TTY.

### Keyboard input

| Register | Role |
|----------|------|
| `in1` | Keyboard-ready flag (1 = character available) |
| `in2` | Keyboard character (ASCII) |

The polling idiom used throughout the OS:

```asm
read_loop:
    mov a, in1        ; read ready flag
    cmp a, 0x1        ; is it 1?
    jne read_loop     ; spin until ready
    mov a, in2        ; read the character
```

---

## Useless OS

The ROM is loaded with a minimal interactive shell. On boot it prints a welcome banner, then enters a read-eval loop:

```
Welcome to the UselessOS v7.3
By Danijel Korent

Shell:> _
```

**Commands:**

| Input | Response |
|-------|----------|
| `help` | Prints available commands |
| anything else | "I'm afraid I can't do that, Dave" |

Only the **first character** of input is used for command dispatch. The OS stores the first character in `RAM[0x00]` and checks it after Enter is pressed.

RAM layout used by the OS:

| Address | Contents |
|---------|----------|
| `0x00` | First character of current input line |
| `0x01` | Most recently read character |

Source: [`asm/useless_OS.asm`](asm/useless_OS.asm)  
ROM image: [`asm/useless_OS.hex`](asm/useless_OS.hex) (generated by `make`)

---

## Python Simulator

A pure-Python cycle-accurate simulator for interactive use:

```bash
python3 tools/cpu_sim.py                    # load asm/useless_OS.hex, interactive shell
python3 tools/cpu_sim.py <rom.hex>          # load a specific ROM image
python3 tools/cpu_sim.py --trace            # print every instruction to stderr
python3 tools/cpu_sim.py --max-cycles N     # stop after N cycles
```

The simulator puts the terminal in raw mode so characters reach the CPU immediately (no buffering). Backspace, Ctrl-C, and Ctrl-D are handled. When the CPU polls `in1` (opcode `0x2`) and the keyboard buffer is empty the simulator blocks on stdin — matching the real hardware behaviour.

---

## Toolchain

### Assembler

Converts assembly source to a Logisim `v2.0 raw` hex file.

```bash
python3 tools/assembler.py <source.asm>               # → <source.hex>
python3 tools/assembler.py <source.asm> -o out.hex    # explicit output path
```

**Features:**
- Two-pass (labels resolved in pass 1, encoded in pass 2)
- Labels: `label:` syntax, resolved to ROM addresses
- Comments: `;` to end of line
- Literals: decimal (`65`), hex (`0x41`), character (`'A'`), escapes (`'\n'`, `'\t'`, `'\0'`)
- All 13 instructions with full operand validation

**Example:**

```asm
; Print 'Hi' on the TTY
    mov out2, 0x1     ; enable TTY print mode
    mov out1, 'H'
    mov out1, 'i'
    mov out2, 0x0     ; disable TTY

loop:
    jmp loop          ; spin forever
```

### Disassembler

Converts a Logisim hex file back to human-readable assembly.

```bash
python3 tools/disassembler.py                          # disassemble asm/useless_OS.hex → asm/useless_OS.asm
python3 tools/disassembler.py <input.hex>              # → <input.asm>
python3 tools/disassembler.py <input.hex> -o out.asm  # explicit output path
```

Output format: `<hex_address>: <mnemonic> <operands>` with inline comments for printable ASCII values.

### Netlist Extractor

Parses the Logisim `.circ` file and produces a [netlistsvg](https://github.com/nturley/netlistsvg)-compatible JSON block diagram.

```bash
python3 tools/extract_netlist.py                                    # → cpu_netlist.json
python3 tools/extract_netlist.py design/CPU_design.circ             # explicit input
python3 tools/extract_netlist.py design/CPU_design.circ -o out.json
python3 tools/extract_netlist.py --summary                          # also print net summary to stdout
```

Render to SVG:

```bash
netlistsvg cpu_netlist.json -o cpu_netlist.svg
```

**What it does:**

1. Flood-fills all 930 wire segments into 149 distinct nets
2. Decodes Logisim Splitter pin geometry to map multi-bit bus nets
3. Identifies 8 data-bus bit lanes (each driven by 5 tri-state buffers)
4. Labels all key signals: `CLK`, `PC_addr[7:0]`, `INSTR[11:0]`, `DATA_BUS[7:0]`, `REG_A[7:0]`, `RAM_rdata[7:0]`, `EQ_FLAG`, `decoder[0x0..0xC]`
5. Emits a Yosys-style JSON with 11 high-level cells

**Key nets discovered:**

| Signal | Net IDs |
|--------|---------|
| `CLK` | 5 |
| `PC_addr[7:0]` | [134, 143, 36, 85, 109, 121, 130, 141] |
| `INSTR[11:0]` | [12, 14, 4, 3, 7, 28, 78, 132, 13, 23, 70, 18] |
| `DATA_BUS[7:0]` | [0, 1, 6, 10, 16, 25, 31, 34] |
| `REG_A[7:0]` | [33, 53, 84, 89, 79, 51, 43, 47] |
| `RAM_rdata[7:0]` | [86, 45, 63, 68, 96, 26, 35, 97] |
| `EQ_FLAG` | 46 |
| `Decoder[0x0..0xC]` | [100, 80, 62, 37, 67, 83, 124, 8, 11, 48, 91, 119, 92] |

---

## Verilog Implementation

A cycle-accurate RTL model of the CPU in `src/cpu.v`.

**Design correspondence to Logisim:**

| Logisim component | Verilog |
|-------------------|---------|
| Counter (PC) | `reg [7:0] pc` |
| ROM 256×12b | `reg [11:0] rom [0:255]` + `$readmemh` |
| RAM 256×8b | `reg [7:0] ram [0:255]` |
| Register A | `reg [7:0] reg_a` |
| Register OUT1 | `output reg [7:0] out1` |
| Register OUT2 | `output reg [7:0] out2` |
| D Flip-Flop (Equal Flag) | `reg eq_flag` |
| 8× XOR + 8-input NOR | `(reg_a == operand)` |
| 8× NAND gate | `~(reg_a & operand)` |
| Tri-state bus (5 drivers/bit) | `always @(*) case(opcode) ...` mux |
| AND-gate instruction decoder | `case(opcode)` in sequential block |

All execution is single-cycle: every `posedge clk` fetches, decodes, executes, and writes back.

### Simulating with Icarus Verilog

```bash
cd src
make          # generate rom_init.mem, compile, run simulation
make wave     # open waveform in GTKWave (requires gtkwave)
make clean
```

Or manually:

```bash
cd src
iverilog -g2012 -Wall -o cpu_sim tb_cpu.v cpu.v
./cpu_sim
```

**Expected output:**

```
--- simulation start ---

Welcome to the UselessOS v7.3
By Danijel Korent

Shell:> help

Available commands:

   help - prints this message

Shell:>

--- simulation done at cycle 12003 ---
```

**Testbench features (`tb_cpu.v`):**
- Injects keyboard input `"help\n"` character by character
- Detects character consumption by watching opcode `0x3` (`mov a, in2`) via hierarchical reference
- Captures TTY output (samples `out1` every cycle when `out2 == 0x01 && out1 != 0x00`)
- Dumps full waveform to `cpu_sim.vcd`
- Terminates after 12 000 cycles

**ROM init file (`src/rom_init.mem`):** Generated from `asm/useless_OS.hex` by the Makefile. One 12-bit hex value per line, 256 entries, in `$readmemh` format.

---

## Logisim Simulation

1. Download [Logisim](http://www.cburch.com/logisim/download.html)
2. Open `design/CPU_design.circ`
3. **Simulate → Ticks Enabled** (starts the clock)
4. Click the **Keyboard** element below the "Keyboard input" label
5. Type `help` and press Enter

---

## Repository Layout

| Directory | Contents |
|-----------|----------|
| `asm/` | Assembly sources — `useless_OS.asm` is the canonical ROM program |
| `design/` | Logisim circuit (`CPU_design.circ`) and schematic screenshot |
| `tools/` | Python toolchain: assembler, disassembler, netlist extractor, simulator |
| `src/` | Verilog RTL, UART modules, top-levels, testbenches, simulation Makefile |
| `fpga/` | Synthesis projects: Quartus (Cyclone II/IV), Vivado (Arty A7), open-source ECP5 (ULX3S) |
