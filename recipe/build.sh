#! /usr/bin/bash

mkdir -p build
cd build

cmake .. -DMINIO_CPP_TEST=ON -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_PREFIX_PATH=$RECIPE_DIR/cmake
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
make -j$NPROC
make install
