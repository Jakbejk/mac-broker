#!/bin/bash
# Navigate to the script's directory
cd "$(dirname "$0")"

# Compile the Objective-C code into a dynamic library
# -dynamiclib: Creates the .dylib
# -framework Foundation: Links the core macOS framework
# -o: Output file name
clang -dynamiclib -framework Foundation -o libmacbrokerbridge.dylib MacBrokerBridge.m

echo "Successfully built libmacbrokerbridge.dylib"