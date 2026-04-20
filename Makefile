ASM_FILES    := $(wildcard asm/*.asm)
HEX_FILES    := $(ASM_FILES:.asm=.hex)
FPGA_TARGETS := $(patsubst fpga/%/,%,$(wildcard fpga/*/))

.PHONY: all clean $(FPGA_TARGETS) \
        $(addsuffix -sram,$(FPGA_TARGETS)) \
        $(addsuffix -flash,$(FPGA_TARGETS))

all: $(HEX_FILES)

# ── Assembler ──────────────────────────────────────────────────────────────
.FORCE:
asm/%.hex: asm/%.asm .FORCE
	python3 tools/assembler.py $< -o $@

# make <stem>  →  assemble asm/<stem>.asm into asm/useless_OS.hex (active ROM)
%: asm/%.asm
	python3 tools/assembler.py $< -o asm/useless_OS.hex
	@echo "Note: assembled $< into asm/useless_OS.hex (active ROM)"

# ── FPGA targets (auto-discovered from fpga/ subfolders) ───────────────────
# make <board>        — build bitstream
# make <board>-sram   — build + program SRAM (volatile)
# make <board>-flash  — build + program flash (persistent)

$(FPGA_TARGETS): %:
	$(MAKE) -C fpga/$@

$(addsuffix -sram,$(FPGA_TARGETS)): %-sram:
	$(MAKE) -C fpga/$* sram

$(addsuffix -flash,$(FPGA_TARGETS)): %-flash:
	$(MAKE) -C fpga/$* flash

# ── Cleanup ────────────────────────────────────────────────────────────────
clean:
	rm -f asm/*.hex
