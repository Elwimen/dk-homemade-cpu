QUARTUS  := /home/dmj/.local/altera/13.0sp1/quartus/bin
PROJECT  := dkcpu
ROM_SRC  := ../../asm/useless_OS.hex

.PHONY: all sram flash clean

all: output_files/$(PROJECT).sof

rom_init.mem: $(ROM_SRC)
	python3 -c "\
lines = open('$(ROM_SRC)').readlines(); \
vals = [v for line in lines[1:] for v in line.split() if v]; \
vals += ['000'] * (256 - len(vals)); \
open('rom_init.mem', 'w').write('\n'.join(vals) + '\n')"
	@echo "Generated rom_init.mem (256 entries)"

output_files/$(PROJECT).sof: rom_init.mem $(PROJECT).qpf $(PROJECT).qsf
	$(QUARTUS)/quartus_sh --flow compile $(PROJECT)

$(PROJECT).pof: output_files/$(PROJECT).sof
	$(QUARTUS)/quartus_cpf -c -d EPCS4 $< $@

sram: output_files/$(PROJECT).sof
	openFPGALoader $<

flash: $(PROJECT).pof
	$(QUARTUS)/quartus_pgm flash_as.cdf

clean:
	rm -rf output_files db incremental_db greybox_tmp rom_init.mem $(PROJECT).pof
	rm -f $(PROJECT).done $(PROJECT).jdi $(PROJECT).pin $(PROJECT).sof \
	      $(PROJECT).*.rpt $(PROJECT).*.smsg $(PROJECT).*.summary
