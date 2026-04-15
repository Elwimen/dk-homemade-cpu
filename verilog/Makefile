SIM_EXE  := cpu_sim
ISIM_EXE := cpu_isim
VCD      := cpu_sim.vcd
ROM_MEM  := rom_init.mem
ROM_SRC  := ../useless_OS.hex

.PHONY: all sim isim wave clean

all: sim

# Convert Logisim hex → $readmemh format
$(ROM_MEM): $(ROM_SRC)
	python3 -c "\
lines = open('$(ROM_SRC)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('$(ROM_MEM)', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated $(ROM_MEM) (256 entries)"

# Compile automated testbench
$(SIM_EXE): cpu.v tb_cpu.v $(ROM_MEM)
	iverilog -g2012 -Wall -o $(SIM_EXE) tb_cpu.v cpu.v

# Compile interactive testbench
$(ISIM_EXE): cpu.v tb_interactive.v $(ROM_MEM)
	iverilog -g2012 -o $(ISIM_EXE) tb_interactive.v cpu.v

# Run automated simulation
sim: $(SIM_EXE)
	./$(SIM_EXE)

# Run interactive simulation (connects stdin/stdout to the CPU's keyboard/TTY)
isim: $(ISIM_EXE)
	./$(ISIM_EXE)

# Open waveform (requires gtkwave)
wave: $(VCD)
	gtkwave $(VCD) &

clean:
	rm -f $(SIM_EXE) $(ISIM_EXE) $(VCD) $(ROM_MEM)
