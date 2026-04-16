ASM_FILES := $(wildcard *.asm)
HEX_FILES := $(ASM_FILES:.asm=.hex)

.PHONY: all clean
all: $(HEX_FILES)

.FORCE:
%.hex: %.asm .FORCE
	python3 assembler.py $< -o $@

# make <stem>  →  assemble <stem>.asm into useless_OS.hex (active ROM)
%: %.asm
	python3 assembler.py $< -o useless_OS.hex
	@echo "Note: assembled $< into useless_OS.hex (active ROM)"

clean:
	rm -f *.hex
