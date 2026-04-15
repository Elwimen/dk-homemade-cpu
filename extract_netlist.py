#!/usr/bin/env python3
"""
extract_netlist.py — Convert a Logisim .circ file to a netlistsvg-compatible JSON.

Produces a Yosys-style JSON with modules/ports/cells describing the block-level
netlist of the CPU, consumable by `netlistsvg input.json -o output.svg`.

Usage:
    python3 extract_netlist.py [file.circ] [-o out.json]
"""

import sys
import json
import argparse
import xml.etree.ElementTree as ET
from collections import defaultdict

# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def parse_pt(s):
    s = s.strip().strip('()')
    x, y = s.split(',')
    return (int(x.strip()), int(y.strip()))

def pt_str(pt):
    return f"({pt[0]},{pt[1]})"

# ---------------------------------------------------------------------------
# Step 1: Build wire nets via flood-fill
# ---------------------------------------------------------------------------

def build_nets(circuit):
    """Return (nets, pt_to_net). nets[i] = frozenset of (x,y) points."""
    adj = defaultdict(set)
    for wire in circuit.findall('wire'):
        a = parse_pt(wire.get('from'))
        b = parse_pt(wire.get('to'))
        adj[a].add(b)
        adj[b].add(a)

    visited = set()
    nets = []
    for start in list(adj):
        if start in visited:
            continue
        net = set()
        stack = [start]
        while stack:
            n = stack.pop()
            if n in visited:
                continue
            visited.add(n)
            net.add(n)
            stack.extend(adj[n] - visited)
        nets.append(frozenset(net))

    pt_to_net = {}
    for i, net in enumerate(nets):
        for pt in net:
            pt_to_net[pt] = i

    return nets, pt_to_net

# ---------------------------------------------------------------------------
# Step 2: Collect components, resolve nearby wire endpoints for multi-pin parts
# ---------------------------------------------------------------------------

LIB = {'0':'Wiring','1':'Gates','2':'Plexers','3':'Arithmetic',
       '4':'Memory','5':'I/O','6':'Base'}

def collect_components(circuit):
    comps = []
    for comp in circuit.findall('comp'):
        name = comp.get('name')
        if name == 'Text':
            continue
        lib   = comp.get('lib', '?')
        loc   = parse_pt(comp.get('loc'))
        attrs = {a.get('name'): a.get('val') for a in comp.findall('a')}
        attrs.pop('contents', None)
        comps.append(dict(name=name, lib=LIB.get(lib, lib), loc=loc, attrs=attrs))
    return comps

def nearby_wire_pts(cx, cy, all_wire_pts, radius=200):
    return [(px, py) for (px, py) in all_wire_pts
            if abs(px-cx) <= radius and abs(py-cy) <= radius]

# ---------------------------------------------------------------------------
# Step 3: Discover multi-bit bus nets for Splitters
#
# For each Splitter, its "bus" side is at loc; individual bit pins are at
# offsets from loc depending on facing and fanout.
# In Logisim, splitter bit pins are spaced 10 units apart from the bus pin.
# ---------------------------------------------------------------------------

