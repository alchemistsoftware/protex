#!/bin/bash

pushd "./bin"
zig build

cp -ruv ../data ../../build
