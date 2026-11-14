PONYC_DIR := vendor/ponyc
PONYC_VERSION = $(shell cat $(PONYC_DIR)/VERSION)
HOST_OS ?= $(shell uname -s)
HOST_ARCH ?= $(shell uname -m)
PONYC_DISTRO ?= $(shell if [ -r /etc/os-release ]; then . /etc/os-release && echo $$ID$$VERSION_ID; fi)
PONYC_ARCH = $(strip $(if $(filter x86_64 amd64,$(HOST_ARCH)),x86-64,$(if $(filter arm64 aarch64,$(HOST_ARCH)),arm64)))
PONYC_PLATFORM = $(strip $(if $(filter Darwin,$(HOST_OS)),apple-darwin,$(if $(filter Linux,$(HOST_OS)),$(if $(PONYC_DISTRO),unknown-linux-$(PONYC_DISTRO)))))
PONYC_URL = https://dl.cloudsmith.io/public/ponylang/releases/raw/versions/$(PONYC_VERSION)/ponyc-$(PONYC_ARCH)-$(PONYC_PLATFORM).tar.gz
TOOLS_PONYC ?= .tools/ponyc

.PHONY: ponyc ponyc-source build test lint clean distclean

build:
	@mkdir -p bin
	crystal build src/sparkle.cr -o bin/sparkle

test:
	crystal spec

lint:
	bin/ameba src spec

ponyc:
	@if [ -x $(TOOLS_PONYC)/bin/ponyc ] && [ "$$(cat $(TOOLS_PONYC)/VERSION-installed 2>/dev/null)" = "$(PONYC_VERSION)" ]; then \
		echo "ponyc $(PONYC_VERSION) already installed in $(TOOLS_PONYC)"; \
	elif [ -z "$(PONYC_ARCH)" ] || [ -z "$(PONYC_PLATFORM)" ]; then \
		echo "no prebuilt ponyc for $(HOST_OS) $(HOST_ARCH); run 'make ponyc-source'"; exit 1; \
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
