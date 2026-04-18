ASM_FILES := $(wildcard asm/*.asm)
HEX_FILES := $(ASM_FILES:.asm=.hex)

.PHONY: all clean
all: $(HEX_FILES)

.FORCE:
asm/%.hex: asm/%.asm .FORCE
	python3 tools/assembler.py $< -o $@

# make <stem>  →  assemble asm/<stem>.asm into asm/useless_OS.hex (active ROM)
%: asm/%.asm
	python3 tools/assembler.py $< -o asm/useless_OS.hex
	@echo "Note: assembled $< into asm/useless_OS.hex (active ROM)"

clean:
	rm -f asm/*.hex
