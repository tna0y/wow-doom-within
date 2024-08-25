
VERSION ?= dev
WOWVER ?= 11002


CC=/opt/toolchains/riscv32/bin/riscv32-unknown-elf-gcc 

PYTHON = python3
ELF2LUA = ./risc-v-wow-emu/tools/elf2lua.py
ELF2LUA_TEMPLATE = dynamicload.lua.j2

ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

BUILD_DIR = $(ROOT_DIR)/build
BUILD_BIN_DIR = $(BUILD_DIR)/bin
OBJDIR = $(BUILD_DIR)/obj
OUTPUT = $(BUILD_BIN_DIR)/doomgeneric

ADDON_NAME = DoomWithin
ADDON_BUILD_DIR = $(BUILD_DIR)/$(ADDON_NAME)


all: release

doomgeneric:
	mkdir -p $(OBJDIR)
	mkdir -p $(BUILD_BIN_DIR)
	$(MAKE) -C doomgeneric -f Makefile.riscv32 OBJDIR=$(OBJDIR) OUTPUT=$(OUTPUT) CC=$(CC)

doomgeneric_lua: doomgeneric
	cat $(OUTPUT) | $(PYTHON) $(ELF2LUA) doom $(ELF2LUA_TEMPLATE) > $(BUILD_BIN_DIR)/doomgeneric.lua

addon: doomgeneric_lua
	mkdir -p $(ADDON_BUILD_DIR)
	cp -r risc-v-wow-emu/src/* $(ADDON_BUILD_DIR)
	cp $(BUILD_BIN_DIR)/doomgeneric.lua $(ADDON_BUILD_DIR)/doomgeneric.lua
	cp -r src/* $(ADDON_BUILD_DIR)

	echo "## Interface: $(WOWVER)" > $(ADDON_BUILD_DIR)/$(ADDON_NAME).toc
	echo "## Title: $(ADDON_NAME)" >> $(ADDON_BUILD_DIR)/$(ADDON_NAME).toc	
	echo "## Version: $(VERSION)" >> $(ADDON_BUILD_DIR)/$(ADDON_NAME).toc
	find $(ADDON_BUILD_DIR) -type f -not -name "$(ADDON_NAME).toc" | xargs -I {} basename {} >> $(ADDON_BUILD_DIR)/$(ADDON_NAME).toc

release: addon
	cd $(BUILD_DIR) && zip -r $(ADDON_NAME)-$(VERSION).zip $(ADDON_NAME)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: doomgeneric doomgeneric_lua addon release clean
