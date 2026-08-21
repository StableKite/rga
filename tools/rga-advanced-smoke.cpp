#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "im2d.hpp"

struct dma_heap_allocation_data_local {
    uint64_t len;
    uint32_t fd;
    uint32_t fd_flags;
    uint64_t heap_flags;
};

struct dma_buf_sync_local {
    uint64_t flags;
};

#define DMA_HEAP_IOC_MAGIC_LOCAL 'H'
#define DMA_HEAP_IOCTL_ALLOC_LOCAL _IOWR(DMA_HEAP_IOC_MAGIC_LOCAL, 0x0, struct dma_heap_allocation_data_local)
#define DMA_BUF_BASE_LOCAL 'b'
#define DMA_BUF_IOCTL_SYNC_LOCAL _IOW(DMA_BUF_BASE_LOCAL, 0, struct dma_buf_sync_local)
#define DMA_BUF_SYNC_READ_LOCAL (1ULL << 0)
#define DMA_BUF_SYNC_WRITE_LOCAL (2ULL << 0)
#define DMA_BUF_SYNC_RW_LOCAL (DMA_BUF_SYNC_READ_LOCAL | DMA_BUF_SYNC_WRITE_LOCAL)
#define DMA_BUF_SYNC_START_LOCAL (0ULL << 2)
#define DMA_BUF_SYNC_END_LOCAL (1ULL << 2)

static bool status_ok(IM_STATUS status) {
    return status == IM_STATUS_SUCCESS || status == IM_STATUS_NOERROR;
}

static int sync_fd(int fd, uint64_t flags) {
    dma_buf_sync_local sync{};
    sync.flags = flags;
    return ioctl(fd, DMA_BUF_IOCTL_SYNC_LOCAL, &sync);
}

struct Buffer {
    int fd = -1;
    void *va = MAP_FAILED;
    size_t size = 0;
    rga_buffer_handle_t handle = 0;
};

static void cleanup(Buffer &buffer) {
    if (buffer.handle != 0) {
        IM_STATUS status = releasebuffer_handle(buffer.handle);
        std::printf("cleanup releasebuffer_handle(%llu) -> %d\n",
                    static_cast<unsigned long long>(buffer.handle),
                    static_cast<int>(status));
        buffer.handle = 0;
    }
    if (buffer.va != MAP_FAILED) {
        munmap(buffer.va, buffer.size);
        buffer.va = MAP_FAILED;
    }
    if (buffer.fd >= 0) {
        close(buffer.fd);
        buffer.fd = -1;
    }
}

static int alloc_reserved(Buffer &buffer, size_t size) {
    const char *heap_path = "/dev/dma_heap/reserved";
    int heap_fd = open(heap_path, O_RDWR | O_CLOEXEC);
    if (heap_fd < 0) {
        std::fprintf(stderr, "open(%s): %s\n", heap_path, std::strerror(errno));
        return -1;
    }

    dma_heap_allocation_data_local request{};
    request.len = size;
    request.fd_flags = O_RDWR | O_CLOEXEC;
    if (ioctl(heap_fd, DMA_HEAP_IOCTL_ALLOC_LOCAL, &request) < 0) {
        std::fprintf(stderr, "DMA_HEAP_IOCTL_ALLOC: %s\n", std::strerror(errno));
        close(heap_fd);
        return -1;
    }
    close(heap_fd);

    void *va = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED,
                    static_cast<int>(request.fd), 0);
    if (va == MAP_FAILED) {
        std::fprintf(stderr, "mmap: %s\n", std::strerror(errno));
        close(static_cast<int>(request.fd));
        return -1;
    }

    buffer.fd = static_cast<int>(request.fd);
    buffer.va = va;
    buffer.size = size;
    return 0;
}

static int cpu_write_pattern(Buffer &buffer, uint8_t value) {
    if (sync_fd(buffer.fd, DMA_BUF_SYNC_START_LOCAL | DMA_BUF_SYNC_RW_LOCAL) < 0) {
        std::fprintf(stderr, "DMA_BUF_SYNC START(write): %s\n", std::strerror(errno));
        return -1;
    }
    std::memset(buffer.va, value, buffer.size);
    if (sync_fd(buffer.fd, DMA_BUF_SYNC_END_LOCAL | DMA_BUF_SYNC_RW_LOCAL) < 0) {
        std::fprintf(stderr, "DMA_BUF_SYNC END(write): %s\n", std::strerror(errno));
        return -1;
    }
    return 0;
}

