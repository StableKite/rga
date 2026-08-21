#!/usr/bin/env bash
set -u -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${RGA_BUILD_DIR:-"${ROOT}/build/build_linux"}
JOBS=${RGA_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}

printf '=== host ===\n'
uname -a
printf 'arch: %s\n' "$(uname -m)"
if [[ $(uname -m) != aarch64 && $(uname -m) != arm64 ]]; then
    printf 'WARNING: expected native AArch64/RK3588 validation host.\n' >&2
fi

printf '\n=== /dev/rga ===\n'
if [[ ! -e /dev/rga ]]; then
    printf 'ERROR: /dev/rga is missing. Kernel/DT validation must be fixed before userspace tests.\n' >&2
    exit 1
fi
ls -l /dev/rga

printf '\n=== native Release build ===\n'
if ! RGA_BUILD_DIR="${BUILD}" RGA_JOBS="${JOBS}" "${ROOT}/cmake-linux.sh"; then
    printf 'ERROR: native Release build failed.\n' >&2
    exit 1
fi

FLAGS_FILE="${BUILD}/CMakeFiles/rga-object.dir/flags.make"
if [[ ! -f ${FLAGS_FILE} ]]; then
    printf 'ERROR: missing compiler flags file: %s\n' "${FLAGS_FILE}" >&2
    exit 1
fi
CXX_FLAGS=$(sed -n 's/^CXX_FLAGS = //p' "${FLAGS_FILE}")
printf 'CXX_FLAGS=%s\n' "${CXX_FLAGS}"

missing=0
for flag in -O3 -Werror -march=native -mtune=native; do
    if [[ " ${CXX_FLAGS} " != *" ${flag} "* ]]; then
        printf 'ERROR: required flag not found: %s\n' "${flag}" >&2
        missing=1
    fi
done
if [[ ${CXX_FLAGS} != *-flto* ]]; then
    printf 'WARNING: LTO flag was not enabled by this target toolchain.\n' >&2
fi
(( missing == 0 )) || exit 1

printf '\n=== GCC native target resolution ===\n'
if command -v gcc >/dev/null 2>&1; then
    gcc -march=native -mtune=native -Q --help=target -c -x c /dev/null 2>/dev/null |
        grep -E '^[[:space:]]+-(march|mcpu|mtune)=' || true
fi

printf '\n=== artifacts ===\n'
file "${BUILD}/librga.a" "${BUILD}/librga.so"
ar t "${BUILD}/librga.a" | head -20

printf '\n=== static archive link smoke test ===\n'
STATIC_SRC="${BUILD}/rga-static-smoke.cpp"
STATIC_BIN="${BUILD}/rga-static-smoke"
cat >"${STATIC_SRC}" <<'EOF'
#include "RgaUtils.h"
#include "rga.h"
int main() {
    return get_bpp_from_format(RK_FORMAT_RGBA_8888) == 4.0f ? 0 : 1;
}
EOF
"${CXX:-g++}" -O3 -DNDEBUG -march=native -mtune=native \
    -I"${ROOT}/include" -I"${ROOT}/im2d_api" \
    "${STATIC_SRC}" "${BUILD}/librga.a" -pthread -lm -o "${STATIC_BIN}"
if ldd "${STATIC_BIN}" 2>/dev/null | grep -qi 'librga'; then
    printf 'ERROR: static smoke binary unexpectedly depends on librga.so.\n' >&2
    exit 1
fi
"${STATIC_BIN}"
printf 'Static librga.a link/runtime smoke: PASS\n'

DEMO="${BUILD}/samples/im2d_api_demo/rgaImDemo"
if [[ ! -x ${DEMO} ]]; then
    printf 'ERROR: demo executable not found: %s\n' "${DEMO}" >&2
    exit 1
fi

printf '\n=== driver / hardware capabilities ===\n'
"${DEMO}" --querystring=all || exit $?

printf '\n=== DMA heaps ===\n'
for heap in /dev/dma_heap/* /dev/rk_dma_heap/*; do
    [[ -e ${heap} ]] && ls -l "${heap}"
done
if [[ -e /dev/dma_heap/system-uncached-dma32 ]]; then
    printf 'RK3588 DMA32 heap: PASS (%s)\n' /dev/dma_heap/system-uncached-dma32
elif [[ -e /dev/dma_heap/reserved ]]; then
    printf 'RK3588 DMA32 heap: unavailable; verified low-memory CMA fallback is present (%s)\n' /dev/dma_heap/reserved
else
    printf 'WARNING: neither RK3588 DMA32 heap nor reserved CMA fallback is present; RGA2-only operations may fail with memory above 4G.\n' >&2
fi

printf '\n=== functional smoke tests ===\n'
# Each test allocates/imports buffers and executes a real RGA operation. Continue after
# failures so one SSH run captures the whole compatibility picture.
tests=(
    '--copy'
    '--resize=up'
    '--resize=down'
    '--crop'
    '--rotate=90'
    '--rotate=180'
    '--rotate=270'
    '--flip=H'
    '--flip=V'
    '--translate'
    '--blend=src-over'
    '--cvtcolor'
    '--fill=red'
)
failures=0
for test_arg in "${tests[@]}"; do
    printf '\n--- %s ---\n' "${test_arg}"
    if ! "${DEMO}" "${test_arg}"; then
        printf 'FAILED: %s\n' "${test_arg}" >&2
        failures=$((failures + 1))
    fi
done

printf '\n=== result ===\n'
if (( failures )); then
    printf '%d functional smoke test(s) failed. Save this output plus dmesg for analysis.\n' "${failures}" >&2
    exit 1
fi
printf 'All functional smoke tests passed.\n'
