#!/usr/bin/env python3
"""
cpu_sim.py — Interactive simulator for the homemade 8-bit CPU.

Loads the ROM from a Logisim hex file and runs the CPU cycle by cycle,
connecting TTY output to stdout and keyboard input to stdin.

Usage:
    python3 cpu_sim.py                        # loads useless_OS.hex
    python3 cpu_sim.py <rom.hex>              # loads a specific ROM image
    python3 cpu_sim.py --trace                # print every instruction executed
    python3 cpu_sim.py --max-cycles N         # stop after N cycles (default: unlimited)
"""

import sys
import os
import argparse
import select
import termios
import tty


# ---------------------------------------------------------------------------
# ROM loader (Logisim v2.0 raw format)
# ---------------------------------------------------------------------------

def load_rom(path):
    with open(path) as f:
        lines = f.readlines()
    if not lines or lines[0].strip() != 'v2.0 raw':
        raise ValueError(f"{path}: not a Logisim hex file (missing 'v2.0 raw' header)")
    values = []
    for line in lines[1:]:
        for tok in line.strip().split():
            if tok:
                values.append(int(tok, 16))
    # Pad to 256 entries with NOPs (0x000 = mov out1, 0x00 — harmless)
    while len(values) < 256:
        values.append(0x000)
    return values[:256]


# ---------------------------------------------------------------------------
# CPU state
# ---------------------------------------------------------------------------

class CPU:
    def __init__(self, rom):
        self.rom     = rom          # list of 256 × 12-bit ints
        self.ram     = [0] * 256    # 256 × 8-bit bytes
        self.pc      = 0            # 8-bit program counter
        self.reg_a   = 0            # 8-bit accumulator
        self.out1    = 0            # 8-bit TTY char register
        self.out2    = 0            # 8-bit TTY mode register
        self.eq_flag = 0            # 1-bit equal flag
        self.cycle   = 0

    def step(self, in1, in2):
        """
        Execute one clock cycle.
        in1: keyboard-ready flag (0 or 1)
        in2: keyboard character (0–255)
        Returns (new_out1, new_out2) after this cycle's register writes.
        """
        instr   = self.rom[self.pc] & 0xFFF
        opcode  = (instr >> 8) & 0xF
        operand = instr & 0xFF

        # Data-bus mux (combinational)
        if   opcode == 0x0: data_bus = operand
        elif opcode == 0x1: data_bus = operand
        elif opcode == 0x2: data_bus = in1 & 0xFF
        elif opcode == 0x3: data_bus = in2 & 0xFF
        elif opcode == 0x4: data_bus = self.ram[operand]
        elif opcode == 0x6: data_bus = self.reg_a
        elif opcode == 0x7: data_bus = operand
        elif opcode == 0x8: data_bus = (~(self.reg_a & operand)) & 0xFF
        else:               data_bus = 0

        # PC update
        if   opcode == 0xA:
            next_pc = operand
        elif opcode == 0xB:
            next_pc = operand if self.eq_flag else (self.pc + 1) & 0xFF
        elif opcode == 0xC:
            next_pc = operand if not self.eq_flag else (self.pc + 1) & 0xFF
        else:
            next_pc = (self.pc + 1) & 0xFF

        # Register and RAM writes
        if   opcode == 0x0: self.out1  = data_bus
        elif opcode == 0x1: self.out2  = data_bus
        elif opcode == 0x2: self.reg_a = data_bus
        elif opcode == 0x3: self.reg_a = data_bus
        elif opcode == 0x4: self.reg_a = data_bus
        elif opcode == 0x5: self.ram[operand] = self.reg_a
        elif opcode == 0x6: self.out1  = data_bus
        elif opcode == 0x7: self.reg_a = data_bus
        elif opcode == 0x8: self.reg_a = data_bus
        elif opcode == 0x9: self.eq_flag = 1 if (self.reg_a == operand) else 0

        self.pc    = next_pc
        self.cycle += 1
        return self.out1, self.out2


OPCODE_NAMES = {
    0x0: 'mov out1, imm', 0x1: 'mov out2, imm',
    0x2: 'mov a, in1',    0x3: 'mov a, in2',
    0x4: 'mov a, [addr]', 0x5: 'mov [addr], a',
    0x6: 'mov out1, a',   0x7: 'mov a, imm',
    0x8: 'nand a, imm',   0x9: 'cmp a, imm',
    0xA: 'jmp addr',      0xB: 'je addr',
    0xC: 'jne addr',
}

def disasm(instr):
    op  = (instr >> 8) & 0xF
    imm = instr & 0xFF
    name = OPCODE_NAMES.get(op, f'??? ({op:X}h)')
    return f"{instr:03X}  {name.replace('imm', f'0x{imm:02X}').replace('addr', f'0x{imm:02X}')}"


# ---------------------------------------------------------------------------
# Interactive runner
# ---------------------------------------------------------------------------

