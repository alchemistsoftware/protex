#!/bin/bash


# Copy index.html, style.css and assets/ to build dir

cp -vu ./*.ts ../../build/
cp -vu ./index.html ../../build/
cp -vu ./style.css ../../build/
cp -vur ./assets ../../build/

cp -vu ./package.json ../../build
cp -vu ./forge.config.js ../../build
cp -vu ./tsconfig.json ../../build

pushd "../../build"

# Install node bs

npm i

# Transpile ts

./node_modules/.bin/tsc -b