static int verify_pattern(Buffer &buffer, uint8_t value, const char *label) {
    if (sync_fd(buffer.fd, DMA_BUF_SYNC_START_LOCAL | DMA_BUF_SYNC_RW_LOCAL) < 0) {
        std::fprintf(stderr, "DMA_BUF_SYNC START(read): %s\n", std::strerror(errno));
        return -1;
    }

    const uint8_t *bytes = static_cast<const uint8_t *>(buffer.va);
    size_t mismatch = buffer.size;
    uint8_t actual = 0;
    for (size_t i = 0; i < buffer.size; ++i) {
        if (bytes[i] != value) {
            mismatch = i;
            actual = bytes[i];
            break;
        }
    }

    if (sync_fd(buffer.fd, DMA_BUF_SYNC_END_LOCAL | DMA_BUF_SYNC_RW_LOCAL) < 0) {
        std::fprintf(stderr, "DMA_BUF_SYNC END(read): %s\n", std::strerror(errno));
        return -1;
    }

    if (mismatch != buffer.size) {
        std::fprintf(stderr,
                     "%s data mismatch at byte %zu: got 0x%02x expected 0x%02x\n",
                     label, mismatch, actual, value);
        return -1;
    }

    std::printf("%s data verification: PASS (%zu bytes)\n", label, buffer.size);
    return 0;
}

