#!/bin/bash

pushd "./bin"
zig build
mkdir -p ../../build/data
