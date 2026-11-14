#!/bin/sh
# Builds the three spike stages into build/. Linux x86-64 only.
set -e
cd "$(dirname "$0")"
P=../../vendor/ponyc
mkdir -p build
cc -c -O1 -I$P/src/libponyc -I$P/src/common shim.c -o build/shim.o
for stage in stage1 stage2 stage3 stage4; do
  crystal build $stage.cr -o build/$stage
done
