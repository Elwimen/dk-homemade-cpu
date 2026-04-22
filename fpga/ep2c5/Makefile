QUARTUS  := /home/dmj/.local/altera/13.0sp1/quartus/bin
PROJECT  := dkcpu
ROM_ASM  := ../../asm/useless_OS.asm
ROM_HEX  := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: $(PROJECT).sof

$(ROM_HEX): $(ROM_ASM)
	python3 ../../tools/assembler.py $< -o $@

rom_init.mem: $(ROM_HEX)
	python3 -c "\
lines = open('$(ROM_HEX)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('rom_init.mem', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated rom_init.mem (256 entries)"

$(PROJECT).sof: rom_init.mem $(PROJECT).qpf $(PROJECT).qsf
	$(QUARTUS)/quartus_sh --flow compile $(PROJECT)

$(PROJECT).pof: $(PROJECT).sof
	$(QUARTUS)/quartus_cpf -c -d EPCS4 $< $@

sram:
	@test -f $(PROJECT).sof || $(MAKE) $(PROJECT).sof
	$(QUARTUS)/quartus_pgm -c "USB-Blaster" -m jtag -o "p;$(PROJECT).sof"

flash:
	@test -f $(PROJECT).pof || $(MAKE) $(PROJECT).pof
	$(QUARTUS)/quartus_pgm -c "USB-Blaster" flash_as.cdf

clean:
	rm -rf output_files db incremental_db greybox_tmp rom_init.mem $(PROJECT).pof
	rm -f $(PROJECT).done $(PROJECT).jdi $(PROJECT).pin $(PROJECT).sof \
	      $(PROJECT).*.rpt $(PROJECT).*.smsg $(PROJECT).*.summary
