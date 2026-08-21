cmake_minimum_required(VERSION 3.12)

include(${CMAKE_SOURCE_DIR}/cmake/utils.cmake)

if (DEFINED BUILD_TOOLCHAINS_PATH AND EXISTS "${BUILD_TOOLCHAINS_PATH}")
    message(STATUS "Loading toolchain settings from ${BUILD_TOOLCHAINS_PATH}")
    include(${BUILD_TOOLCHAINS_PATH})
endif()

project(rga LANGUAGES C CXX)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Defaulting to Release build")
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the build type: Debug, Release, RelWithDebInfo, MinSizeRel."
        FORCE)
endif()

if(NOT DEFINED CMAKE_BUILD_TARGET OR CMAKE_BUILD_TARGET STREQUAL "")
    if(UNIX AND NOT ANDROID)
        set(CMAKE_BUILD_TARGET cmake_linux CACHE STRING "RGA build target" FORCE)
    endif()
endif()

option(RGA_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)
option(RGA_NATIVE_OPTIMIZATION "Optimize Release builds for the CPU running the compiler" ON)
option(RGA_ENABLE_LTO "Enable interprocedural/link-time optimization in Release builds" ON)
option(RGA_BUILD_SAMPLES "Build the im2d API demo" ON)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

add_library(COMMON_LIBS INTERFACE)

if(CMAKE_BUILD_TARGET STREQUAL android_ndk)
    message(STATUS "RGA target: Android NDK")
    add_compile_definitions(LINUX ANDROID_VNDK)
    add_compile_definitions(LOG_TAG=librga)
    target_link_libraries(COMMON_LIBS INTERFACE log)
elseif(CMAKE_BUILD_TARGET STREQUAL buildroot)
    message(STATUS "RGA target: Buildroot")
    add_compile_definitions(LINUX)
elseif(CMAKE_BUILD_TARGET STREQUAL cmake_linux)
    message(STATUS "RGA target: native Linux")
    add_compile_definitions(LINUX)
elseif(CMAKE_BUILD_TARGET STREQUAL rt_thread)
    message(STATUS "RGA target: RT-Thread")
    add_compile_definitions(LINUX RT_THREAD RGA_SYNC_DISABLE RGA_UTILS_DRM_DISABLE)
else()
    message(FATAL_ERROR "Unsupported CMAKE_BUILD_TARGET='${CMAKE_BUILD_TARGET}'")
endif()

if(NOT CMAKE_BUILD_TARGET STREQUAL rt_thread)
    find_package(Threads REQUIRED)
    target_link_libraries(COMMON_LIBS INTERFACE Threads::Threads)
    if(UNIX AND NOT APPLE)
        target_link_libraries(COMMON_LIBS INTERFACE m)
    endif()
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    add_compile_options(-Wall -Wextra -Wformat=2)
    # The strict policy is the default for Linux/Buildroot. Preserve the
    # historical Android/RT-Thread behavior, where external platform headers
    # and toolchains may intentionally carry warnings outside librga's control.
    if(RGA_WARNINGS_AS_ERRORS
       AND NOT CMAKE_BUILD_TARGET STREQUAL android_ndk
       AND NOT CMAKE_BUILD_TARGET STREQUAL rt_thread)
        add_compile_options(-Werror)
    endif()
endif()

if(RGA_NATIVE_OPTIMIZATION AND CMAKE_BUILD_TARGET STREQUAL cmake_linux)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang" OR CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
        add_compile_options($<$<CONFIG:Release>:-march=native> $<$<CONFIG:Release>:-mtune=native>)
    endif()
endif()

if(RGA_ENABLE_LTO AND NOT CMAKE_BUILD_TARGET STREQUAL rt_thread)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT RGA_IPO_SUPPORTED OUTPUT RGA_IPO_ERROR)
    if(RGA_IPO_SUPPORTED)
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
    else()
        message(WARNING "LTO/IPO requested but not supported: ${RGA_IPO_ERROR}")
    endif()
endif()

if (BUILD_WITH_VERSION STREQUAL true)
    im2d_api_extract_version()
endif()

# Sources common to every supported userspace build.
set(IM2D_SRCS
    core/utils/android_utils/src/android_utils.cpp
    core/utils/drm_utils/src/drm_utils.cpp
    core/utils/utils.cpp
    core/NormalRgaApi.cpp
    core/RgaUtils.cpp
    core/rga_sync.cpp
    im2d_api/src/im2d_log.cpp
    im2d_api/src/im2d_debugger.cpp
    im2d_api/src/im2d_context.cpp
    im2d_api/src/im2d_job.cpp
    im2d_api/src/im2d_impl.cpp
    im2d_api/src/im2d.cpp
)

set(IM2D_3RDPARTY_INCLUDE
    ./core/3rdparty/libdrm/include/drm
    ./core/3rdparty/android_hal
)

if(CMAKE_BUILD_TARGET STREQUAL rt_thread)
    set(IM2D_RT_THREAD_INCLUDE
        ${RTOS_BSP}/include/
        ${RTOS_BSP}/components/drivers/include/
        ${RTOS_BSP}/components/finsh
        ${RTOS_BSP}/bsp/rockchip/rk2118/
        ${RTOS_BSP}/rt-thread/include
        ${RTOS_BSP}/bsp/maix3/
        ${RTOS_BSP}/rt-thread/components/finsh/
        ${RTOS_BSP}/bsp/maix3/c908/
    )
    list(APPEND IM2D_3RDPARTY_INCLUDE ${IM2D_RT_THREAD_INCLUDE})
