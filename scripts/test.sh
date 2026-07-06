#!/bin/sh
# `swift test` wrapper for Command Line Tools-only machines (no Xcode installed).
#
# The CLT ships Testing.framework outside the default search path, and its
# lib_TestingInterop.dylib in a directory the framework's own install-name
# arithmetic misses. Full-Xcode machines (and CI) can run plain `swift test`;
# this script makes the CLT case work identically.
set -e
cd "$(dirname "$0")/.."

if xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
    FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
else
    exec swift test "$@"
fi
