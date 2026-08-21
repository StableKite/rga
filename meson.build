project(
    'librga',
    'cpp',
    version : '2.1.0',
    meson_version : '>=0.47.0',
    default_options : [
        'buildtype=release',
        'warning_level=3',
        'werror=true',
        'b_lto=true',
        'cpp_std=c++11'
    ]
)

pkgconfig = import('pkgconfig')
libthreads_dep = dependency('threads')
cc = meson.get_compiler('cpp')

project_cpp_args = ['-DLINUX=1', '-DUN_NEED_GL']
if get_option('native_optimization') and not meson.is_cross_build()
    if cc.has_argument('-march=native')
        project_cpp_args += ['-march=native']
    endif
    if cc.has_argument('-mtune=native')
        project_cpp_args += ['-mtune=native']
    endif
endif
add_project_arguments(project_cpp_args, language : 'cpp')

librga_srcs = [
    'core/utils/android_utils/src/android_utils.cpp',
    'core/utils/drm_utils/src/drm_utils.cpp',
    'core/utils/utils.cpp',
    'core/GrallocOps.cpp',
    'core/NormalRgaApi.cpp',
    'core/NormalRga.cpp',
    'core/RgaUtils.cpp',
    'core/RgaUtils_symbol.cpp',
    'core/RockchipRga.cpp',
    'core/RgaApi.cpp',
    'core/rga_gralloc.cpp',
    'core/rga_sync.cpp',
    'im2d_api/src/im2d_log.cpp',
    'im2d_api/src/im2d_debugger.cpp',
    'im2d_api/src/im2d_context.cpp',
    'im2d_api/src/im2d_job.cpp',
    'im2d_api/src/im2d_impl.cpp',
    'im2d_api/src/im2d.cpp',
]

incdir = include_directories(
    '.',
    'include',
    'im2d_api',
    'core',
    'core/hardware',
    'core/utils',
    'core/adapter',
    'core/3rdparty/libdrm/include/drm',
    'core/3rdparty/android_hal'
)

# Keep shared and static outputs in the default build.  They use the exact same
# source list so neither variant can silently lose functionality.
librga_shared = shared_library(
    'rga',
    librga_srcs,
    dependencies : [libthreads_dep],
    include_directories : incdir,
    install : true,
)

librga_static = static_library(
    'rga',
    librga_srcs,
    dependencies : [libthreads_dep],
    include_directories : incdir,
    install : true,
)

install_headers(
    'include/rga.h',
    'include/drmrga.h',
    'include/GrallocOps.h',
    'include/RockchipRga.h',
    'include/RgaMutex.h',
    'include/RgaSingleton.h',
    'include/RgaUtils.h',
    'include/RgaApi.h',
    'im2d_api/im2d.h',
    'im2d_api/im2d.hpp',
    'im2d_api/im2d_type.h',
    'im2d_api/im2d_version.h',
    'im2d_api/im2d_buffer.h',
    'im2d_api/im2d_common.h',
    'im2d_api/im2d_single.h',
    'im2d_api/im2d_task.h',
    'im2d_api/im2d_mpi.h',
    'im2d_api/im2d_expand.h',
    subdir : 'rga',
)

pkgconfig.generate(
    libraries : librga_shared,
    filebase : 'librga',
    name : 'librga',
    version : meson.project_version(),
    description : 'Userspace interface to Rockchip RGA 2D accelerator',
    extra_cflags : ['-I${includedir}/rga'],
)

librga_demo_option = get_option('librga_demo')
if librga_demo_option != 'false'
    demo_src = [
        'samples/utils/utils.cpp',
        'samples/utils/allocator/dma_alloc.cpp',
        'samples/utils/allocator/drm_alloc.cpp',
        'samples/im2d_api_demo/rgaImDemo.cpp',
        'samples/im2d_api_demo/args.cpp',
    ]
    demo_incdir = include_directories(
        'include',
        'im2d_api',
        'samples/utils',
        'samples/utils/allocator/include',
        'samples/utils/3rdparty/libdrm/include',
        'samples/utils/3rdparty/libdrm/include/libdrm'
    )
    executable(
        'rgaImDemo',
        demo_src,
        include_directories : demo_incdir,
        link_with : librga_shared,
        install : true,
    )
endif
