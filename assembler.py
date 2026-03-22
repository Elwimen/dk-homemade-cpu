#!/usr/bin/env python3

import argparse
import re
import sys


REGISTERS = {'a', 'out1', 'out2', 'in1', 'in2'}


def parse_number(token):
    """Parse a number literal: decimal, hex (0x), or character ('x' / '\\n')."""
    token = token.strip()

    if token.startswith("'") and token.endswith("'"):
        inner = token[1:-1]
        escape_map = {'\\n': 0x0a, '\\r': 0x0d, '\\t': 0x09, '\\0': 0x00, '\\\\': ord('\\')}
        if inner in escape_map:
            return escape_map[inner]
        if len(inner) == 1:
            return ord(inner)
        raise ValueError(f"Unknown character literal: {token}")

    if token.startswith("0x") or token.startswith("0X"):
        return int(token, 16)

    return int(token, 10)


def is_ram_ref(token):
    return token.startswith('[') and token.endswith(']')


def get_ram_addr(token):
    return parse_number(token[1:-1])


def resolve(token, labels):
    """Resolve a token (label or literal) to an integer."""
    if token in labels:
        return labels[token]
    return parse_number(token)


def encode(mnemonic, operands, labels, line_num):
    """Encode one instruction to a 12-bit integer."""

    def op(index):
        if index >= len(operands):
            raise ValueError(f"Missing operand {index + 1}")
        return operands[index]

    if mnemonic == 'mov':
        if len(operands) != 2:
            raise ValueError("mov requires exactly two operands")
        dst, src = op(0), op(1)

        if dst == 'out1' and src == 'a':
            return 0x600
        elif dst == 'out1':
            return (0x0 << 8) | (resolve(src, labels) & 0xFF)
        elif dst == 'out2':
            return (0x1 << 8) | (resolve(src, labels) & 0xFF)
        elif dst == 'a' and src == 'in1':
            return 0x200
        elif dst == 'a' and src == 'in2':
            return 0x300
        elif dst == 'a' and is_ram_ref(src):
            return (0x4 << 8) | (get_ram_addr(src) & 0xFF)
        elif is_ram_ref(dst) and src == 'a':
            return (0x5 << 8) | (get_ram_addr(dst) & 0xFF)
        elif dst == 'a':
            return (0x7 << 8) | (resolve(src, labels) & 0xFF)
        else:
            raise ValueError(f"Invalid mov operands: {dst}, {src}")

    elif mnemonic == 'nand':
        if len(operands) != 2 or op(0) != 'a':
            raise ValueError("nand syntax: nand a, <imm>")
        return (0x8 << 8) | (resolve(op(1), labels) & 0xFF)

    elif mnemonic == 'cmp':
        if len(operands) != 2 or op(0) != 'a':
            raise ValueError("cmp syntax: cmp a, <imm>")
        return (0x9 << 8) | (resolve(op(1), labels) & 0xFF)

    elif mnemonic == 'jmp':
        if len(operands) != 1:
            raise ValueError("jmp requires exactly one operand")
        return (0xA << 8) | (resolve(op(0), labels) & 0xFF)

    elif mnemonic == 'je':
        if len(operands) != 1:
            raise ValueError("je requires exactly one operand")
        return (0xB << 8) | (resolve(op(0), labels) & 0xFF)

    elif mnemonic == 'jne':
        if len(operands) != 1:
            raise ValueError("jne requires exactly one operand")
        return (0xC << 8) | (resolve(op(0), labels) & 0xFF)

    else:
        raise ValueError(f"Unknown mnemonic: '{mnemonic}'")


def split_operands(operand_str):
    """Split operand string by commas, ignoring commas inside character literals."""
    operands = []
    current = []
    in_char = False

    for ch in operand_str:
        if ch == "'" and not in_char:
            in_char = True
            current.append(ch)
        elif ch == "'" and in_char:
            in_char = False
            current.append(ch)
        elif ch == ',' and not in_char:
            operands.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)

    if current:
        operands.append(''.join(current).strip())

    return operands


def tokenize_line(line, line_num):
    """
    Parse one source line into (label, mnemonic, operands).
    Returns None for blank/comment-only lines.
    Raises ValueError on syntax errors.
    """
    # Strip comment
    comment_pos = line.find(';')
    if comment_pos != -1:
        line = line[:comment_pos]

    line = line.strip()
    if not line:
        return None

    label = None

    # Detect label: identifier followed by colon
    label_match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)', line)
    if label_match:
        label = label_match.group(1)
        line = label_match.group(2).strip()

    if not line:
        return (label, None, [])

    # Split mnemonic from rest
    parts = line.split(None, 1)
    mnemonic = parts[0].lower()

    operands = []
    if len(parts) > 1:
        # Split by comma, but not inside single-quoted character literals
        operands = split_operands(parts[1])

    return (label, mnemonic, operands)


def assemble(source_lines):
    """
    Two-pass assembler.
    Returns a list of 12-bit encoded instructions.
    """

    # --- First pass: collect label addresses ---
    labels = {}
    address = 0

    for line_num, line in enumerate(source_lines, 1):
        result = tokenize_line(line, line_num)
        if result is None:
            continue
        label, mnemonic, _ = result
        if label is not None:
            if label in labels:
                raise ValueError(f"Line {line_num}: Duplicate label '{label}'")
            labels[label] = address
        if mnemonic is not None:
            address += 1

    # --- Second pass: encode instructions ---
    instructions = []
    address = 0

    for line_num, line in enumerate(source_lines, 1):
        result = tokenize_line(line, line_num)
        if result is None:
            continue
        label, mnemonic, operands = result
        if mnemonic is None:
            continue
        try:
            encoded = encode(mnemonic, operands, labels, line_num)
        except ValueError as e:
            raise ValueError(f"Line {line_num}: {e}")
        instructions.append(encoded)
        address += 1

    return instructions


def write_hex_file(instructions, output_file, values_per_line=8):
    """Write instructions in Logisim v2.0 raw hex format."""
    output_file.write("v2.0 raw\n")
    for i in range(0, len(instructions), values_per_line):
        chunk = instructions[i:i + values_per_line]
        output_file.write(" ".join(f"{val:03x}" for val in chunk) + "\n")


def parse_arguments():
    parser = argparse.ArgumentParser(description="Assembler for a custom 8-bit CPU ISA.")
    parser.add_argument("input_file", help="Input assembly source file (.asm)")
    parser.add_argument("-o", "--output_file", help="Output hex file (default: input filename with .hex extension)")
    args = parser.parse_args()

    if args.output_file is None:
        args.output_file = args.input_file.rsplit('.', 1)[0] + ".hex"

    return args


if __name__ == '__main__':
    args = parse_arguments()

    with open(args.input_file, 'r') as f:
        source_lines = f.readlines()

    try:
        instructions = assemble(source_lines)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    with open(args.output_file, 'w', newline='\n') as f:
        write_hex_file(instructions, f)

    print(f"Assembled {len(instructions)} instructions -> {args.output_file}")
