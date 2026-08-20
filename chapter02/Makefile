KUBARA_SRC := $(CURDIR)/kubara/src

OFFLINE ?= 0
OFFLINE_BOOTSTRAP_CATALOG ?= ./catalogs/bootstrap
OFFLINE_GENERAL_CATALOG ?= ./catalogs/general

.PHONY: help build build-all test clean

help:
	@echo "kubara build targets:"
	@echo "  make build                 Build for the current platform"
	@echo "  make build-all             Build for Linux, macOS, and Windows (amd64/arm64)"
	@echo "  make build OFFLINE=1       Build with local catalog paths as defaults"
	@echo "  make build-all OFFLINE=1   Cross-build with local catalog paths as defaults"

build:
	@$(MAKE) -C $(KUBARA_SRC) build \
		OFFLINE=$(OFFLINE) \
		OFFLINE_BOOTSTRAP_CATALOG=$(OFFLINE_BOOTSTRAP_CATALOG) \
		OFFLINE_GENERAL_CATALOG=$(OFFLINE_GENERAL_CATALOG)

build-all:
	@$(MAKE) -C $(KUBARA_SRC) build-all \
		OFFLINE=$(OFFLINE) \
		OFFLINE_BOOTSTRAP_CATALOG=$(OFFLINE_BOOTSTRAP_CATALOG) \
		OFFLINE_GENERAL_CATALOG=$(OFFLINE_GENERAL_CATALOG)

test:
	@$(MAKE) -C $(KUBARA_SRC) test

clean:
	@$(MAKE) -C $(KUBARA_SRC) clean
