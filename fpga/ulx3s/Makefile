SRCS    := ../../src/cpu.v ../../src/uart_rx.v ../../src/uart_tx.v ../../src/top_ulx3s.v
ROM_MEM := rom_init.mem
ROM_SRC := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: ulx3s.bit

# Convert Logisim hex → $readmemh format (shared with src/Makefile target)
$(ROM_MEM): $(ROM_SRC)
	python3 -c "\
lines = open('$(ROM_SRC)').readlines(); \
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

sram: ulx3s.bit
	openFPGALoader -b ulx3s $<

flash: ulx3s.bit
	openFPGALoader -b ulx3s --write-flash $<

clean:
	rm -f ulx3s.json ulx3s.config ulx3s.bit rom_init.mem
