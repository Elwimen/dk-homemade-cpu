SRCS    := ../../src/cpu.v ../../src/uart_rx.v ../../src/uart_tx.v ../../src/top_ulx3s.v
ROM_MEM := rom_init.mem
ROM_ASM := ../../asm/useless_OS.asm
ROM_HEX := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: ulx3s.bit

$(ROM_HEX): $(ROM_ASM)
	python3 ../../tools/assembler.py $< -o $@

$(ROM_MEM): $(ROM_HEX)
	python3 -c "\
lines = open('$(ROM_HEX)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('$(ROM_MEM)', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated $(ROM_MEM) (256 entries)"

ulx3s.json: $(SRCS) $(ROM_MEM)
	yosys -p "synth_ecp5 -top top_ulx3s -json $@" $(SRCS)

ulx3s.config: ulx3s.json ulx3s.lpf
	nextpnr-ecp5 --12k --package CABGA381 --lpf ulx3s.lpf --json ulx3s.json --textcfg $@

ulx3s.bit: ulx3s.config
	ecppack ulx3s.config $@

sram:
	@test -f ulx3s.bit || $(MAKE) ulx3s.bit
	openFPGALoader -b ulx3s ulx3s.bit

flash:
	@test -f ulx3s.bit || $(MAKE) ulx3s.bit
	openFPGALoader -b ulx3s --write-flash ulx3s.bit

clean:
	rm -f ulx3s.json ulx3s.config ulx3s.bit rom_init.mem
