# RGA validation report

Validated against the userspace source supplied without `.git` and the supplied `drivers/video/rockchip` kernel tree.

## Default build policy

The native Linux CMake path now defaults to:

- `Release` (`-O3 -DNDEBUG` with GCC/Clang toolchains used here);
- `-Wall -Wextra -Wformat=2 -Werror`;
- `-march=native -mtune=native` for native Release builds;
- LTO/IPO when the compiler/linker supports it;
- C++ exceptions and RTTI disabled for librga's native object target, matching the project's previous Linux intent;
- both `librga.a` and `librga.so` built from the exact same object target;
- the im2d demo included in the default CMake build so warning failures in sample/helper code are also visible.

`cmake-linux.sh` is now a native build script. On Orange Pi 5 it therefore makes `-march=native` target RK3588 rather than the host running a cross compiler.

Container validation completed with:

- GCC 14: complete Release build, zero warnings under `-Werror`;
- Clang 17: complete Release build, zero warnings under `-Werror`; the container's Clang installation lacks its LLVMgold LTO plugin, so CMake correctly reported IPO unsupported and continued without LTO for that *secondary* compiler validation;
- static integration link: the demo objects linked successfully against `librga.a` with no `librga.so` dependency;
- demo `--help` executes in the container; hardware operations are not runnable without `/dev/rga`.

## Warnings and defects fixed

The strict build exposed and the source now fixes, among other cleanup:

- 64-bit pointer truncation in code paths that assumed every non-AArch64 host was 32-bit;
- a real dangling-pointer lifetime bug in legacy `RgaBlit()` and `RgaCollorFill()` ioctl request selection;
- a real `void **` vs `void *` ioctl argument bug in legacy palette submission;
- palette-table update now performs the legacy RGA2 ABI conversion instead of sending the modern request layout to a legacy ioctl;
- legacy color-fill no longer reports a modern fence value that a legacy driver does not provide;
- non-literal `snprintf` patterns replaced where the format is actually constant;
- the variadic error-message wrapper is declared with a printf-format attribute so call sites receive real format checking;
- C++ object zero-initialization is used instead of `memset()` on non-trivial option objects;
- unused/dead locals reported by strict compilers were removed or scoped to Android-only blocks.

## Userspace source completeness

Every production Linux/C++ source under `core/` and `im2d_api/src/` is in the default CMake target: 18 translation units in total. Meson was aligned to the same source set; its previous omission of `core/rga_gralloc.cpp` and global warning suppression (`-w`) were removed. The container did not provide the `meson` executable and has no package-download network, so the executed validation path is CMake; Meson changes were statically reviewed but not configured here.

The only production-looking C++ files not in the native Linux target are:

- `core/platform_gralloc4.cpp`
- `core/platform_gralloc5.cpp`

They are Android mapper/gralloc implementations selected by Android-specific build logic and require Android graphics services; they are not missing Linux RGA functionality.

`RGA_SYNC_DISABLE` and `RGA_UTILS_DRM_DISABLE` are defined only for the RT-Thread target, not the default Linux build.

Two old YUV HDS/VDS heuristic blocks remain under upstream `#if 0`. Their ABI fields are still present and match the kernel. They were not force-enabled because that would change runtime image-processing policy rather than “compile more of the library”, and requires hardware/output validation on the target.

## Multi-RGA (RK3588) kernel ABI

The supplied userspace `core/hardware/rga_ioctl.h` was compared structurally against supplied kernel `rga3/include/rga.h`.

All tested ABI structure sizes and relevant offsets match on 64-bit ABI, including:

- `rga_img_info_t`: 56 bytes
- MMU info: 24 bytes
- `rga_req`: 504 bytes
- `rga_user_request`: 152 bytes
- `rga_external_buffer`: 288 bytes
- `rga_buffer_pool`: 16 bytes
- version/hardware-version structures, CSC, mosaic, OSD, pre-interrupt, Gaussian and RGBA5551 control structures.

All eight modern ioctl numbers match exactly:

- GET_DRIVER_VERSION
- GET_HW_VERSION
- IMPORT_BUFFER
- RELEASE_BUFFER
- REQUEST_CREATE
- REQUEST_SUBMIT
- REQUEST_CONFIG
- REQUEST_CANCEL

Userspace has call paths for all eight, and the supplied `rga3/rga_drv.c` has corresponding ioctl cases for all eight.

The kernel enum contains one additional memory type, `RGA_DMA_BUFFER_PTR`. Inspection of the supplied kernel shows it is used for **kernel-owned `struct dma_buf *` pointers** (including the in-kernel MPI path), not a userspace pointer type. Its absence from the userspace public enum is therefore intentional and not a missing userspace capability.

The userspace RK3588 hardware mapping recognizes RGA3 revision `0x76831` as RK3588 and RGA2-enhance revision `0x63318` as RK3566/RK3568/RK3588.

## Legacy RGA2/RGA1 compatibility

For AArch64, the userspace compatibility request prefix matches the supplied RGA2 driver's user-facing `struct rga_req` through the final meaningful `full_csc` field. The RGA2 driver supports the legacy `0x5017/0x5018` ioctl family and converts that request internally to its hardware-specific `struct rga2_req`, which matches what librga's compatibility path expects.

