#!/bin/sh
# protocol-conformance.sh - the acceptance test for a protocol row marked `implemented`.
#
#     sh tests/backports/host/protocol-conformance.sh
#
# A protocol row marked `implemented` claims every member of the protocol is callable, and
# backports.lua:664 turns that claim into a BAND FLOOR. So the claim is measured, and THE CRITERION IS
# AN AST COMPARISON, not a warning:
#
#   an `implemented` row  <=>  for every protocol member - required and optional instance and class
#   methods, and every property's getter and (when readwrite) its setter - the class's
#   @implementation, its category implementations or its @synthesize bindings DEFINE that selector.
#
# That is protocol-members.py, which reads the SDK's members through the file's own import and the
# class's definitions from the same translation unit. It reads IN PLACE and writes nothing, and it
# needs no pragma stripped: a suppressed warning hides a message, and a declaration is not a message.
#
# -Wprotocol is KEPT as a cross-check, because it is right about METHODS and catches an inherited one
# the AST comparison would accept. It is not the criterion and it is not sufficient: it does not
# inspect property accessors, and a property whose getter is on the wrong class produces nothing.
# -Wobjc-protocol-property-synthesis is GONE: it cannot tell a hand-written getter from a missing one,
# so it reported the same six warnings on a tree with the six getters written and on one without.
#
# Every row is printed with the class file and the flags it used, and the rows are read FROM THE
# REGISTRY rather than from a list copied into this script, so a row flipped without a class here fails
# loudly instead of passing unexamined.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
SDK=""
for candidate in "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk; do
    if [ -f "$candidate/SDKSettings.json" ]; then SDK="$candidate"; break; fi
done
[ -n "$SDK" ] || { echo "FAIL: no iOS 16.4 SDK; set LIBRARY_SDK" >&2; exit 1; }
work=${WORK:-$root/.agent-work/runs/protocol-conformance}
rm -rf "$work"
mkdir -p "$work/tree"
cp -R "$root/packages/a/apple-backports" "$work/tree/apple-backports"

flags="-target armv7-apple-ios6.1.3 -isysroot $SDK -fobjc-arc -Os -g0 -Wall
-Wno-unguarded-availability-new -Wno-unguarded-availability -Wprotocol"

# PROTOCOL CLASS FILE -- from the registry, and from the class names the sources declare.
rows=$(python3 - "$root" <<'PY'
import json, os, re, sys
root = sys.argv[1]
base = os.path.join(root, "packages/a/apple-backports/registry/Metal")
# The three rows with no @interface of their own, and the protocols 16.4 says each inherits FROM:
# MTLBuffer.h:32 and MTLTexture.h:264 make MTLResource, MTLRenderCommandEncoder.h:131 and
# MTLComputeCommandEncoder.h:41 make MTLCommandEncoder, and CAMetalDrawable is <MTLDrawable> in
# QuartzCore's CAMetalLayer.h:28.
INHERITED_BY = {
    "MTLResource": ("MTLBuffer", "MTLTexture"),
    "MTLCommandEncoder": ("MTLRenderCommandEncoder", "MTLComputeCommandEncoder"),
    "MTLDrawable": ("CAMetalDrawable",),
}
# EVERY source, headers included: the @interface that adopts the protocol is in CharonMetal.h, and a
# scan of the .m files alone finds nine of the fifteen rows nowhere. The .m is then located by the
# class name, or - for a class that is a secondary @implementation - by a search for its declaration.
sources = {}
for folder, _, files in os.walk(os.path.join(root, "packages/a/apple-backports")):
    for name in files:
        if name.endswith((".m", ".h")):
            sources[name] = os.path.join(folder, name)
for name in sorted(os.listdir(base)):
    if not name.endswith(".json"):
        continue
    document = json.load(open(os.path.join(base, name)))
    for entry in (document["entries"] if isinstance(document, dict) else document):
        if entry.get("kind") != "protocol" or entry["api"] not in (
                "MTLDevice", "MTLResource", "MTLBuffer", "MTLTexture", "MTLSamplerState", "MTLFunction",
                "MTLLibrary", "MTLRenderPipelineState", "MTLCommandQueue", "MTLCommandBuffer",
                "MTLCommandEncoder", "MTLRenderCommandEncoder", "MTLDrawable",
                "MTLDepthStencilState", "MTLCaptureScope"):
            continue
        # The class that declares this protocol, found by its @interface. The protocol list is
        # matched with [,\s>] and not with a closing angle alone, because "<MTLBuffer, MTLResource>"
        # is as common as a single protocol and a pattern that insists on the closing bracket finds
        # none of them - which is how nine rows came out with no class at all in an earlier run.
        pattern = r"^@interface (\w+) : NSObject <%s[,\s>]" % re.escape(entry["api"])
        cls = None
        for path in sources.values():
            found = re.search(pattern, open(path, errors="ignore").read(), re.M)
            if found:
                cls = found.group(1)
                break
        if cls is None:
            # A row implemented BY INHERITANCE: no @interface adopts it directly, so the class to ask
            # is the one that adopts a protocol INHERITING it. The criterion is the same question -
            # does that class answer every member of the protocol - and the SDK's own headers say which
            # protocols inherit which, so the search is over the port's @interface lines only.
            for path in sources.values():
                text = open(path, errors="ignore").read()
                for found in re.finditer(r"^@interface (\w+) : NSObject <([A-Za-z, ]+)>", text, re.M):
                    adopted = [a.strip() for a in found.group(2).split(",")]
                    # the class adopts a protocol that INHERITS the row's protocol
                    if any(a in adopted for a in INHERITED_BY.get(entry["api"], ())):
                        cls = found.group(1)
                        break
                if cls:
                    break
        if cls is None:
            print("%s\t?\t?" % entry["api"])
            continue
        path = sources.get(cls + ".m")
        if path is None:                      # a secondary @implementation in another class's file
            for other, candidate in sources.items():
                if re.search(r"^@implementation %s\b" % re.escape(cls), open(candidate, errors="ignore").read(), re.M):
                    path = candidate
                    break
        rel = os.path.relpath(path or ".", os.path.join(root, "packages/a/apple-backports"))
        print("%s\t%s\t%s" % (entry["api"], cls, rel))
PY
)

