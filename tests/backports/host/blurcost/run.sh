#!/bin/sh
# run.sh -- what the blur's shading costs, and so how much of a UIVisualEffectView refresh has to be
# on the main thread at all.
#
# Compiles the port's own CharonBlur.m against a C shim for its Objective-C header
# (blurcost/CharonBlur.h) and times charon_blur_pixels at the three sizes
# packages/a/apple-backports/facts/UIKit/UIVisualEffect.md reports a whole refresh at. That is the
# BEFORE figure for moving the shading off the main thread: the read stays there whatever happens, and
# this is not it.
#
# The shim is a copy, not a -I path: CharonBlur.m includes its header with quotes, and a quoted include
# looks in the including file's own directory before any -I, so the package's Objective-C header wins
# from wherever the compiler is run. The source is therefore copied beside the shim -- and `cmp` says
# the copy is the package's file, so a measurement cannot be taken against a source that has drifted
# from the one the port ships.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
sources=${BLURCOST_SOURCES:-$root/packages/a/apple-backports/UIKit}
build=${BLURCOST_BUILD:-${TMPDIR:-/tmp}/charon-blurcost}
rm -rf "$build"
mkdir -p "$build"

cp "$here/CharonBlur.h" "$build/CharonBlur.h"
cp "$sources/CharonBlur.m" "$build/CharonBlur.m"
if ! cmp -s "$sources/CharonBlur.m" "$build/CharonBlur.m"; then
    echo "blurcost: the copy of CharonBlur.m differs from the package's; refusing to measure" >&2
    exit 2
fi
printf '  source: %s\n' "$sources/CharonBlur.m" >&2

cc -O2 -Wall -Wno-unused-parameter -I"$build" -o "$build/blurcost" "$here/blurcost.c" "$build/CharonBlur.m"
"$build/blurcost"