def splitter_bit_pins(loc, attrs, all_wire_pts, pt_to_net):
    """
    Return (bus_net, [bit0_net, bit1_net, ...]) for a Splitter.

    Logisim splitter geometry (appear=center, which is used by all splitters here):
      - For east/west facing:  bit pins are at (cx ± 20, cy + (i - n//2)*10)
      - For north/south facing: bit pins are at (cx + (i - n//2)*10, cy ± 20)
    The ± 20 depends on facing direction (east → +20, west → -20, etc.).
    bus_net corresponds to loc itself (component shares pin with co-located part).
    """
    cx, cy  = loc
    fanout  = int(attrs.get('fanout', 2))
    facing  = attrs.get('facing', 'east')

    # Step in facing direction for the bit-pin column/row
    fwd = {'east': (20, 0), 'west': (-20, 0),
           'north': (0, -20), 'south': (0, 20)}
    fx, fy = fwd.get(facing, (20, 0))

    # Perpendicular spread centred on zero: offset = (i - fanout//2) * 10
    bit_pins = []
    for i in range(fanout):
        spread = (i - fanout // 2) * 10
        if facing in ('east', 'west'):
            bp = (cx + fx, cy + spread)
        else:
            bp = (cx + spread, cy + fy)
        bit_pins.append(bp)

    # Match each calculated pin to the nearest actual wire endpoint (within 6 units)
    bit_nets = []
    for bp in bit_pins:
        bpx, bpy = bp
        best, best_d = None, 7
        for (px, py) in all_wire_pts:
            d = abs(px - bpx) + abs(py - bpy)
            if d < best_d:
                best_d = d
                best = (px, py)
        bit_nets.append(pt_to_net.get(best) if best else None)

    # Bus net: loc is the combined-side pin (may not be a wire endpoint if directly
    # coupled to a co-located component, e.g. Counter+Splitter at same loc).
    bus_net = pt_to_net.get(loc)

    return bus_net, bit_nets

# ---------------------------------------------------------------------------
# Step 4: Identify named buses from splitters adjacent to key components
# ---------------------------------------------------------------------------

def find_bus_nets(comps, all_wire_pts, pt_to_net):
    """
    Walk splitters that sit immediately adjacent to key components and extract
    their bit-net arrays.  Returns a dict of logical signal name → [net_ids].
    """
    buses = {}

    # Index splitters by loc for lookup
    splitters = {c['loc']: c for c in comps if c['name'] == 'Splitter'}

    def get_splitter_bits(loc):
        c = splitters.get(loc)
        if c is None:
            return None
        _, bits = splitter_bit_pins(loc, c['attrs'], all_wire_pts, pt_to_net)
        return bits

    # ---- PC output: Counter @ (240,510) co-located east Splitter → bit pins east ----
    # (310,510) west Splitter reconstructs the same bus for ROM address.
    # Both map to the same nets; use (310,510) since it clearly faces the ROM.
    pc_bits = get_splitter_bits((310, 510))
    if pc_bits:
        buses['PC_addr'] = pc_bits   # 8-bit ROM address

    # ---- ROM instruction output: east Splitter @ (450,510) fanout=12 ----
    # bit pins at (470, y): bits [0..11], where bits[11:8]=opcode, bits[7:0]=operand
    rom_sp = get_splitter_bits((450, 510))
    if rom_sp:
        buses['INSTR']   = rom_sp        # full 12-bit instruction
        buses['OPERAND'] = rom_sp[:8]    # bits [7:0]  immediate/address operand
        buses['OPCODE']  = rom_sp[8:12]  # bits [11:8] opcode

    # ---- RAM data output: east Splitter @ (920,490) co-located with RAM ----
    # bit pins at (940, y) going toward the data bus
    ram_sp = get_splitter_bits((920, 490))
    if ram_sp:
        buses['RAM_rdata'] = ram_sp

    # ---- Reg A output: east Splitter @ (1710,490) co-located with Reg A ----
    rega_sp = get_splitter_bits((1710, 490))
    if rega_sp:
        buses['REG_A'] = rega_sp

    # ---- Reg OUT1 output: east Splitter @ (2750,500) ----
    out1_sp = get_splitter_bits((2750, 500))
    if out1_sp:
        buses['OUT1'] = out1_sp

    # ---- Reg OUT2 output: east Splitter @ (2820,620) ----
    # OUT2 drives TTY mode (bits 0 and 1 used); upper bits may be unwired
    out2_sp = get_splitter_bits((2820, 620))
    if out2_sp:
        buses['OUT2'] = out2_sp

    # ---- Data bus (8 nets, each with 5 controlled-buffer outputs) ----
    # These are already identified by net label; we build the array below.

    return buses

# ---------------------------------------------------------------------------
# Step 5: Data-bus bit lanes (8 nets × 5 tri-state drivers each)
# ---------------------------------------------------------------------------

def find_databus_nets(nets, pt_to_net, comps, net_map):
    """Return [net0, net1, ..., net7] for the 8-bit tri-state data bus."""
    bus_candidates = []
    for net_idx, entries in net_map.items():
        cb_count = sum(1 for cname, _, _ in entries if cname == 'Controlled Buffer')
        if cb_count == 5 and len(nets[net_idx]) >= 28:
            bus_candidates.append(net_idx)
    bus_candidates.sort()
    return bus_candidates   # should be exactly 8

# ---------------------------------------------------------------------------
# Step 6: Build the netlistsvg JSON
# ---------------------------------------------------------------------------

def make_netlistsvg(circuit_name, buses, databus, pt_to_net, nets, net_map):
    """
    Construct a Yosys-style JSON dict with high-level cells representing the
    major blocks of the CPU.
    """

    def bus(name, fallback=None):
        """Get list of net IDs for a named bus, or fallback."""
        b = buses.get(name, fallback or [])
        # Replace None with "x" (unconnected) for netlistsvg
        return ["x" if n is None else n for n in b]

    def single(name):
        """Get net IDs list for a single-bit signal from buses dict."""
        b = buses.get(name, [None])
        return ["x" if n is None else n for n in b[:1]]

    # Well-known single-bit nets
    CLK     = pt_to_net.get((690, 30), 999)
    EQ_FLAG = pt_to_net.get((2370, 1130), 998)   # D-FF Q output

    # 8-bit data bus
    DB = databus if len(databus) == 8 else (databus + [None]*(8-len(databus)))
    DB = ["x" if n is None else n for n in DB]

    # Instruction fields
    INSTR   = bus('INSTR',   [None]*12)
    OPERAND = bus('OPERAND', INSTR[:8])
    OPCODE  = bus('OPCODE',  INSTR[8:])

    PC_ADDR = bus('PC_addr', [None]*8)
    RAM_RD  = bus('RAM_rdata', [None]*8)
    REG_A   = bus('REG_A',   [None]*8)
    OUT1    = bus('OUT1',    [None]*8)
    OUT2    = bus('OUT2',    [None]*8)

    # Decoder output nets (one per opcode 0x0..0xC)
    # AND gates at x=630, y = 1690..2410 in steps of 60
    decoder_nets = []
    for opcode in range(13):
        y = 1690 + opcode * 60
        n = pt_to_net.get((630, y))
        decoder_nets.append("x" if n is None else n)

    # CMP result net (NOR gate output at (2310,1080))
    CMP_ZERO = pt_to_net.get((2310, 1080), "x")
    if CMP_ZERO is None:
        CMP_ZERO = "x"

    # NAND unit output nets (8 NAND gates at x=1700, y=580..1000 step 60)
    nand_out = []
    for bit in range(8):
        y = 580 + bit * 60
        n = pt_to_net.get((1700, y))
        nand_out.append("x" if n is None else n)

    # ---- Ports (top-level I/O) ----
    ports = {
        "clk":       {"direction": "input",  "bits": [CLK]},
        "kbd_ready": {"direction": "input",  "bits": ["x"]},
        "kbd_data":  {"direction": "input",  "bits": ["x"]*8},
        "tty_char":  {"direction": "output", "bits": OUT1},
        "tty_mode":  {"direction": "output", "bits": OUT2},
    }

    # ---- Cells ----
    cells = {}

    # Program Counter (8-bit counter)
    cells["PC"] = {
        "type":            "PC",
        "port_directions": {
            "clk":   "input",
            "load":  "input",
            "D":     "input",
            "Q":     "output",
        },
        "connections": {
            "clk":  [CLK],
            "load": [decoder_nets[0xA]],   # JMP loads the PC
            "D":    DB,                    # jump target from data bus
            "Q":    PC_ADDR,
        }
    }

    # Program ROM (256 × 12-bit)
    cells["ROM"] = {
        "type":            "ROM",
        "port_directions": {
            "addr":  "input",
            "instr": "output",
        },
        "connections": {
            "addr":  PC_ADDR,
            "instr": INSTR,
        }
    }

    # Instruction register / decoder
    cells["INSTR_DECODE"] = {
        "type":            "INSTR_DECODE",
        "port_directions": {
            "opcode":    "input",
            "operand":   "input",
            "dec_out":   "output",
        },
        "connections": {
            "opcode":    OPCODE,
            "operand":   OPERAND,
            "dec_out":   decoder_nets,
        }
    }

    # Data RAM (256 × 8-bit)
    cells["RAM"] = {
        "type":            "RAM",
        "port_directions": {
            "clk":   "input",
            "addr":  "input",
            "din":   "input",
            "we":    "input",
            "dout":  "output",
        },
        "connections": {
            "clk":  [CLK],
            "addr": OPERAND,
            "din":  DB,
            "we":   [decoder_nets[0x5]],    # mov [addr], a
            "dout": RAM_RD,
        }
    }

    # Accumulator (Reg A)
    cells["REG_A"] = {
        "type":            "REG_A",
        "port_directions": {
            "clk":  "input",
            "load": "input",
            "D":    "input",
            "Q":    "output",
        },
        "connections": {
            "clk":  [CLK],
            # load when any A-destination instruction fires
            "load": [decoder_nets[0x2]],   # simplified; decoder_nets 2,3,4,7,8 all load A
            "D":    DB,
            "Q":    REG_A,
        }
    }

    # Output register 1 (drives TTY char)
    cells["REG_OUT1"] = {
        "type":            "REG_OUT1",
        "port_directions": {
            "clk":  "input",
            "load": "input",
            "D":    "input",
            "Q":    "output",
        },
        "connections": {
            "clk":  [CLK],
            "load": [decoder_nets[0x0]],   # mov out1, imm  or mov out1, a
            "D":    DB,
            "Q":    OUT1,
        }
    }

    # Output register 2 (TTY mode control)
    cells["REG_OUT2"] = {
        "type":            "REG_OUT2",
        "port_directions": {
            "clk":  "input",
            "load": "input",
            "D":    "input",
            "Q":    "output",
        },
        "connections": {
            "clk":  [CLK],
            "load": [decoder_nets[0x1]],
            "D":    DB,
            "Q":    OUT2,
        }
    }

    # NAND unit (8-bit NAND of Reg A and operand → result back to A)
    cells["NAND_UNIT"] = {
        "type":            "NAND_UNIT",
        "port_directions": {
            "A":    "input",
            "B":    "input",
            "en":   "input",
            "Q":    "output",
        },
        "connections": {
            "A":   REG_A,
            "B":   OPERAND,
            "en":  [decoder_nets[0x8]],
            "Q":   nand_out,
        }
    }

    # CMP unit (8× XOR + 8-input NOR → equal flag)
    cells["CMP_UNIT"] = {
        "type":            "CMP_UNIT",
        "port_directions": {
            "A":    "input",
            "B":    "input",
            "en":   "input",
            "eq":   "output",
        },
        "connections": {
            "A":   REG_A,
            "B":   OPERAND,
            "en":  [decoder_nets[0x9]],
            "eq":  [CMP_ZERO],
        }
    }

    # Equal flag D flip-flop
    cells["EQ_FLAG"] = {
        "type":            "EQ_FLAG",
        "port_directions": {
            "clk":  "input",
            "D":    "input",
            "Q":    "output",
        },
        "connections": {
            "clk":  [CLK],
            "D":    [CMP_ZERO],
            "Q":    [EQ_FLAG],
        }
    }

    # Branch logic (je / jne)
    cells["BRANCH"] = {
        "type":            "BRANCH",
        "port_directions": {
            "eq_flag":  "input",
            "je":       "input",
            "jne":      "input",
            "jmp":      "input",
            "take":     "output",
        },
        "connections": {
            "eq_flag":  [EQ_FLAG],
            "je":       [decoder_nets[0xB]],
            "jne":      [decoder_nets[0xC]],
            "jmp":      [decoder_nets[0xA]],
            "take":     ["x"],            # drives PC load enable
        }
    }

    return {
        "modules": {
            circuit_name: {
                "ports": ports,
                "cells": cells,
            }
        }
    }

# ---------------------------------------------------------------------------
# Step 7: Also dump a human-readable net summary (optional)
# ---------------------------------------------------------------------------

def dump_net_summary(nets, net_map, buses, databus, pt_to_net):
    print("=== NET SUMMARY ===\n")

    # Single named signals
    print("Key single-bit nets:")
    print(f"  CLK      = net {pt_to_net.get((690,30), '?')}")
    print(f"  EQ_FLAG  = net {pt_to_net.get((2370,1130), '?')}")
    print(f"  CMP_ZERO = net {pt_to_net.get((2310,1080), '?')}")
    print()

    # Buses
    print("Key bus nets  [bit0 .. bitN]:")
    for name, nids in sorted(buses.items()):
        print(f"  {name:12s} = {nids}")
    print(f"  {'DATA_BUS':12s} = {databus}")
    print()

    # Decoder
    print("Instruction decoder outputs (opcode → net):")
    for opcode in range(13):
        y = 1690 + opcode * 60
        n = pt_to_net.get((630, y), '?')
        print(f"  [{opcode:X}h] net {n}")
    print()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('input', nargs='?', default='CPU_design.circ',
                    help='Logisim .circ file (default: CPU_design.circ)')
    ap.add_argument('-o', '--output', default='cpu_netlist.json',
                    help='Output JSON file (default: cpu_netlist.json)')
    ap.add_argument('--summary', action='store_true',
                    help='Also print a human-readable net summary to stdout')
    args = ap.parse_args()

    tree    = ET.parse(args.input)
    circuit = tree.getroot().find('circuit')

    nets, pt_to_net = build_nets(circuit)
    all_wire_pts    = set(pt_to_net.keys())
    comps           = collect_components(circuit)

    # Build net_map for databus detection
    net_map = defaultdict(list)
    for comp in comps:
        loc = comp['loc']
        n   = pt_to_net.get(loc)
        if n is not None:
            net_map[n].append((comp['name'], 'pin', loc))

    buses   = find_bus_nets(comps, all_wire_pts, pt_to_net)
    databus = find_databus_nets(nets, pt_to_net, comps, net_map)

    if args.summary:
        dump_net_summary(nets, net_map, buses, databus, pt_to_net)

    netlist = make_netlistsvg('homemade_cpu', buses, databus,
                              pt_to_net, nets, net_map)

    with open(args.output, 'w') as f:
        json.dump(netlist, f, indent=2)

    print(f"Written {args.output}  "
          f"({len(netlist['modules']['homemade_cpu']['cells'])} cells, "
          f"{len(nets)} nets)")

if __name__ == '__main__':
    main()
