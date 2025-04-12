#! /usr/bin/bash

mkdir -p build
cd build

cmake .. -DMINIO_CPP_TEST=ON -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_PREFIX_PATH=$RECIPE_DIR/cmake
make -j$(nproc)
make install
