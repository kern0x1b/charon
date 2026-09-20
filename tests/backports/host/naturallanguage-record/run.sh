#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
xcrun clang -fobjc-arc -w -I"$device" "$here/record.m" -framework NaturalLanguage -framework Foundation -o "$build/record"
"$build/record" "$device/naturallanguage-expectations.h"
echo "records: $(grep -c '^    "' "$device/naturallanguage-expectations.h")"