class KeyboardBuffer:
    """Line-buffered stdin reader that releases characters one at a time."""
    def __init__(self):
        self._buf = []

    def has_char(self):
        return len(self._buf) > 0

    def peek_char(self):
        return self._buf[0] if self._buf else None

    def consume_char(self):
        return self._buf.pop(0) if self._buf else None

    def push_line(self, line):
        for ch in line:
            self._buf.append(ord(ch))


def run_interactive(rom_path, trace=False, max_cycles=None):
    rom = load_rom(rom_path)
    cpu = CPU(rom)
    kbd = KeyboardBuffer()

    # Put terminal in raw mode so characters are available immediately
    # (no need to press Enter for the simulator to receive them).
    # The CPU's shell is line-oriented anyway, so we also handle echoing.
    old_settings = None
    if sys.stdin.isatty():
        old_settings = termios.tcgetattr(sys.stdin)
        tty.setraw(sys.stdin)

    prev_out1 = 0
    prev_out2 = 0

    try:
        while True:
            if max_cycles is not None and cpu.cycle >= max_cycles:
                sys.stderr.write(f"\n[stopped after {cpu.cycle} cycles]\n")
                break

            # ------------------------------------------------------------------
            # Keyboard: determine in1 / in2 for this cycle
            # ------------------------------------------------------------------
            in1 = 1 if kbd.has_char() else 0
            in2 = kbd.peek_char() if kbd.has_char() else 0

            # ------------------------------------------------------------------
            # When the CPU is about to execute "mov a, in1" (opcode 0x2) and
            # in1 is 0, try to read from stdin to fill the keyboard buffer.
            # This is the only point where we block — matching the real hardware
            # behaviour where the CPU polls until a character is ready.
            # ------------------------------------------------------------------
            instr   = rom[cpu.pc] & 0xFFF
            opcode  = (instr >> 8) & 0xF

            if opcode == 0x2 and not kbd.has_char():
                # CPU is polling for keyboard input and buffer is empty — read
                if sys.stdin.isatty():
                    # Raw mode: read char-by-char, handle Enter and Backspace
                    line = _read_line_raw(sys.stdin)
                else:
                    line = sys.stdin.readline()
                    if not line:   # EOF (Ctrl-D / end of pipe)
                        break
                kbd.push_line(line)
                in1 = 1 if kbd.has_char() else 0
                in2 = kbd.peek_char() if kbd.has_char() else 0

            # ------------------------------------------------------------------
            # Execute one cycle
            # ------------------------------------------------------------------
            if trace:
                sys.stderr.write(
                    f"  [{cpu.cycle:6d}] PC={cpu.pc:02X}  {disasm(instr)}"
                    f"  A={cpu.reg_a:02X}  EQ={cpu.eq_flag}"
                    f"  in1={in1}\n"
                )

            new_out1, new_out2 = cpu.step(in1, in2)

            # TTY output: character is displayed when out2=1 and out1 is non-null
            if new_out2 == 0x01 and new_out1 != 0x00:
                ch = chr(new_out1)
                # In raw mode the ONLCR output translation is disabled, so \n
                # only moves the cursor down without returning to column 0.
                # Emit \r\n so the terminal behaves normally.
                if old_settings is not None and ch == '\n':
                    ch = '\r\n'
                sys.stdout.write(ch)
                sys.stdout.flush()

            # Consume keyboard character when CPU executes "mov a, in2"
            if opcode == 0x3 and in1:
                kbd.consume_char()

            prev_out1 = new_out1
            prev_out2 = new_out2

    except KeyboardInterrupt:
        sys.stdout.write("\n")
    finally:
        if old_settings is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)


def _read_line_raw(stdin):
    """
    Read a line of input in raw terminal mode.
    Handles printable chars, Enter (\r → \n), and Backspace.
    Returns the completed line including the trailing '\n'.
    """
    line = []
    while True:
        ch = stdin.read(1)
        if not ch:
            break
        if ch in ('\r', '\n'):
            sys.stdout.write('\r\n')
            sys.stdout.flush()
            line.append('\n')
            break
        elif ch in ('\x7f', '\x08'):  # Backspace / Delete
            if line:
                line.pop()
                sys.stdout.write('\b \b')
                sys.stdout.flush()
        elif ch == '\x03':            # Ctrl-C
            raise KeyboardInterrupt
        elif ch == '\x04':            # Ctrl-D (EOF)
            break
        elif ch >= ' ':               # printable
            line.append(ch)
            sys.stdout.write(ch)
            sys.stdout.flush()
    return ''.join(line)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description='Interactive simulator for the homemade 8-bit CPU.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    ap.add_argument('rom', nargs='?', default='useless_OS.hex',
                    help='ROM image in Logisim v2.0 raw format (default: useless_OS.hex)')
    ap.add_argument('--trace', action='store_true',
                    help='Print every instruction to stderr')
    ap.add_argument('--max-cycles', type=int, default=None,
                    help='Stop after N cycles')
    args = ap.parse_args()

    run_interactive(args.rom, trace=args.trace, max_cycles=args.max_cycles)


if __name__ == '__main__':
    main()
