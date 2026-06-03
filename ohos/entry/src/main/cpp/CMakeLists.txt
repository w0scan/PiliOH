# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(media_kit_ohos_video)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVE_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# OHOS_ARCH is provided by the DevEco/hvigor CMake toolchain (e.g. "arm64-v8a").
if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()

# entry/libs/<abi> -- prebuilt libmpv.so.2 lives here and is auto-packaged.
set(PREBUILT_LIB_DIR ${NATIVE_ROOT_PATH}/../../../libs/${OHOS_ARCH})

include_directories(
    ${NATIVE_ROOT_PATH}
    ${NATIVE_ROOT_PATH}/include   # bundled mpv headers (mpv/client.h ...)
)

# Prebuilt libmpv (SONAME = libmpv.so.2), monolithic build with FFmpeg/libass
# statically linked; only needs system EGL/GLES/OHAudio at runtime.
add_library(mpv SHARED IMPORTED)
set_target_properties(mpv PROPERTIES
    IMPORTED_LOCATION ${PREBUILT_LIB_DIR}/libmpv.so.2)

add_library(media_kit_ohos_video SHARED
    napi_init.cpp
    media_kit_ohos_video.cpp)

target_link_libraries(media_kit_ohos_video PUBLIC
    mpv                       # libmpv.so.2
    libace_napi.z.so          # NAPI
    libnative_window.so       # OHNativeWindow + OH_NativeWindow_*
    EGL                       # libEGL.so
    GLESv3                    # libGLESv3.so
    libhilog_ndk.z.so)        # OH_LOG_*
