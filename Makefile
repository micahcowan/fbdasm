ROMFILE='Family BASIC (Japan) (v3.0).nes'

.PHONY: all
all: fb3.asm

fb3.asm: fb3.ini
	clever-disasm $(ROMFILE) fb3.ini | sed 's/	*\/\*.*//'  > $@
