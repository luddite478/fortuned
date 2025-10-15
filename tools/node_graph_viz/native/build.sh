#!/bin/sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$SCRIPT_DIR/build"
mkdir -p "$OUT_DIR"

INCLUDE_FLAGS="-I$SCRIPT_DIR/miniaudio"

clang -std=c11 -O2 -fPIC -dynamiclib \
  $INCLUDE_FLAGS \
  "$SCRIPT_DIR/nodegraph.c" \
  -o "$OUT_DIR/libnodegraph.dylib"

echo "Built $OUT_DIR/libnodegraph.dylib"
