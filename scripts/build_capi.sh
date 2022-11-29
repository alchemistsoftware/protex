#!/bin/bash

export LD_LIBRARY_PATH="./lib/"
gcc src/capi.c -g -L ./lib/ -L /usr/local/lib/ -Wl,-ljpc,-lhs_runtime -o woot
