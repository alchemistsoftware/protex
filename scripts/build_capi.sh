#!/bin/bash

zig build
export LD_LIBRARY_PATH="./lib/"
gcc src/capi.c -g -I/usr/include/hs -L ./lib/ -L /usr/local/lib/ -Wl,-ljpc,-lhs_runtime -o woot
