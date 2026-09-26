# Tang Nano 9K — OSS CAD Suite build system
# Device: GW1NR-LV9QN88PC6/I5 (GW1NR-9C, QFN88P)
#
# Usage:
#   make            — synthesize, P&R, pack
#   make flash      — load to SRAM  (volatile, lost on power-off)
#   make flash-rom  — write to flash (persistent)
#   make clean      — remove build/

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

.PHONY: all flash flash-rom clean

all: $(BITFILE)

$(BUILD):
	mkdir -p $(BUILD)

# 1. Synthesis
$(JSON): $(SRCS) | $(BUILD)
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
	rm -rf $(BUILD)
