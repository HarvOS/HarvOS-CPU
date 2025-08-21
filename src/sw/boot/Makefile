# Minimal build for hello_counter -> hello.hex
# Requires: riscv32-unknown-elf-gcc + objcopy + python3
CROSS ?= riscv32-unknown-elf
CC    := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
CFLAGS := -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -Os -ffreestanding
LDFLAGS:= -T link.ld -nostdlib -nostartfiles -Wl,--gc-sections

all: hello.hex

hello.elf: hello_counter.S link.ld
\t$(CC) $(CFLAGS) hello_counter.S -o $@ $(LDFLAGS)

hello.bin: hello.elf
\t$(OBJCOPY) -O binary $< $@

hello.hex: hello.bin ../tools/bin2hex.py
\tpython3 ../tools/bin2hex.py $< $@

clean:
\trm -f hello.elf hello.bin hello.hex