The much older `rga/` driver has an older tail containing kernel-private scatter-gather/attachment pointers. RK3588 uses Multi-RGA (`rga3`) rather than this path. The container audit therefore treats `rga3` as the required RK3588 ABI and `rga2/rga` as compatibility fallbacks; their real execution still needs target hardware if they are ever enabled.

## Kernel files used for the ABI audit

SHA-256 of key supplied files:

- `rga3/include/rga.h`: `2e21e8b8ba8a4d90b283dc9ef5791d7770a400edc3630fee38f66a6e544e5525`
- `rga3/rga_drv.c`: `f5a4c2f154c3634deb3ebcbeb7163c978613696e1e055691b41cdf90b381fae9`
- `rga2/rga2.h`: `822c8b6f928d9ab826570b12be6ceb38ffaacb593b50eed3e0000e3d745d62f2`
- `rga2/rga2_drv.c`: `028af72678e77963087785a3a4ac2bc3635d9ef26709c0476817ff0dd20204b4`

## Remaining Orange Pi 5 validation

`tools/validate-orange-pi.sh` is included to perform the native Release build, verify `-O3/-Werror/-march=native/-mtune=native`, query the live driver capabilities, and run a broad functional smoke-test set in one SSH session.

The remaining checks require the actual RK3588 system:

1. confirm `/dev/rga` and query driver/hardware versions;
2. build natively and verify the compile command contains `-O3 -march=native -mtune=native` and LTO is accepted by the target toolchain;
3. run querystring/copy/resize/format-conversion and async/fence paths;
4. test DMA-BUF import/release and job create/config/submit/cancel;
5. inspect `dmesg`/RGA debugfs for driver-side validation failures;
6. benchmark representative operations.

## Orange Pi 5 validation pass 1 (2026-08-18)

The first native RK3588 run used Ubuntu GCC/G++ 13.3.0 and CMake 3.28.3 on kernel `6.1.119-rt45-vendor-rk35xx`.
The live system exposed `/dev/rga`; kernel boot logs showed two RGA3 cores with hardware revision `3.0.76831`, one RGA2 core with revision `3.2.63318`, successful RGA IOMMU binding, and driver version `1.3.7`.

The target compiler accepted the intended native Release flags (`-O3 -Werror -march=native -mtune=native`) and LTO (`-flto=auto`). The first build stopped before linking because Ubuntu's fortified stdio declarations mark ignored `fread()` results with `warn_unused_result`; that distro/toolchain-specific diagnostic was not emitted by the container toolchains.

All production/default helper `fread()` and `fwrite()` calls now validate the exact transferred byte count, close the file on failure, and return `-EIO`. The same class of unchecked I/O was also fixed in the non-default SLT CRC sample so a later all-samples strict build will not simply encounter the equivalent issue there.

`tools/validate-orange-pi.sh` now also prints GCC's resolved native target settings and performs a real compile/link/run smoke test against `librga.a`, rejecting a test binary that accidentally depends on `librga.so`.


## Orange Pi 5 v3 fixes

- Fixed `samples/im2d_api_demo/CMakeLists.txt` incorrectly forcing every `cmake_linux` build to `RKRGA_TARGET_SOC=rv1106`. Native RK3588 builds now use the existing DMA32 heap path (`/dev/dma_heap/system-uncached-dma32`) unless `RKRGA_TARGET_SOC=rv1106` is explicitly requested.
- Fixed `rgaImDemo` process exit semantics: librga defines `IM_STATUS_SUCCESS` as `1`, but POSIX shells define exit status `0` as success. The demo now returns `EXIT_SUCCESS` for successful librga operations and `EXIT_FAILURE` otherwise.

## Orange Pi 5 DMA32/CMA validation (v4)

On the target RK3588 kernel, `/dev/dma_heap/system-uncached-dma32` is not
registered, while `/dev/dma_heap/reserved` is present. A five-iteration
hardware probe showed `imfill` succeeds 5/5 with `reserved`, and fails 5/5
with both `system` and `system-uncached`. The sample allocator therefore uses
`reserved` only as a low-memory fallback when a DMA32 heap was explicitly
requested but is unavailable. Because the standard CMA heap is cacheable, the
demo enables DMA-BUF CPU/device synchronization for this fallback. This does
not change librga's ABI or buffer-import behavior; it only makes the sample
allocator match the memory constraints of the live RK3588/RGA2 path.

## Advanced Orange Pi / RK3588 validation

After `tools/validate-orange-pi.sh` passes on the RK3588 target, run:

```sh
./tools/validate-orange-pi-advanced.sh
```

This builds an external application against `librga.a` with strict warnings and LTO,
then exercises DMA-BUF import/release, async release fences + `imsync()`, job
create/task/async-submit, job cancel, and the MPI context `REQUEST_CONFIG` path.
The test also verifies copied buffer contents and checks new kernel messages for
RGA/IOMMU/DMA faults.

## v8 advanced REQUEST_CONFIG validation

The RK3588 kernel ABI audit confirms that `RGA_IOC_REQUEST_CONFIG` calls the
request configuration path with execution disabled (`run_enable=false`). The
advanced smoke test therefore validates CONFIG by requiring a successful
`improcess_ctx()` call, verifying that the destination DMA-BUF remains
unchanged, and then cancelling the configured context successfully. This
avoids incorrectly treating CONFIG as SUBMIT.
