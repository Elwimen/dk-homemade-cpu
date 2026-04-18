# CLAUDE.md — dkcpu

Homemade 8-bit Harvard CPU in Verilog, targeting the EP2C5T144C8N (Cyclone II) mini board.

## Architecture

Harvard: separate 256×12-bit ROM (program) and 256×8-bit RAM (data).  
8-bit data path, 8-bit PC, 12-bit instructions (4-bit opcode + 8-bit operand).  
Single-cycle execution except `mov a, [addr]` which takes 2 cycles (RAM read is registered to enable M4K block RAM inference).

### ISA

| Opcode | Mnemonic | Operation |
|--------|----------|-----------|
| 0x0 | `mov out1, imm` | out1 ← imm |
| 0x1 | `mov out2, imm` | out2 ← imm |
| 0x2 | `mov a, in1` | a ← keyboard-ready flag |
| 0x3 | `mov a, in2` | a ← keyboard character |
| 0x4 | `mov a, [addr]` | a ← RAM[addr]  *(2 cycles)* |
| 0x5 | `mov [addr], a` | RAM[addr] ← a |
| 0x6 | `mov out1, a` | out1 ← a |
| 0x7 | `mov a, imm` | a ← imm |
| 0x8 | `nand a, imm` | a ← ~(a & imm) |
| 0x9 | `cmp a, imm` | eq_flag ← (a == imm) |
| 0xA | `jmp addr` | pc ← addr |
| 0xB | `je addr` | pc ← addr if eq_flag |
| 0xC | `jne addr` | pc ← addr if !eq_flag |

### out2 mode values

| Value | Meaning |
|-------|---------|
| 0x00 | off |
| 0x01 | print out1 over UART |
| 0x02 | echo keyboard character |
| 0xFF | halt CPU |

## Key files

| File | Purpose |
|------|---------|
| `cpu.v` | CPU core — datapath, opcodes, load stall |
| `top.v` | Top-level: CPU + UART RX/TX + LEDs + reset sync |
| `uart_rx.v` | 8N1 UART receiver, 9600 baud @ 50 MHz (CLKS_PER_BIT=5208) |
| `uart_tx.v` | 8N1 UART transmitter, 9600 baud @ 50 MHz |
| `rom_init.mem` | ROM contents in `$readmemh` hex format (256 × 12-bit) |
| `Makefile` | Simulation targets (see below) |
| `tb_cpu.v` | Automated testbench — injects "help\n" / "exit\n", checks halt |
| `tb_interactive.v` | Interactive testbench — stdin/stdout wired to CPU keyboard/TTY |
| `../fpga/quartus/dkcpu.qpf` | Quartus project file |
| `../fpga/quartus/dkcpu.qsf` | Pin assignments + source file list |
| `../fpga/quartus/flash_as.cdf` | Active Serial flash descriptor (programs EPCS4) |

## ROM program

`rom_init.mem` is generated from `../asm/useless_OS.hex` (Logisim hex format) by the Makefile.  
It implements a fake Linux boot sequence ending with a `root@cpu:~#` prompt and a simple command interpreter.

To regenerate after editing the Logisim source:
```sh
make rom_init.mem
```

## Simulation

Uses Icarus Verilog. Run from the `dkcpu/` directory:

```sh
make sim     # automated testbench — runs to halt, prints TTY output
make isim    # interactive — stdin/stdout connected to CPU in real time
make wave    # open last VCD in GTKWave
make clean   # remove built artifacts
```

The testbench simulates against `cpu.v` directly (not `top.v`); UART and LED logic are not exercised in sim.

## Synthesis & flashing (Quartus II 13.0sp1)

Quartus binary: `/home/dmj/.local/altera/13.0sp1/quartus/bin/`

```sh
# Full compile (run from repo root)
quartus_sh --flow compile fpga/quartus/dkcpu

# Convert SOF → POF for EPCS4
quartus_cpf -c -d EPCS4 fpga/quartus/dkcpu.sof fpga/quartus/dkcpu.pof

# Flash to board (Active Serial — persistent across power cycles)
quartus_pgm fpga/quartus/flash_as.cdf
```

Programmer: USB-Blaster. Device: EP2C5T144C8N. Config flash: EPCS4.

## Pin assignments

| Signal | Pin | Notes |
|--------|-----|-------|
| `clk` | PIN_17 | 50 MHz onboard oscillator |
| `rst_n` | PIN_144 | Active-low button, weak pull-up |
| `uart_tx` | PIN_73 | UART TX, 9600 8N1 |
| `uart_rx` | PIN_74 | UART RX, 9600 8N1, weak pull-up |
| `led_cpu` | PIN_3 | CPU status: off=halted, on=running, blink=error |
| `led_tx` | PIN_7 | Mirrors UART TX line |
| `led_rx` | PIN_9 | Mirrors UART RX line |

All LEDs are active-low.

## Resource usage (last compile)

| Resource | Used | Total | % |
|----------|------|-------|---|
| Logic elements | 540 | 4,608 | 12% |
| Registers | ~125 | 4,608 | ~3% |
| Memory bits | 2,048 | 119,808 | 2% |
| Pins | 7 | 89 | 8% |

Data RAM (256×8) is inferred as M4K block RAM. Program ROM is in LEs (async read).

## ULX3S (Radiona) — LFE5U-12F ECP5

Top-level: `top_ulx3s.v`. Uses 25 MHz oscillator, active-high reset (btn[0]), active-high LEDs, 9600 8N1 UART via FTDI USB chip (`CLKS_PER_BIT=2604`).

Toolchain: yosys + nextpnr-ecp5 + ecppack + openFPGALoader (all open-source).

```sh
cd fpga/ulx3s
make          # synthesise → place & route → pack bitstream
make flash    # program via openFPGALoader
```

Connect after flashing: `picocom -b 9600 /dev/ttyUSB0`

Reset: hold btn[0] (PWR button, pin R1).

| Signal | Pin | Notes |
|--------|-----|-------|
| `clk_25mhz` | G2 | 25 MHz onboard oscillator |
| `rst` | R1 | btn[0], active-high |
| `uart_tx` | L4 | FPGA → ftdi_rxd, 9600 8N1 |
| `uart_rx` | M1 | ftdi_txd → FPGA, 9600 8N1 |
| `led[0]` | B2 | CPU status: off=halted, on=running, blink=error |
| `led[1]` | C2 | Mirrors UART TX (active-high = activity) |
| `led[2]` | C1 | Mirrors UART RX (active-high = activity) |

All LEDs are active-high.
