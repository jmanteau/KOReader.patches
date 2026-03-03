include .env

.DEFAULT_GOAL := help

EMULATOR_KOREADER := $(patsubst %/patches,%,$(EMULATOR_PATCHES))

SIMULATE ?= kobo-libra-2

# Device presets (used when SIMULATE is set)
# kodev built-in: kindle, legacy-paperwhite, kobo-forma, kobo-aura-one,
#                 kobo-clara, kindle-paperwhite, kobo-h2o, hidpi
# Custom presets resolved below.

# Custom device presets (not built into kodev)
ifeq ($(SIMULATE),kobo-libra-2)
  KODEV_SCREEN_FLAGS := -W 632 -H 840 -D 300
  export EMULATE_READER_PIXEL_SCALE := 2
else ifeq ($(SIMULATE),boox-go-7)
  KODEV_SCREEN_FLAGS := -W 632 -H 840 -D 300
  export EMULATE_READER_PIXEL_SCALE := 2
else ifeq ($(SIMULATE),custom)
  KODEV_SCREEN_FLAGS := -W $(SCREEN_W) -H $(SCREEN_H) -D $(DPI)
else
  KODEV_SCREEN_FLAGS := -s $(SIMULATE)
endif

.PHONY: help run run-bw link-patches link-icons reset devices

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(firstword $(MAKEFILE_LIST)) | awk -F ':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

run: link-patches link-icons ## Run emulator (SIMULATE=<device> to change screen)
	$(KODEV) run -v $(KODEV_SCREEN_FLAGS) $(LIBRARY)

run-bw: link-patches link-icons ## Run emulator in grayscale (SIMULATE=<device>)
	EMULATE_BW_SCREEN=1 EMULATE_BB_TYPE=BB8 $(KODEV) run -v $(KODEV_SCREEN_FLAGS) $(LIBRARY)

link-patches: ## Symlink emulator patches dir to this repo's patches/
ifndef EMULATOR_PATCHES
	$(error EMULATOR_PATCHES is not set -- add it to .env or pass on the command line)
endif
	@if [ -L patches ]; then \
		echo "ERROR: ./patches is a symlink (old reversed setup). Remove it and restore the real directory." >&2; \
		exit 1; \
	fi
	@if [ ! -d patches ]; then \
		echo "ERROR: ./patches directory not found -- this repo's source-of-truth is missing." >&2; \
		exit 1; \
	fi
	@if [ ! -d "$(dir $(EMULATOR_PATCHES))" ]; then \
		echo "ERROR: Parent directory of EMULATOR_PATCHES does not exist: $(dir $(EMULATOR_PATCHES))" >&2; \
		exit 1; \
	fi
	@if [ -d "$(EMULATOR_PATCHES)" ] && [ ! -L "$(EMULATOR_PATCHES)" ]; then \
		echo "ERROR: $(EMULATOR_PATCHES) is a real directory -- refusing to delete it. Remove manually if intended." >&2; \
		exit 1; \
	fi
	@if [ -L "$(EMULATOR_PATCHES)" ] && [ "$$(readlink "$(EMULATOR_PATCHES)")" = "$(CURDIR)/patches" ]; then \
		exit 0; \
	fi
	@rm -f "$(EMULATOR_PATCHES)"
	@ln -s "$(CURDIR)/patches" "$(EMULATOR_PATCHES)"
	@echo "Symlinked $(EMULATOR_PATCHES) -> $(CURDIR)/patches"

EMULATOR_ICONS := $(EMULATOR_KOREADER)/icons

link-icons: ## Symlink emulator icons dir to this repo's icons/
ifndef EMULATOR_PATCHES
	$(error EMULATOR_PATCHES is not set -- add it to .env or pass on the command line)
endif
	@if [ -L icons ]; then \
		echo "ERROR: ./icons is a symlink (old reversed setup). Remove it and restore the real directory." >&2; \
		exit 1; \
	fi
	@if [ ! -d icons ]; then \
		echo "ERROR: ./icons directory not found -- this repo's source-of-truth is missing." >&2; \
		exit 1; \
	fi
	@if [ -d "$(EMULATOR_ICONS)" ] && [ ! -L "$(EMULATOR_ICONS)" ]; then \
		echo "ERROR: $(EMULATOR_ICONS) is a real directory -- refusing to delete it. Remove manually if intended." >&2; \
		exit 1; \
	fi
	@if [ -L "$(EMULATOR_ICONS)" ] && [ "$$(readlink "$(EMULATOR_ICONS)")" = "$(CURDIR)/icons" ]; then \
		exit 0; \
	fi
	@rm -f "$(EMULATOR_ICONS)"
	@ln -s "$(CURDIR)/icons" "$(EMULATOR_ICONS)"
	@echo "Symlinked $(EMULATOR_ICONS) -> $(CURDIR)/icons"

devices: ## List available device presets for SIMULATE=
	@echo "Custom presets:"
	@echo "  kobo-libra-2       632x840 @ 300 DPI (default)"
	@echo "  boox-go-7          632x840 @ 300 DPI"
	@echo "  custom             use SCREEN_W, SCREEN_H, DPI vars"
	@echo ""
	@echo "kodev built-in presets:"
	@echo "  kindle             600x800   @ 167 DPI"
	@echo "  legacy-paperwhite  758x1024  @ 212 DPI"
	@echo "  kobo-forma         1440x1920 @ 300 DPI"
	@echo "  kobo-aura-one      1404x1872 @ 300 DPI"
	@echo "  kobo-clara         1072x1448 @ 300 DPI"
	@echo "  kobo-h2o           1080x1429 @ 265 DPI"
	@echo "  hidpi              1500x2000 @ 600 DPI"

reset: ## Remove all KOReader state from the emulator (stats, settings, cache, history, sidecars)
ifndef EMULATOR_PATCHES
	$(error EMULATOR_PATCHES is not set -- add it to .env or pass on the command line)
endif
	rm -f "$(EMULATOR_KOREADER)/settings.reader.lua"
	rm -f "$(EMULATOR_KOREADER)/history.lua"
	rm -f "$(EMULATOR_KOREADER)/settings/statistics.sqlite3"
	rm -f "$(EMULATOR_KOREADER)/settings/bookinfo_cache.sqlite3"
	rm -f "$(EMULATOR_KOREADER)/settings/vocabulary_builder.sqlite3"
	rm -rf "$(EMULATOR_KOREADER)/cache"
	@if [ -n "$(LIBRARY)" ] && [ -d "$(LIBRARY)" ]; then \
		find "$(LIBRARY)" -name '*.sdr' -type d -exec rm -rf {} + 2>/dev/null; \
		echo "Removed sidecars from $(LIBRARY)"; \
	fi
	@echo "Emulator state reset"
