set( CMAKE_SYSTEM_NAME Linux )
set( CMAKE_SYSTEM_PROCESSOR aarch64 )

set( CMAKE_SYSROOT "/home/binfeng/work/qual/toolchain-gcc-112/tmp/sysroots/qcm6490" )

set( CMAKE_C_COMPILER   aarch64-qcom-linux-gcc )
set( CMAKE_CXX_COMPILER aarch64-qcom-linux-g++ )

set( CMAKE_AR      aarch64-qcom-linux-ar CACHE FILEPATH "archiver" )
set( CMAKE_RANLIB  aarch64-qcom-linux-ranlib CACHE FILEPATH "ranlib" )

set( CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}" )

set( CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER )
set( CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY )

set( arch_c_flags "-march=armv8.2-a+fp16+dotprod -ftree-vectorize -ffast-math -fno-finite-math-only" )
set( warn_c_flags "-Wno-format -Wno-unused-variable -Wno-unused-function" )

set( CMAKE_C_FLAGS_INIT   "${arch_c_flags} ${warn_c_flags}" )
set( CMAKE_CXX_FLAGS_INIT "${arch_c_flags} ${warn_c_flags}" )

set( CMAKE_C_FLAGS_RELEASE        "-O3 -DNDEBUG" CACHE STRING "" FORCE )
set( CMAKE_CXX_FLAGS_RELEASE      "-O3 -DNDEBUG" CACHE STRING "" FORCE )
