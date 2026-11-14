PONYC_DIR := vendor/ponyc
PONYC_VERSION = $(shell cat $(PONYC_DIR)/VERSION)
PONYC_DISTRO ?= $(shell . /etc/os-release && echo $$ID$$VERSION_ID)
PONYC_URL = https://dl.cloudsmith.io/public/ponylang/releases/raw/versions/$(PONYC_VERSION)/ponyc-x86-64-unknown-linux-$(PONYC_DISTRO).tar.gz
TOOLS_PONYC := .tools/ponyc

.PHONY: ponyc ponyc-source build test clean distclean

build:
	crystal build src/sparkle.cr -o bin/sparkle

test:
	crystal spec

ponyc:
	@if [ -x $(TOOLS_PONYC)/bin/ponyc ] && [ "$$(cat $(TOOLS_PONYC)/VERSION-installed 2>/dev/null)" = "$(PONYC_VERSION)" ]; then \
		echo "ponyc $(PONYC_VERSION) already installed in $(TOOLS_PONYC)"; \
	elif [ "$$(uname -s)" != "Linux" ] || [ "$$(uname -m)" != "x86_64" ]; then \
		echo "no prebuilt ponyc for this host; run 'make ponyc-source'"; exit 1; \
	else \
		rm -rf $(TOOLS_PONYC) && mkdir -p $(TOOLS_PONYC) && \
		if curl -fsSL "$(PONYC_URL)" | tar -xz --strip-components=1 -C $(TOOLS_PONYC) && [ -x $(TOOLS_PONYC)/bin/ponyc ]; then \
			echo "$(PONYC_VERSION)" > $(TOOLS_PONYC)/VERSION-installed; \
			echo "installed ponyc $(PONYC_VERSION) in $(TOOLS_PONYC)"; \
		else \
			rm -rf $(TOOLS_PONYC); \
			echo "download of ponyc $(PONYC_VERSION) failed; run 'make ponyc-source'"; exit 1; \
		fi; \
	fi

ponyc-source:
	cd $(PONYC_DIR) && cmake -P lib/build-libs.cmake
	cd $(PONYC_DIR) && cmake --preset release
	cd $(PONYC_DIR) && cmake --build --preset release

clean:
	rm -rf bin .sparkle

distclean: clean
	rm -rf .tools
