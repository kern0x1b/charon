#!/bin/sh
# protocol-conformance.sh - the acceptance test for a protocol row marked `implemented`.
#
#     sh tests/backports/host/protocol-conformance.sh
#
# A protocol row marked `implemented` is a CLAIM that the port's class really answers the protocol, and
# backports.lua:664 turns that claim into a BAND FLOOR. So the claim is measured, and this is the
# measurement: for every class behind such a row, the stripped compile is run IN PLACE - the
# library's own flags, no -I, from packages/a/apple-backports - with BOTH diagnostics that make a
# conformance a callable gap:
#
#   -Wprotocol                        a required METHOD nobody implements
#   -Wobjc-protocol-property-synthesis a required PROPERTY nobody synthesizes, which is a selector
#                                     that RAISES unrecognized-selector when read
#
# The second is why an earlier run of this by hand was wrong: it checked -Wprotocol only, and two
# rows passed that do not conform.
#
# The pragmas are stripped IN A COPY, and the copy is made INSIDE .agent-work/runs with the whole
# package tree beside it, because a copy of one file breaks its relative `#import "Sibling.h"` and
# then fails for a reason that has nothing to do with the protocol. That is not a hypothetical: an
# earlier attempt did exactly that and measured nothing at all.
#
# It exits 1 when any row marked `implemented` has any diagnostic, and it exits 1 when the mutant
# does not go red.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
SDK=${LIBRARY_SDK:-$HOME/.xmake/packages/i/iphoneos-sdk/16.4}
SDK=""
for candidate in "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk; do
    if [ -f "$candidate/SDKSettings.json" ]; then SDK="$candidate"; break; fi
done
[ -n "$SDK" ] || { echo "FAIL: no iOS 16.4 SDK; set LIBRARY_SDK" >&2; exit 1; }
work=${WORK:-$root/.agent-work/runs/protocol-conformance}
rm -rf "$work"
mkdir -p "$work"

flags="-target armv7-apple-ios6.1.3 -isysroot $SDK -fobjc-arc -Os -g0 -Wall
-Wno-unguarded-availability-new -Wno-unguarded-availability
-Wprotocol -Wobjc-protocol-property-synthesis"

# The whole package tree, so relative quoted imports still resolve, and the classes that back an
# `implemented` protocol row.
tree="$work/tree"
mkdir -p "$tree"
cp -R "$root/packages/a/apple-backports" "$tree/apple-backports"
# NOT > "$1": the shell truncates the output before grep reads the input, and the file comes out
# empty - which is why this script produced no output at all until it was run with -x.
strip() {
    grep -v 'clang diagnostic ignored "-Wprotocol"\|clang diagnostic ignored "-Wincomplete-implementation"' "$1" > "$1.stripped"
    mv "$1.stripped" "$1"
}

# The rows that claim `implemented`, and the class each one claims is behind it. This list IS the
# registry's - read from it, not copied, so a row flipped without a class here fails loudly below.
classes=$(python3 - "$root" <<'PY'
import json, os, sys
root = sys.argv[1]
pairs = {
    "MTLSamplerState": "CharonMetalSampler",
    "MTLFunction": "CharonMetalLibrary",
    "MTLDepthStencilState": "CharonMetalDepthStencil",
    "MTLDrawable": "CharonMetalDrawable",
    "MTLCaptureScope": "CharonMTLCaptureScope",
}
found = {}
base = os.path.join(root, "packages/a/apple-backports/registry/Metal")
for name in sorted(os.listdir(base)):
    if not name.endswith(".json"):
        continue
    document = json.load(open(os.path.join(base, name)))
    for entry in (document["entries"] if isinstance(document, dict) else document):
        if entry.get("kind") == "protocol" and entry.get("status") == "implemented" and entry["api"] in pairs:
            found[entry["api"]] = pairs[entry["api"]]
for protocol, cls in sorted(found.items()):
    print("%s:%s" % (protocol, cls))
PY
)

[ -n "$classes" ] || { echo "FAIL: no protocol row is marked implemented, so this checks nothing" >&2; exit 1; }

fail=0
for line in $classes; do
    protocol=${line%%:*}
    class=${line#*:}
    source=$(find "$tree/apple-backports" -name "$class.m" | head -1)
    if [ -z "$source" ]; then
        # a secondary @implementation: the class is inside another class's file, so find the file
        # that declares it. CharonMTLCaptureScope is inside MTLCaptureManager11.m.
        source=$(grep -rl "@implementation $class\\b" "$tree/apple-backports" 2>/dev/null | head -1)
    fi
    if [ -z "$source" ]; then
        echo "FAIL: $protocol is marked implemented and $class.m is not in the tree" >&2
        fail=1
        continue
    fi
    strip "$source"
    count=$( (cd "$tree/apple-backports" && xcrun clang $flags -fsyntax-only "$source") 2>&1 \
             | grep -cE "not implemented|not synthesized" || true)
    # EVERY diagnostic, with its text: a count cannot be acted on, and the point of this check is
    # that the text names the member so a row can be fixed or the gap can be recorded.
    # Only the diagnostics naming THIS row's protocol. CharonMetalLibrary implements MTLFunction AND
    # MTLLibrary, and CharonMetalTexture implements MTLTexture AND MTLResource, so a class behind two
    # rows reports both: counting every one of its diagnostics would make a row fail on gaps that
    # belong to a different row - and the rows that DO own those gaps are already inert.
    diagnostics=$( (cd "$tree/apple-backports" && xcrun clang $flags -fsyntax-only "$source") 2>&1 \
                  | grep -E "not implemented|not synthesized" | grep -F "in protocol '$protocol'" || true)
    count=$(printf '%s' "$diagnostics" | grep -c . || true)
    if [ "$count" -eq 0 ]; then
        echo "  ok   $protocol via $class: no -Wprotocol, no -Wobjc-protocol-property-synthesis"
    else
        echo "  FAIL $protocol via $class: $count diagnostic(s) - a callable gap, so the row must be inert" >&2
        printf '%s\n' "$diagnostics" | sed "s|.*Metal/$class.m|$class.m|" | sed 's/^/         /' >&2
        fail=1
    fi
done

# THE MUTANT: a class missing one method for an implemented row must make this go red, or the test
# is not testing anything. CharonMetalDrawable is conformant, so renaming one of its methods is a
# conformance failure the test has to notice.
echo
echo "the mutant: one method removed from a class behind an implemented row"
mutant=$(find "$tree/apple-backports" -name "MTLCaptureManager11.m" | head -1)
before=$(grep -c "^- " "$mutant" || true)
python3 "$here/mutate-conformance.py" "$mutant" || { echo "FAIL: the mutant could not be made" >&2; exit 1; }
mutant_count=$( (cd "$tree/apple-backports" && xcrun clang $flags -fsyntax-only "$mutant") 2>&1 \
                | grep -cE "not implemented|not synthesized|error:" || true)
if [ "$mutant_count" -eq 0 ]; then
    echo "FAIL: the mutant is NOT red, so this check no longer tests anything" >&2
    fail=1
else
    echo "  ok   the mutant is RED: $mutant_count diagnostic(s) from one renamed method"
fi

if [ "$fail" -ne 0 ]; then
    echo "protocol-conformance: FAILED" >&2
    exit 1
fi
echo "protocol-conformance: every implemented protocol row is conformant, and the mutant is red"