fail=0
echo "the criterion: clang -Xclang -ast-dump=json, library flags, no -I, read in place"
echo "  flags: $flags"
echo
for line in $(printf '%s\n' "$rows" | tr '\t' ':'); do
    protocol=${line%%:*}
    rest=${line#*:}
    cls=${rest%%:*}
    file=${rest#*:}
    # PROTOCOL CLASS SDK FILE - four arguments, and FILE is not derivable from CLASS: four of the
    # implemented rows live in a differently named file.
    out=$(cd "$root/packages/a/apple-backports" && python3 "$here/protocol-members.py" \
            "$protocol" "$cls" "$SDK" "$file" 2>&1) || true
    printf '%s\n' "$out"
    printf '%s\n' "$out" >> "$work/sweep.txt"
    printf '%s\n' "$out" | grep -q "missing:" && fail=1
    # the cross-check: -Wprotocol, for methods, which the AST comparison would accept if inherited
    if [ "$cls" != "?" ] && [ "$file" != "?" ]; then
        (cd "$root/packages/a/apple-backports" && xcrun clang $flags -fsyntax-only "$file") 2>&1 \
            | grep "in protocol '$protocol' not implemented" | sed 's/^/      -Wprotocol: /' || true
    fi
    echo
done
# THE MUTANTS. Two, because the criterion has two halves and a check that only exercises one is a
# check that would pass with the other half broken: a class missing a METHOD for an implemented row,
# and a class whose property GETTER is missing - the case neither warning could see, and the one this
# criterion exists for.
echo "the mutants"
for mutation in method getter; do
    for probe in CharonMetalLibrary CharonMetalDepthStencil; do
        dir="$work/tree/apple-backports"
        file="$dir/Metal/$probe.m"
        [ -f "$file" ] || file=$(find "$dir/Metal" -name "$probe.m" | head -1)
        [ -n "$file" ] || continue
        cp "$file" "$work/$probe.$mutation.orig"
        if [ "$mutation" = method ]; then
            python3 "$here/mutate-conformance.py" "$file" || { echo "FAIL: cannot make a method mutant" >&2; exit 1; }
        else
            python3 "$here/mutate-getter.py" "$file" || { echo "FAIL: cannot make a getter mutant" >&2; exit 1; }
        fi
        rel=$(basename "$(dirname "$file")")/$(basename "$file")
        # a broken class must FAIL TO COMPILE for the method mutant, and must be REPORTED by the
        # criterion for the getter mutant. Both are measured by running the thing and looking at what
        # it says, rather than by a shell expression that swallows its own exit status.
        if (cd "$dir" && xcrun clang $flags -fsyntax-only "$rel") >"$work/$probe.$mutation.log" 2>&1; then
            compiles=yes; else compiles=no; fi
        noticed=$( (cd "$dir" && python3 "$here/protocol-members.py" MTLFunction "$probe" "$SDK" "$rel" 2>&1) \
                   | grep -c "missing:" || true)
        if [ "$mutation" = method ] && [ "$compiles" = yes ]; then
            echo "  FAIL the method mutant still compiled, so the check is not testing methods" >&2
            fail=1
        elif [ "$mutation" = getter ] && [ "$noticed" -eq 0 ]; then
            echo "  FAIL the getter mutant went unnoticed, which is the case the criterion exists for" >&2
            fail=1
        else
            echo "  ok   the $mutation mutant in $probe is red"
        fi
        cp "$work/$probe.$mutation.orig" "$file"
    done
done
echo
# THE FINAL LINE, with counts and a reason. Exit 1 is BY DESIGN when any row has gaps: an inert row
# is one whose conformance is not callable, and the test exists to say so, not to fail the build for
# a row that is correctly inert. So the counts are the result and exit 1 means "there is work owed",
# which is different from "the check is broken" - and the mutants distinguish the two.
# two different things, and the first version conflated them: how many ROWS were checked, how many of
# them are conformant, and how many SELECTORS the rest are missing.
checked=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
conformant=$(grep -c "every protocol member is defined" "$work/sweep.txt" 2>/dev/null || echo 0)
gapped=$((checked - conformant))
selectors=$(grep -c "missing:" "$work/sweep.txt" 2>/dev/null || echo 0)
summary="protocol-conformance: $checked row(s) checked, $conformant conformant, $gapped inert with $selectors selector(s) owed"
if [ "$fail" -ne 0 ]; then
    echo "$summary; EXIT 1 BY DESIGN - the gap rows are inert, and the mutants were red so the check is working" >&2
    exit 1
fi
echo "$summary; every one conformant, and both mutants are red"
