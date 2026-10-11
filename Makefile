# Tang Nano 9K — OSS CAD Suite build system
# Device: GW1NR-LV9QN88PC6/I5 (GW1NR-9C, QFN88P)
#
# Usage:
#   make            — build firmware, synthesize, P&R, pack
#   make flash      — load to SRAM  (volatile, lost on power-off)
#   make flash-rom  — write to flash (persistent)
#   make firmware   — build firmware.hex only (without touching the FPGA build)
#   make clean      — remove build/ and firmware build artifacts

DEVICE     := GW1NR-LV9QN88PC6/I5   # full part number  → nextpnr-himbaechel
PACKDEV    := GW1N-9C                 # exact family name → gowin_pack
FAMILY     := GW1N-9C
TOP     := top

SRCS    := $(wildcard src/*.v)
CST     := constraints/tangnano9k.cst
BUILD   := build

JSON    := $(BUILD)/$(TOP).json
ROUTED  := $(BUILD)/$(TOP)_pnr.json
BITFILE := $(BUILD)/$(TOP).fs

# ── PicoRV32 firmware (RV32I) ────────────────────────────────────────────
FW_PREFIX  := riscv64-elf-
FW_CC      := $(FW_PREFIX)gcc
FW_OBJCOPY := $(FW_PREFIX)objcopy
FW_CFLAGS  := -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -Os -Wall -Wextra
FW_LDFLAGS := -Tfirmware/sections.lds -Wl,--no-relax -Wl,--gc-sections
FW_WORDS   := 1024   # must match cpu_ram.v WORDS parameter (4 KB)

FW_ELF := firmware/firmware.elf
FW_BIN := firmware/firmware.bin
FW_HEX := firmware/firmware.hex

.PHONY: all flash flash-rom clean firmware

all: $(BITFILE)

$(BUILD):
	mkdir -p $(BUILD)

# ── Firmware build chain ─────────────────────────────────────────────────
# start.S must be linked first so its _start lands at address 0 (PROGADDR_RESET).
$(FW_ELF): firmware/start.S firmware/main.c firmware/sections.lds
	$(FW_CC) $(FW_CFLAGS) $(FW_LDFLAGS) -o $@ firmware/start.S firmware/main.c

$(FW_BIN): $(FW_ELF)
	$(FW_OBJCOPY) -O binary $< $@

$(FW_HEX): $(FW_BIN) tools/makehex.py
	python3 tools/makehex.py $(FW_BIN) $(FW_WORDS) > $@

firmware: $(FW_HEX)

# 1. Synthesis — depends on firmware.hex because cpu_ram.v reads it via
#    $readmemh at elaboration time; it must exist before yosys runs.
$(JSON): $(SRCS) $(FW_HEX) | $(BUILD)
	yosys -p "read_verilog $(SRCS); synth_gowin -top $(TOP) -json $@"

# 2. Place and route (nextpnr-himbaechel Gowin backend)
$(ROUTED): $(JSON) $(CST)
	nextpnr-himbaechel \
		--json $(JSON) \
		--write $(ROUTED) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

# 3. Pack bitstream
$(BITFILE): $(ROUTED)
	gowin_pack -d $(PACKDEV) -o $@ $(ROUTED)

# Flash to SRAM (use during development — won't survive power cycle)
flash: $(BITFILE)
	openFPGALoader -b tangnano9k $(BITFILE)

# Burn to SPI flash (survives power cycle)
flash-rom: $(BITFILE)
	openFPGALoader -b tangnano9k -f $(BITFILE)

clean:
	rm -rf $(BUILD) firmware/firmware.elf firmware/firmware.bin firmware/firmware.hex
