set( CMAKE_SYSTEM_NAME Linux )
set( CMAKE_SYSTEM_PROCESSOR aarch64 )

set( SYSROOT "/opt/qcom-sysroot" )
set( CMAKE_SYSROOT "${SYSROOT}" )

set( target aarch64-qcom-linux )

set( CMAKE_C_COMPILER   clang )
set( CMAKE_CXX_COMPILER clang++ )

set( CMAKE_C_COMPILER_TARGET   ${target} )
set( CMAKE_CXX_COMPILER_TARGET ${target} )

set( CMAKE_AR      llvm-ar CACHE FILEPATH "archiver" )
set( CMAKE_RANLIB  llvm-ranlib CACHE FILEPATH "ranlib" )

set( CMAKE_FIND_ROOT_PATH "${SYSROOT}" )
set( CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER )
set( CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY )
set( CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY )

set( arch_c_flags "-march=armv8.2-a+fp16+dotprod --sysroot=${SYSROOT} --gcc-toolchain=${SYSROOT}" )
set( warn_c_flags "-Wno-format -Wno-unused-variable -Wno-unused-function -Wno-gnu-zero-variadic-macro-arguments" )

set( CMAKE_C_FLAGS_INIT   "${arch_c_flags} ${warn_c_flags}" )
set( CMAKE_CXX_FLAGS_INIT "${arch_c_flags} ${warn_c_flags}" )

set( CMAKE_C_FLAGS_RELEASE        "-O3 -DNDEBUG" CACHE STRING "" FORCE )
set( CMAKE_CXX_FLAGS_RELEASE      "-O3 -DNDEBUG" CACHE STRING "" FORCE )
