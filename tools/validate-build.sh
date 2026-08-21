#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=${RGA_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
BUILD=${RGA_VALIDATION_BUILD_DIR:-"${ROOT}/build/validation"}

rm -rf "${BUILD}"
cmake -S "${ROOT}" -B "${BUILD}" \
    -DCMAKE_BUILD_TARGET=cmake_linux \
    -DCMAKE_BUILD_TYPE=Release \
    -DRGA_WARNINGS_AS_ERRORS=ON \
    -DRGA_NATIVE_OPTIMIZATION=ON \
    -DRGA_ENABLE_LTO=ON \
    -DRGA_BUILD_SAMPLES=ON
cmake --build "${BUILD}" --parallel "${JOBS}"

printf '\nValidated artifacts:\n'
file "${BUILD}/librga.a" "${BUILD}/librga.so" "${BUILD}/samples/im2d_api_demo/rgaImDemo"
printf '\nCompiler flags for rga-object:\n'
if [[ -f "${BUILD}/CMakeFiles/rga-object.dir/flags.make" ]]; then
    grep -E '^(C|CXX)_FLAGS' "${BUILD}/CMakeFiles/rga-object.dir/flags.make" || true
fi
