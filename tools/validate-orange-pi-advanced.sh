#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD=${RGA_BUILD_DIR:-"${ROOT}/build/build_linux"}
INCLUDE="${BUILD}/install/include"
ARCHIVE="${BUILD}/librga.a"
SOURCE="${ROOT}/tools/rga-advanced-smoke.cpp"
BINARY="${BUILD}/rga-advanced-smoke"
ITERATIONS=${RGA_ADVANCED_ITERATIONS:-5}

if [[ $(uname -m) != aarch64 && $(uname -m) != arm64 ]]; then
    printf 'ERROR: advanced validator must run natively on AArch64 target.\n' >&2
    exit 1
fi

for path in /dev/rga /dev/dma_heap/reserved "${ARCHIVE}" "${INCLUDE}/im2d.hpp" "${SOURCE}"; do
    if [[ ! -e ${path} ]]; then
        printf 'ERROR: required path missing: %s\n' "${path}" >&2
        exit 1
    fi
done

printf '=== strict external static-LTO link ===\n'
g++ -std=gnu++11 -O3 -Wall -Wextra -Wformat=2 -Werror \
    -march=native -mtune=native -flto=auto \
    -I"${INCLUDE}" "${SOURCE}" "${ARCHIVE}" \
    -pthread -ldl -lm -o "${BINARY}"

file "${BINARY}"
if ldd "${BINARY}" 2>/dev/null | grep -qi 'librga'; then
    printf 'ERROR: advanced smoke unexpectedly depends on librga.so\n' >&2
    exit 1
fi
printf 'Static external link: PASS (no librga.so dependency)\n'

before=$(dmesg 2>/dev/null | wc -l)
failures=0

printf '\n=== advanced API iterations ===\n'
for i in $(seq 1 "${ITERATIONS}"); do
    printf '\n--- advanced iteration %s/%s ---\n' "${i}" "${ITERATIONS}"
    if ! "${BINARY}"; then
        failures=$((failures + 1))
    fi
done

printf '\n=== new kernel messages ===\n'
new_dmesg=$(dmesg 2>/dev/null | tail -n "+$((before + 1))")
if [[ -n ${new_dmesg} ]]; then
    printf '%s\n' "${new_dmesg}" | grep -Ei \
        '(^|[[:space:]])rga([0-9:]|[[:space:]]|$)|iommu.*fault|mmu.*fault|dma.*fault|page fault|oops' || true
else
    printf 'No new kernel messages.\n'
fi

kernel_bad=0
if printf '%s\n' "${new_dmesg}" | grep -Eqi \
    'no core match|job assign failed|submit failed|request commit failed|iommu.*fault|mmu.*fault|dma.*fault|page fault|oops'; then
    kernel_bad=1
fi

printf '\n=== advanced result ===\n'
printf 'iterations=%s failures=%s kernel_bad=%s\n' "${ITERATIONS}" "${failures}" "${kernel_bad}"
if (( failures == 0 && kernel_bad == 0 )); then
    printf 'Advanced RGA API validation: PASS\n'
    exit 0
fi
printf 'Advanced RGA API validation: FAIL\n' >&2
exit 1