endif()

set(IM2D_INCLUDE
    ./
    ./im2d_api
    ./include
    ./core
    ./core/hardware
    ./core/utils
    ./core/adapter
    ${IM2D_3RDPARTY_INCLUDE}
)

# C++ core used by normal Linux/Android builds. RT-Thread intentionally uses
# the smaller adapter path required by that operating system.
set(IM2D_CORE_CPP_SRCS
    core/RockchipRga.cpp
    core/GrallocOps.cpp
    core/NormalRga.cpp
    core/RgaApi.cpp
    core/RgaUtils_symbol.cpp
    core/rga_gralloc.cpp
)

set(IM2D_3RDPARTY_CPP_INCLUDE
    hardware/libhardware/modules/gralloc
    system/core/liblog/includeNDROID_NDK_REVISION_REGEX
    system/core/libion/kernel-headers
)

set(IM2D_PUBLIC_HEADER
    im2d_api/im2d_version.h
    im2d_api/im2d_type.h
    im2d_api/im2d_buffer.h
    im2d_api/im2d_common.h
    im2d_api/im2d_single.h
    im2d_api/im2d_task.h
    im2d_api/im2d_mpi.h
    im2d_api/im2d_expand.h
    im2d_api/im2d.h
    include/rga.h
    include/RgaUtils.h
)

set(IM2D_PUBLIC_CPP_HEADER
    im2d_api/im2d.hpp
    include/drmrga.h
    include/RgaApi.h
    include/RockchipRga.h
    include/RgaSingleton.h
    include/RgaMutex.h
    include/GrallocOps.h
)

if (RGA_SOURCE_CODE_TYPE STREQUAL c)
    set_source_files_properties(${IM2D_SRCS} PROPERTIES LANGUAGE C COMPILE_FLAGS "-x c")
elseif(NOT CMAKE_BUILD_TARGET STREQUAL rt_thread)
    list(APPEND IM2D_SRCS ${IM2D_CORE_CPP_SRCS})
    list(APPEND IM2D_INCLUDE ${IM2D_3RDPARTY_CPP_INCLUDE})
    list(APPEND IM2D_PUBLIC_HEADER ${IM2D_PUBLIC_CPP_HEADER})
endif()

set(OBJECT_NAME ${PROJECT_NAME}-object)
add_library(${OBJECT_NAME} OBJECT ${IM2D_SRCS})
target_include_directories(${OBJECT_NAME} PRIVATE ${IM2D_INCLUDE})
set_target_properties(${OBJECT_NAME} PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(${OBJECT_NAME} PRIVATE UN_NEED_GL)
target_link_libraries(${OBJECT_NAME} PRIVATE COMMON_LIBS)

if(CMAKE_BUILD_TARGET STREQUAL cmake_linux)
    target_compile_options(${OBJECT_NAME} PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions;-fno-rtti>
        -fdata-sections -ffunction-sections)
endif()

set(SHARED_LIB_NAME ${PROJECT_NAME})
add_library(${SHARED_LIB_NAME} SHARED $<TARGET_OBJECTS:${OBJECT_NAME}>)
target_include_directories(${SHARED_LIB_NAME} PRIVATE ${IM2D_INCLUDE})
target_link_libraries(${SHARED_LIB_NAME} PRIVATE COMMON_LIBS)
if(CMAKE_BUILD_TARGET STREQUAL cmake_linux AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_link_options(${SHARED_LIB_NAME} PRIVATE -Wl,--gc-sections)
endif()

if(NOT DEFINED IM2D_API_VERSION)
    set_target_properties(${SHARED_LIB_NAME} PROPERTIES PUBLIC_HEADER "${IM2D_PUBLIC_HEADER}")
else()
    message(STATUS "Generated im2d API version: v${IM2D_API_VERSION}")
    set_target_properties(${SHARED_LIB_NAME} PROPERTIES
        PUBLIC_HEADER "${IM2D_PUBLIC_HEADER}"
        VERSION ${IM2D_API_VERSION}
        SOVERSION ${IM2D_API_VERSION_MAJOR})
endif()

set(STATIC_LIB_NAME ${PROJECT_NAME}-static)
add_library(${STATIC_LIB_NAME} STATIC $<TARGET_OBJECTS:${OBJECT_NAME}>)
target_include_directories(${STATIC_LIB_NAME} PRIVATE ${IM2D_INCLUDE})
set_target_properties(${STATIC_LIB_NAME} PROPERTIES OUTPUT_NAME ${PROJECT_NAME})
target_link_libraries(${STATIC_LIB_NAME} PRIVATE COMMON_LIBS)

if (NOT DEFINED CMAKE_INSTALL_LIBDIR)
    set(CMAKE_INSTALL_LIBDIR lib)
endif()
if (NOT DEFINED CMAKE_INSTALL_INCLUDEDIR)
    set(CMAKE_INSTALL_INCLUDEDIR include)
endif()

install(TARGETS ${SHARED_LIB_NAME}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(TARGETS ${STATIC_LIB_NAME}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

if (RGA_BUILD_SAMPLES AND NOT CMAKE_BUILD_TARGET STREQUAL rt_thread)
    add_subdirectory(samples/im2d_api_demo)
    if (DEFINED RGA_ENABLE_INSTALL_SAMPLES)
        install(DIRECTORY samples DESTINATION ${CMAKE_INSTALL_PREFIX})
    endif()
endif()
