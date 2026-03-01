include .env

.DEFAULT_GOAL := help

EMULATOR_KOREADER := $(patsubst %/patches,%,$(EMULATOR_PATCHES))

.PHONY: help run run-bw link-patches reset

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(firstword $(MAKEFILE_LIST)) | awk -F ':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

run: link-patches ## Run emulator in color
	$(KODEV) run -v $(LIBRARY)

run-bw: link-patches ## Run emulator in grayscale (Kobo e-ink simulation)
	EMULATE_BW_SCREEN=1 EMULATE_BB_TYPE=BB8 $(KODEV) run -v $(LIBRARY)

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
