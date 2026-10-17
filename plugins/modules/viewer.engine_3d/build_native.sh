#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Established build entry delegates to the single CORE CMake target.
set -euo pipefail
framework=${1:?usage: build_native.sh <framework-root> <new-build-directory>}
build_dir=${2:?provide a separate new build directory}
test ! -e "$build_dir"
cmake -S "$framework/core/native3d" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DGX3DE_BUILD_TCL_VIEWER=ON
cmake --build "$build_dir" --target gx3de_viewer_tcl --parallel
# Install through the CORE project after reviewing the build. No plugin-local copy.
