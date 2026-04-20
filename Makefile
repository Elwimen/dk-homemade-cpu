ASM_FILES    := $(wildcard asm/*.asm)
HEX_FILES    := $(ASM_FILES:.asm=.hex)
FPGA_TARGETS := $(patsubst fpga/%/,%,$(wildcard fpga/*/))
FPGA_ACTIONS := sram flash

_ACTION := $(firstword $(filter $(FPGA_ACTIONS),$(MAKECMDGOALS)))

.PHONY: all clean sram flash

all: $(HEX_FILES)

# ── Assembler ──────────────────────────────────────────────────────────────
.FORCE:
asm/%.hex: asm/%.asm .FORCE
	python3 tools/assembler.py $< -o $@

# make <stem>  →  assemble asm/<stem>.asm into asm/useless_OS.hex (active ROM)
%: asm/%.asm
	python3 tools/assembler.py $< -o asm/useless_OS.hex
	@echo "Note: assembled $< into asm/useless_OS.hex (active ROM)"

# ── FPGA targets ───────────────────────────────────────────────────────────
# Generates for each board in fpga/: <board>  <board>-sram  <board>-flash
# Two-word form also works: make <board> sram|flash

define fpga_rules
.PHONY: $(1) $(1)-sram $(1)-flash
$(1):
	$$(MAKE) -C fpga/$(1) $$(_ACTION)
$(1)-sram:
	$$(MAKE) -C fpga/$(1) sram
$(1)-flash:
	$$(MAKE) -C fpga/$(1) flash
endef

$(foreach t,$(FPGA_TARGETS),$(eval $(call fpga_rules,$(t))))

sram flash: ;

# ── Cleanup ────────────────────────────────────────────────────────────────
clean:
	rm -f asm/*.hex
	$(foreach t,$(FPGA_TARGETS),$(MAKE) -C fpga/$(t) clean;)
