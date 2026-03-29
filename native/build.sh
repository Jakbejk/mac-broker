#!/bin/bash

set -e

# Navigate to the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create build output directory
BUILD_DIR="$SCRIPT_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Compiler settings
COMPILER="clang"
HEADER_DIR="$SCRIPT_DIR/src/headers"
SOURCE_DIR="$SCRIPT_DIR/src"
OUTPUT_LIB="$BUILD_DIR/libMacBrokerBridge.dylib"

# Compile flags
CFLAGS="-fPIC -Wall -include wchar.h"
LDFLAGS="-dynamiclib"
FRAMEWORKS="-framework Foundation -framework Security -framework AppKit -framework WebKit"

echo "Building native library..."
echo "Source directory: $SOURCE_DIR"
echo "Build directory: $BUILD_DIR"
echo "Output library: $OUTPUT_LIB"

# Compile and link the Objective-C code
$COMPILER \
    $CFLAGS \
    -I"$HEADER_DIR" \
    "$SOURCE_DIR/MacBrokerBridge.m" \
    $LDFLAGS \
    $FRAMEWORKS \
    -o "$OUTPUT_LIB" \
    2>&1

echo "Build complete!"
echo "Library created at: $OUTPUT_LIB"
