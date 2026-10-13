#!/usr/bin/env bash
set -euo pipefail
framework=${1:?usage: build_native.sh <framework-root>}
module_dir=$(cd -- "$(dirname -- "$0")" && pwd)
lib_dir="$framework/core/native3d/lib"
test -f "$lib_dir/libgx3de.so"
mkdir -p "$module_dir/bin"
g++ -std=c++17 -O2 -fPIC -shared -Wall -Wextra -Werror \
  $(pkg-config --cflags tcl) \
  -I"$framework/core/native3d/include" \
  -I"$framework/core/native3d" \
  "$module_dir/native/gx3de_viewer_tcl.cpp" \
  -L"$lib_dir" -lgx3de $(pkg-config --libs tcl) \
  -Wl,-rpath,'$ORIGIN/../../../../core/native3d/lib' \
  -o "$module_dir/bin/libgx3de_viewer_tcl.so"
