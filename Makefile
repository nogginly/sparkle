PONYC_DIR := vendor/ponyc

.PHONY: ponyc build test clean

build:
	crystal build src/sparkle.cr -o bin/sparkle

test:
	crystal spec

ponyc:
	cd $(PONYC_DIR) && cmake -P lib/build-libs.cmake
	cd $(PONYC_DIR) && cmake --preset release
	cd $(PONYC_DIR) && cmake --build --preset release

clean:
	rm -rf bin .sparkle
