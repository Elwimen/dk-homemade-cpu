BOARD   := arty_a7_100t
BITFILE := dkcpu.bit
ROM_ASM := ../../asm/useless_OS.asm
ROM_HEX := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: $(BITFILE)

$(ROM_HEX): $(ROM_ASM)
	python3 ../../tools/assembler.py $< -o $@

rom_init.mem: $(ROM_HEX)
	python3 -c "\
lines = open('$(ROM_HEX)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('rom_init.mem', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated rom_init.mem (256 entries)"

$(BITFILE): rom_init.mem build.tcl arty_a7_100.xdc
	vivado -mode batch -source build.tcl

sram:
	@test -f $(BITFILE) || $(MAKE) $(BITFILE)
	openFPGALoader -b $(BOARD) $(BITFILE)

flash:
	@test -f $(BITFILE) || $(MAKE) $(BITFILE)
	openFPGALoader -b $(BOARD) --write-flash $(BITFILE)

clean:
	rm -rf vivado.jou vivado.log vivado_*.backup.jou vivado_*.backup.log \
	       clockInfo.txt .Xil rom_init.mem $(BITFILE)
