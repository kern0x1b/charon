#!/bin/sh
# braille-table-test.sh - the braille tables against the Unified English Braille rulebook's own
# examples.
#
# The host's AXBrailleTranslator is no oracle here: it answers nil for a table built by hand,
# because a table's dot patterns are a provider's data and the host has none installed for one
# (measured; facts/Accessibility/Accessibility.md). The standard is the check, and every
# expectation is written out by hand in braille-table-test.m rather than sampled - two of the
# three errors this package had were in the tables and the host could not have found either.
#
# Usage: sh tests/backports/accessibility/braille-table-test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
xcrun clang -target arm64-apple-macos26.0 -isysroot "$(xcrun --show-sdk-path)" -fobjc-arc -O0 \
    -DCHARON_HALF_PORT=1 -DCHARON_BRAILLE_ONLY=1 \
    -DAXBrailleTable=CharonPortBrailleTable \
    -DAXBrailleTranslationResult=CharonPortBrailleTranslationResult \
    -DAXBrailleTranslator=CharonPortBrailleTranslator \
    -I"$root/packages/a/apple-backports/Accessibility" \
    -I"$root/packages/a/apple-backports/Intents" \
    "$here/braille-table-test.m" \
    "$root/packages/a/apple-backports/Accessibility/CharonBraille.m" \
    "$root/packages/a/apple-backports/Intents/CharonIntentsCoding.m" \
    -framework Foundation -framework CoreLocation -o "$build/table-test" 2>"$build/build.log" || {
        echo "the table test did not build; $build/build.log says why" >&2
        tail -20 "$build/build.log" >&2
        exit 1
    }
"$build/table-test"
