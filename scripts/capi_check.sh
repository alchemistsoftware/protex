#!/bin/bash

# Stop script on error
set -e

# NOTE(cjb): Can I get this from build.zig?
DataDir="./data"
SourceDir="./src"
BinsDir="./bin"
ExePath="${BinsDir}/capi_check"
LibDirFlags="-L ./lib/ -L /usr/local/lib/"
LinkerFlags="-lgracie,-lhs_runtime"
IncludeFlags="-I/usr/include/hs"
CompilerFlags="-g"
SourceFiles="${SourceDir}/capi_check.c"

# Build lib
mkdir -pv $BinsDir # zig build should take care of this... but just in case
zig build          # becuase gcc depends on it

# Compile capi
gcc $SourceFiles $CompilerFlags $IncludeFlags $LibDirFlags -Wl,$LinkerFlags -o $ExePath

# Run packager
echo "*----------*"
echo "| packager |"
echo "*----------*"
$BinsDir/packager $DataDir/patterns #TODO(cjb): Have packager specify artifact path
ln -Pvf $DataDir/gracie.bin.0.0.1 $DataDir/gracie.bin

# Run capi
echo "*----------*"
echo "|capi_check|"
echo "*----------*"
./$ExePath
