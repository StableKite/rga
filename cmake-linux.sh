#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${RGA_BUILD_DIR:-"${SCRIPT_DIR}/build/build_linux"}
BUILD_TYPE=${RGA_BUILD_TYPE:-Release}
JOBS=${RGA_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
BUILD_SOURCE_TYPE=cpp

# Keep the historical "c" first argument for callers that need the C-compatibility build.
if [[ ${1:-} == "c" ]]; then
    BUILD_SOURCE_TYPE=c
    shift
fi

rm -rf "${BUILD_DIR}"
cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TARGET=cmake_linux \
    -DRGA_SOURCE_CODE_TYPE="${BUILD_SOURCE_TYPE}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}/install" \
    "$@"

cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
cmake --install "${BUILD_DIR}"
