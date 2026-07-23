set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(OE_SYSROOT "/usr/local/oecore-x86_64/sysroots/cortexa78c-oe-linux")
set(OE_TOOLCHAIN_BIN "/usr/local/oecore-x86_64/sysroots/x86_64-oesdk-linux/usr/bin/aarch64-oe-linux")

if(NOT IS_DIRECTORY "${OE_SYSROOT}")
    message(FATAL_ERROR "OE sysroot not found: ${OE_SYSROOT}. Run inside byuns-rust-toolchain:local image.")
endif()

set(CMAKE_SYSROOT "${OE_SYSROOT}")

set(CMAKE_C_COMPILER   "${OE_TOOLCHAIN_BIN}/aarch64-oe-linux-gcc")
set(CMAKE_CXX_COMPILER "${OE_TOOLCHAIN_BIN}/aarch64-oe-linux-g++")
set(CMAKE_AR      "${OE_TOOLCHAIN_BIN}/aarch64-oe-linux-ar")
set(CMAKE_RANLIB  "${OE_TOOLCHAIN_BIN}/aarch64-oe-linux-ranlib")
set(CMAKE_STRIP   "${OE_TOOLCHAIN_BIN}/aarch64-oe-linux-strip")

set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_C_FLAGS   "-mcpu=cortex-a78c -march=armv8.2-a+crypto -mbranch-protection=standard -fstack-protector-strong -D_FORTIFY_SOURCE=2")
set(CMAKE_CXX_FLAGS "${CMAKE_C_FLAGS}")

set(CMAKE_C_FLAGS_RELEASE        "-O3 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE      "-O3 -DNDEBUG" CACHE STRING "" FORCE)

message(STATUS "Using OE-Linux aarch64 toolchain, sysroot=${CMAKE_SYSROOT}")