int main() {
    constexpr int width = 640;
    constexpr int height = 480;
    constexpr int format = RK_FORMAT_RGBA_8888;
    constexpr size_t bytes = static_cast<size_t>(width) * height * 4;

    Buffer src;
    Buffer dst;
    int failures = 0;

    std::printf("=== advanced RGA API smoke ===\n");
    std::printf("buffer: %dx%d RGBA8888, %zu bytes\n", width, height, bytes);

    if (alloc_reserved(src, bytes) != 0 || alloc_reserved(dst, bytes) != 0) {
        cleanup(src);
        cleanup(dst);
        return 10;
    }

    if (cpu_write_pattern(src, 0x5a) != 0 || cpu_write_pattern(dst, 0x00) != 0) {
        cleanup(src);
        cleanup(dst);
        return 11;
    }

    src.handle = importbuffer_fd(src.fd, width, height, format);
    dst.handle = importbuffer_fd(dst.fd, width, height, format);
    std::printf("IMPORT src handle=%llu dst handle=%llu\n",
                static_cast<unsigned long long>(src.handle),
                static_cast<unsigned long long>(dst.handle));
    if (src.handle == 0 || dst.handle == 0) {
        std::fprintf(stderr, "IMPORT: FAIL\n");
        cleanup(src);
        cleanup(dst);
        return 12;
    }
    std::printf("IMPORT: PASS\n");

    rga_buffer_t src_rga = wrapbuffer_handle(src.handle, width, height, format);
    rga_buffer_t dst_rga = wrapbuffer_handle(dst.handle, width, height, format);

    std::printf("\n=== ASYNC + FENCE ===\n");
    int fence_fd = -1;
    IM_STATUS status = imcopy(src_rga, dst_rga, 0, &fence_fd);
    std::printf("imcopy(async) -> %d, release_fence=%d\n",
                static_cast<int>(status), fence_fd);
    if (!status_ok(status) || fence_fd <= 0) {
        std::fprintf(stderr, "ASYNC submit/fence: FAIL\n");
        ++failures;
        if (fence_fd > 0)
            close(fence_fd);
    } else {
        status = imsync(fence_fd);
        std::printf("imsync -> %d\n", static_cast<int>(status));
        if (!status_ok(status) || verify_pattern(dst, 0x5a, "ASYNC copy") != 0)
            ++failures;
        else
            std::printf("ASYNC + FENCE: PASS\n");
    }

    std::printf("\n=== JOB CREATE + TASK + ASYNC SUBMIT ===\n");
    if (cpu_write_pattern(dst, 0x00) != 0)
        ++failures;
    im_job_handle_t job = imbeginJob();
    std::printf("imbeginJob -> %u\n", job);
    if (job == 0) {
        std::fprintf(stderr, "JOB CREATE: FAIL\n");
        ++failures;
    } else {
        status = imcopyTask(job, src_rga, dst_rga);
        std::printf("imcopyTask -> %d\n", static_cast<int>(status));
        int job_fence_fd = -1;
        if (!status_ok(status)) {
            ++failures;
            (void)imcancelJob(job);
        } else {
            status = imendJob(job, IM_ASYNC, 0, &job_fence_fd);
            std::printf("imendJob(async) -> %d, release_fence=%d\n",
                        static_cast<int>(status), job_fence_fd);
            if (!status_ok(status) || job_fence_fd <= 0) {
                ++failures;
                if (job_fence_fd > 0)
                    close(job_fence_fd);
            } else {
                status = imsync(job_fence_fd);
                std::printf("job imsync -> %d\n", static_cast<int>(status));
                if (!status_ok(status) || verify_pattern(dst, 0x5a, "JOB copy") != 0)
                    ++failures;
                else
                    std::printf("JOB SUBMIT: PASS\n");
            }
        }
    }

    std::printf("\n=== JOB CANCEL ===\n");
    im_job_handle_t cancel_job = imbeginJob();
    std::printf("imbeginJob(cancel test) -> %u\n", cancel_job);
    if (cancel_job == 0) {
        ++failures;
    } else {
        status = imcancelJob(cancel_job);
        std::printf("imcancelJob -> %d\n", static_cast<int>(status));
        if (!status_ok(status))
            ++failures;
        else
            std::printf("JOB CANCEL: PASS\n");
    }

    std::printf("\n=== MPI CONTEXT / REQUEST_CONFIG ===\n");
    if (cpu_write_pattern(dst, 0x00) != 0)
        ++failures;
    im_ctx_id_t context = imbegin(0);
    std::printf("imbegin(ctx) -> %u\n", context);
    if (context == 0) {
        ++failures;
    } else {
        rga_buffer_t pat{};
        im_rect src_rect{};
        im_rect dst_rect{};
        im_rect pat_rect{};
        im_opt_t opt{};

        // RGA_IOC_REQUEST_CONFIG configures the request but intentionally does
        // not submit it. The kernel's CONFIG ioctl uses run_enable=false.
        // Therefore a successful improcess_ctx() must leave dst untouched
        // until a separate submit path is used; cancellation then releases it.
        src_rect.x = 0;
        src_rect.y = 0;
        src_rect.width = width;
        src_rect.height = height;
        dst_rect = src_rect;

        int unused_fence_fd = -1;
        status = improcess_ctx(src_rga, dst_rga, pat,
                               src_rect, dst_rect, pat_rect,
                               -1, &unused_fence_fd, &opt, 0, context);
        std::printf("improcess_ctx(sync/config) -> %d, fence=%d\n",
                    static_cast<int>(status), unused_fence_fd);
        if (!status_ok(status)) {
            ++failures;
        } else if (unused_fence_fd != -1) {
            std::fprintf(stderr,
                         "REQUEST_CONFIG unexpectedly returned a release fence: %d\n",
                         unused_fence_fd);
            if (unused_fence_fd > 0)
                close(unused_fence_fd);
            ++failures;
        } else if (verify_pattern(dst, 0x00, "MPI CONFIG no-submit") != 0) {
            ++failures;
        } else {
            std::printf("REQUEST_CONFIG path: PASS (configured, not submitted)\n");
        }

        IM_STATUS cancel_status = imcancel(context);
        std::printf("imcancel(ctx) -> %d\n", static_cast<int>(cancel_status));
        if (!status_ok(cancel_status)) {
            ++failures;
        } else {
            std::printf("REQUEST_CONFIG cancel: PASS\n");
        }
    }

    std::printf("\n=== RELEASE IMPORTED BUFFERS ===\n");
    IM_STATUS src_release = releasebuffer_handle(src.handle);
    IM_STATUS dst_release = releasebuffer_handle(dst.handle);
    std::printf("release src -> %d, dst -> %d\n",
                static_cast<int>(src_release), static_cast<int>(dst_release));
    src.handle = 0;
    dst.handle = 0;
    if (!status_ok(src_release) || !status_ok(dst_release)) {
        ++failures;
    } else {
        std::printf("RELEASE: PASS\n");
    }

    cleanup(src);
    cleanup(dst);

    std::printf("\nADVANCED FAILURES=%d\n", failures);
    if (failures == 0) {
        std::printf("ADVANCED RGA API SMOKE: PASS\n");
        return 0;
    }

    std::printf("ADVANCED RGA API SMOKE: FAIL\n");
    return 1;
}
