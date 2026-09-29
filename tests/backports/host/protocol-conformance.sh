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
echo "the mutants, on rows other than the one the criterion most often catches"
# Each mutant removes a member the PROTOCOL REQUIRES and that class DEFINES, asked of
# protocol-members.py rather than guessed: an earlier mutator renamed whichever method came first in
# the file, which for CharonMetalLibrary was -functionNames - a method no protocol asks for, so the
# class still compiled and the mutant read green while removing nothing that mattered.
mutant_runs=0
mutant_red=0
for row in "MTLFunction:CharonMetalFunction:Metal/CharonMetalLibrary.m" \
           "MTLDepthStencilState:CharonMetalDepthStencil:Metal/CharonMetalDepthStencil.m" \
           "MTLCaptureScope:CharonMTLCaptureScope:Metal/MTLCaptureManager11.m"; do
    protocol=${row%%:*}; rest=${row#*:}; cls=${rest%%:*}; file=${rest#*:}
    for mutation in method getter; do
        mutant_runs=$((mutant_runs + 1))
        # the mutation happens in the SCRATCH TREE, never in the checkout: the file is copied back
        # from the tree afterwards, so a run leaves no change behind
        tree="$work/tree/apple-backports"
        cp "$root/packages/a/apple-backports/$file" "$tree/$file"
        removed=$(cd "$tree" && python3 "$here/${MUTATOR:-mutate-member.py}" "$protocol" "$cls" "$SDK" \
                      "$file" "$mutation" 2>&1 | head -1)
        reported=$( (cd "$tree" && python3 "$here/protocol-members.py" "$protocol" "$cls" "$SDK" \
                       "$file") 2>&1 | grep -c "missing:" || true)
        if [ "$reported" -gt 0 ]; then
            mutant_red=$((mutant_red + 1))
            echo "  ok   $mutation mutant on $protocol via $cls: $removed -> $reported selector(s) missing"
        else
            echo "  FAIL the $mutation mutant on $protocol via $cls went unnoticed: $removed" >&2
            fail=1
        fi
    done
done

# THE FINAL LINE, with counts and a reason. EXIT 1 IS BY DESIGN and means "work is owed": an inert row
# is one whose conformance is not callable, and the test exists to say so. It is NOT the same as a
# broken check, and the mutant count is what tells the two apart - so a non-zero exit with fewer than
# every mutant red means the CHECK is broken, which is a different statement and a louder one.
checked=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
conformant=$(grep -c "every protocol member is defined" "$work/sweep.txt" 2>/dev/null || echo 0)
gapped=$((checked - conformant))
selectors=$(grep -c "missing:" "$work/sweep.txt" 2>/dev/null || echo 0)
summary="protocol-conformance: $checked row(s) checked, $conformant conformant, $gapped inert with $selectors selector(s) owed; $mutant_runs mutant run(s), $mutant_red red"
# EXIT 1 IS OWED WORK: inert rows with gaps, the state the review found correct.
# EXIT 3 IS A BROKEN CHECK: a mutant went unnoticed, so nothing the run says about conformant rows can
# be trusted. Two codes rather than one, because "some rows have gaps" and "the instrument is lying"
# are not the same statement and a reader should not have to read the message to tell them apart.
if [ "$mutant_red" -ne "$mutant_runs" ]; then
    echo "$summary; EXIT 3 - THE CHECK IS BROKEN: $((mutant_runs - mutant_red)) mutant(s) went unnoticed, so its verdict on a conformant row is not evidence" >&2
    exit 3
fi
if [ "$fail" -ne 0 ]; then
    echo "$summary; EXIT 1 - the gap rows are inert by the rule, and every mutant was red, so the check is working" >&2
    exit 1
fi
echo "$summary; every row conformant, and every mutant red"
