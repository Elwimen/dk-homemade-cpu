BOARD   := arty_a7_100t
BITFILE := dkcpu.bit
ROM_SRC := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: $(BITFILE)

rom_init.mem: $(ROM_SRC)
	python3 -c "\
lines = open('$(ROM_SRC)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('rom_init.mem', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated rom_init.mem (256 entries)"

$(BITFILE): rom_init.mem build.tcl arty_a7_100.xdc
	vivado -mode batch -source build.tcl

sram: $(BITFILE)
	openFPGALoader -b $(BOARD) $(BITFILE)

flash: $(BITFILE)
	openFPGALoader -b $(BOARD) --write-flash $(BITFILE)

clean:
	rm -rf vivado.jou vivado.log .Xil rom_init.mem $(BITFILE)
