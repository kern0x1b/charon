#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
BUILD=${BUILD:-$(runs_fresh charon-uttypetags)}
xcrun clang -fobjc-arc -w "$here/probe.m" -framework CoreServices -framework Foundation -o "$BUILD/probe"
"$BUILD/probe" | tee "$BUILD/uttypetags.txt"
