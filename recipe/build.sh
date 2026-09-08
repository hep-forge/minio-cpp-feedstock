#! /usr/bin/bash

mkdir -p build
cd build

# ${CMAKE_ARGS} carries conda-build's own -DCMAKE_BUILD_TYPE=Release
# (plus toolchain/strip paths) -- omitting it leaves CMAKE_BUILD_TYPE
# unset (this project's own CMakeLists.txt never defaults it either),
# producing an unoptimized, unstripped debug-info binary.
# Upstream is C++17 code: types.h declares `DeleteObject() = default;`
# and examples/ brace-initialize it. A defaulted ctor is user-declared
# but not user-provided, so the struct stays an aggregate in C++17 --
# but C++20 tightened the rule to "no user-declared constructors", which
# makes `DeleteObject{"my-object1"}` a hard error. The project asks for
# cxx_std_17 via target_compile_features, which is only a *minimum*, so
# CMake emits no -std flag and the compiler default wins. That was fine
# until conda-forge moved the default compiler to GCC 16, whose default
# is C++20. Pin the standard explicitly so the toolchain default cannot
# silently change the language dialect out from under this source.
cmake .. ${CMAKE_ARGS} -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DMINIO_CPP_TEST=ON -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_PREFIX_PATH=$RECIPE_DIR/cmake
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
make -j$NPROC
make install
