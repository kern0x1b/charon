#!/bin/sh
# The port's PDFDocument and PDFPage against the host's own PDFKit, on a PDF this harness writes.
#
# TWO BINARIES, and that is the only shape that works.  An earlier version compiled the port's objects
# into the host's process with their class names renamed, so the host framework's PDFKit and the port's
# @interface shared a translation-unit universe and a small integer ended up in the port's
# CGPDFDocumentRef.  So:
#
#   host-side  the host's PDFKit and nothing else, no port object in the process
#   port-side  the port's objects and nothing else, no macOS PDFKit imported or linked - it builds
#              against the port's CharonPDFKit.h, which needs only Foundation and CoreGraphics
#
# There is no -D rename anywhere, so the two sets of ivars cannot meet.  Each side prints one
# key=value line per fact and the image dladdr names for the classes it used, and this script diffs the
# two.  The images differ by construction: one names PDFKit, the other names this binary.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../../../.." && pwd)
port=$tree/packages/a/apple-backports/PDFKit
build=${BUILD:-$tree/.agent-work/runs/pdfkit-document}
mkdir -p "$build/fixtures"

# the fixture: written here with the release's own CGPDFContext, so neither side is asked about a file
# it cannot reproduce
xcrun clang -fobjc-arc -Wall -Werror=incomplete-implementation "$here/make-pdf.m" -framework Foundation -framework CoreGraphics \
    -o "$build/make-pdf" 2> "$build/make.log" || {
    echo "BUILD the fixture writer did not compile:"; head -6 "$build/make.log" | sed 's/^/    /'; exit 1; }
python3 "$here/make-box-pdfs.py" "$build/fixtures" > /dev/null
"$build/make-pdf" "$build/fixtures" > /dev/null
# the annotation fixtures join the same directory, written by the release-aware writer rather than by
# CGPDFContext: an annotation's dictionary has to be in the file by the time it is read, and these are
# measured by both sides through the same /Annots array the port walks.
python3 "$here/tools/make-annotation-fixtures.py" "$build/fixtures" > /dev/null
# the CONFORMING-WRITER text fixtures, built here and not committed: they are a by-product of a tool, and
# a committed PDF would be a second source of truth for what the tool writes.  They are here for the text
# rows specifically - the hand-written fixtures are the control, and both kinds are walked, because a
# string answer measured only on files this port wrote itself would prove nothing about a file a
# conforming writer produced.
xcrun clang -fobjc-arc -Wall "$here/make-text-fixture.m" -framework Foundation -framework CoreGraphics \
    -o "$build/make-text-fixture" 2> "$build/make-text-fixture.log" || {
    echo "BUILD the conforming text fixture writer did not compile:"; head -6 "$build/make-text-fixture.log" | sed 's/^/    /'; exit 1; }
"$build/make-text-fixture" "$build/fixtures" > /dev/null


# The fixture must carry text, checked by reading the stream back through CGPDFStreamCopyData, which
# inflates it - a grep over the file's bytes sees only the compressed form CGPDFContext writes.  Built
# and run here, outside any pipeline, so the status checked is the checker's own.
xcrun clang -fobjc-arc -Wall "$here/check-fixture.m" -framework Foundation -framework CoreGraphics \
    -o "$build/check-fixture" 2> "$build/check-fixture.log" || {
    echo "BUILD the fixture check did not compile:"; head -6 "$build/check-fixture.log" | sed 's/^/    /'; exit 1; }
if ! "$build/check-fixture" "$build/fixtures"; then
    echo "the fixture carries no text, so every fact below would be over a document with none in it"
    exit 1
fi

# side A: the host only
# AppKit too: the host's PDFView is an AppKit view and its symbols do not link without it
xcrun clang -fobjc-arc -Wall "$here/host.m" -framework Foundation -framework AppKit -framework PDFKit \
    -o "$build/host-side" 2> "$build/host.log" || {
    echo "BUILD the host side did not compile:"; head -8 "$build/host.log" | sed 's/^/    /'; exit 1; }
# side B: the port only, with no macOS PDFKit anywhere
# -Werror=incomplete-implementation makes the COMPILER the completeness check: a selector
# CharonPDFKit.h declares with no body fails this build and the compiler names it.  That is the check.
# A hand-written metadata parser here once reported 23 missing bodies when only two were, and a check
# that cries wolf is worse than no check.  -respondsToSelector: is no use either: it answers YES for a
# declared method with no body, which is how a missing -charon_readAttributes and a missing
# -pageAtIndex: both reached a differential that printed "the port has it=1".
# -Wall and NOT -w: -w switches the warning off, and -Werror does not switch a disabled warning
# back on, so with -w the completeness check was decorative - it said nothing while a body was missing.
xcrun clang -fobjc-arc -Wall -Werror=incomplete-implementation -I "$port" "$here/port.m" \
    "$port/PDFDocument11.m" "$port/PDFPage11.m" "$port/PDFView11.m" "$port/PDFAnnotation11.m" \
    -framework Foundation -framework CoreGraphics -o "$build/port-side" 2> "$build/port.log" || {
    echo "BUILD the port side did not compile:"; head -8 "$build/port.log" | sed 's/^/    /'; exit 1; }

# the rows are truncated FIRST: a stale verdict in this file once made a crash look like a pass
: > "$build/host.txt"; : > "$build/port.txt"
set +e
"$build/host-side" "$build"/fixtures/*.pdf > "$build/host.txt" 2>&1; hoststatus=$?
"$build/port-side" "$build"/fixtures/*.pdf > "$build/port.txt" 2>&1; portstatus=$?
set -e
# each side's own status, not a pipeline's: a crash is a failure whatever the file says
if [ "$hoststatus" -ne 0 ] || [ "$portstatus" -ne 0 ]; then
    echo "a side crashed: host=$hoststatus port=$portstatus - a crash is not a verdict"
    exit 1
fi

# the images must differ BY CONSTRUCTION, or the two sides are not what this thinks they are
hostimage=$(grep -m1 '^host.PDFDocument.image=' "$build/host.txt" | cut -d= -f2-)
portimage=$(grep -m1 '^port.PDFDocument.image=' "$build/port.txt" | cut -d= -f2-)
case "$hostimage" in *PDFKit*) ;; *) echo "the host side's PDFDocument is not from PDFKit: $hostimage"; exit 1;; esac
case "$portimage" in *port-side*|*port\.side*) ;; *) echo "the port side's PDFDocument is not from this binary: $portimage"; exit 1;; esac
[ "$hostimage" != "$portimage" ] || { echo "both sides name the same image: $hostimage"; exit 1; }
echo "images differ by construction: host=$hostimage port=$portimage"

# the counts are derived from the fixtures, not typed in: three fixtures, and per fixture the
# document, its page count and the past-the-end page are comparable, while the three attributes and
# the two boxes are not - the host's PDFKit has no such methods, which the run names per line
fixtures_expected=$(ls "$build"/fixtures/*.pdf | wc -l | tr -d ' ')
# The expected count is NOT written as an arithmetic formula any more: it depended on how many
# attributes a fixture's Info carries, and that differs per fixture - the box fixtures name no Info and
# answer no keys, the text fixtures name six.  A formula that counted them would have to be right about
# every fixture to be a check at all.  The comparison now asserts instead that every key BOTH sides
# printed was accounted for, and that the only keys not compared are the ones the run says why.
compared_expected=0
skipped_expected=0

# the facts both sides can answer, compared key by key
# THE COMPARISON, as a function so the red control below runs the same verdict code rather than a
# second copy of it that could disagree with this one. $1 is the mutation mode: empty for the plain
# comparison, "auto" to plant a key the two sides currently agree on, or a key's own name.
compare() {
python3 - "$build/host.txt" "$build/port.txt" "$compared_expected" "$skipped_expected" "$1" <<'PYEOF'
import sys
EXPECTED_COMPARED = int(sys.argv[3])     # the compared facts both sides must produce
EXPECTED_SKIPPED = int(sys.argv[4])      # the ones the host cannot answer, which must be named

def read(path, side):
    keys = {}
    for line in open(path):
        line = line.rstrip("\n")
        if not line or line.startswith("side="):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        prefix = side + "."
        if key.startswith(prefix):
            key = key[len(prefix):]
        if key.endswith(".image"):
            continue        # the images are the PROOF the sides are separate, asserted above
        keys[key] = value
    return keys

host, port = read(sys.argv[1], "host"), read(sys.argv[2], "port")

# ---- the red control -------------------------------------------------------------------
#
# A comparison that reads "0 mismatches" is only evidence if it WOULD have read one had the port
# been wrong, and the only way to know that is to make it wrong on purpose and see. So:
#
#   --mutation <key>   plant one value for that key, in a SCRATCH COPY of the port's answers
#   --mutation auto    plant the first key the two sides currently AGREE on
#   --mutation plant   the flag with no key named, which must fail rather than pass quietly
#
# The key is chosen from the data rather than named by hand: a key is eligible only if it is present
# on both sides with the same value, so "it agrees" is the run's own finding and not my assertion.
# The mutation is written to a scratch file and the port map is re-read from it, so the port's own
# answers on disk are never touched and the same verdict code below does all the comparing.
MUTATION = sys.argv[5] if len(sys.argv) > 5 else ""

if MUTATION:
    if MUTATION == "plant" or not MUTATION:
        print("MUTATION has no key to plant: --mutation was given a flag and no key, and a control"
              " that plants nothing must fail rather than report a clean run")
        sys.exit(1)
    agreeing = sorted(k for k in host if k in port and host[k] == port[k]
                      and not any(k.endswith(s) for s in
                                  ("documentAttribute.supported", "page0.pageIndex.supported")))
    if MUTATION == "auto":
        if not agreeing:
            print("MUTATION has no key to plant: the two sides agree on nothing, so there is no"
                  " agreeing key to change and the control cannot run")
            sys.exit(1)
        key = agreeing[0]
    else:
        key = MUTATION
        if key not in host or key not in port:
            print(f"MUTATION was asked for {key!r} and the two sides do not both print it:"
                  f" host={'yes' if key in host else 'no'} port={'yes' if key in port else 'no'}")
            sys.exit(1)
        if host[key] != port[key]:
            print(f"MUTATION was asked for {key!r}, which the two sides do NOT agree on"
                  f" (host={host[key]!r} port={port[key]!r}), so mutating it would prove nothing"
                  " about the comparison seeing a difference it should have seen")
            sys.exit(1)
    import os
    import tempfile
    scratch = os.path.join(tempfile.mkdtemp(prefix="pdfkit-mutation-"), "port.txt")
    parts = host[key].split(",")
    if len(parts) == 4:
        try:                                  # a rect: move it a whole unit, far outside the 0.001
            numbers = [float(x) for x in parts]
        except ValueError:
            numbers = None
        if numbers:
            numbers[0] = numbers[0] + 1.0
            planted = ",".join(f"{x:g}" for x in numbers)
        else:
            planted = host[key] + "-PLANTED"
    else:
        planted = host[key] + "-PLANTED"
    with open(sys.argv[2]) as original, open(scratch, "w") as copy:
        for line in original:
            if line.startswith("port.") and line.partition("=")[0][len("port."):].strip() == key:
                copy.write(f"port.{key}={planted}\n")
            else:
                copy.write(line)
    port = read(scratch, "port")
    print(f"MUTATION planted on {key!r}, a key the two sides agreed on"
          f" (host={host[key]!r} port={read(sys.argv[2], 'port')[key]!r}),"
          f" now port={port[key]!r} in a scratch copy at {scratch}")
    if port[key] == host[key]:
        print(f"MUTATION failed: {key!r} was planted and still agrees, so the comparison is blind")
        sys.exit(1)

compared = differences = skipped = 0
# the SINGULAR accessor's presence is EXPECTED to differ: the port implements what the host lacks, and
# that is why its row stays inert.  Named here, inside the loop, so it is neither compared nor counted as
# a difference.
EXPECTED_DIVERGENT = ("documentAttribute.supported", "page0.pageIndex.supported",
                     "view.window.supported")
# and the ones this run cannot compare at all, with the reason it prints for each
NOT_COMPARED = {
    "dataRepresentation.length": ("the port's own bytes against the host's REWRITTEN document, and a "
                                  "count of two different documents is not a fact either side can agree on"),

}
divergent = 0
for key in sorted(set(host) | set(port)):
    if any(key.endswith(suffix) for suffix in EXPECTED_DIVERGENT):
        divergent += 1
        hv, pv = host.get(key), port.get(key)
        if hv is not None and pv is not None and hv != pv:
            print(f"  expected to differ  {key}  host={hv} port={pv}"
                  f"  (the port implements what the host lacks)")
        continue
    if any(key.endswith(suffix) for suffix in NOT_COMPARED):
        skipped += 1
        print(f"  not compared  {key}  host={host.get(key)}  port={port.get(key)}  -  {NOT_COMPARED[[s for s in NOT_COMPARED if key.endswith(s)][0]]}")
        continue
    hv, pv = host.get(key), port.get(key)
    if hv is None or pv is None:
        print(f"  MISSING   {key}  host={hv} port={pv}")
        differences += 1
        continue
    if ".page0." in key:
        # a rect: four numbers, compared with a stated tolerance rather than as text
        try:
            a = [float(x) for x in hv.split(",")]
            b = [float(x) for x in pv.split(",")]
        except ValueError:
            a = b = None
        if a and len(a) == 4 and len(b) == 4:
            compared += 1
            near = all(abs(x - y) <= 0.001 for x, y in zip(a, b))
            print(f"  {'agree  ' if near else 'DIFFER '} {key}  host={hv} port={pv}"
                  f"{'' if near else '   (tolerance 0.001)'}")
            if not near:
                differences += 1
            continue
    if hv.startswith("NOT-COMPARED") or pv.startswith("NOT-COMPARED"):
        skipped += 1
        print(f"  not compared  {key}  host={hv}  port={pv}")
        continue
    compared += 1
    print(f"  {'agree  ' if hv == pv else 'DIFFER '} {key}  host={hv!r} port={pv!r}")
    if hv != pv:
        differences += 1
print(f"COMPARED {compared} MISMATCHES {differences}  (not compared: {skipped}"
      f", expected to differ: {divergent})")
unaccounted = (len(set(host) | set(port)) - compared - skipped - divergent)
if unaccounted != 0:
    print(f"  {unaccounted} key(s) both sides printed were neither compared, skipped nor expected to"
          f" differ: the extraction is short, so this is not a verdict")
    sys.exit(1)
sys.exit(1 if differences else 0)
sys.exit(1 if differences else 0)

PYEOF
}

# the plain comparison: the run's own verdict, and a mismatch here fails the run
compare "" || { echo "the port and the host disagree on something; see above"; exit 1; }

# THE RED CONTROL, and it is part of the sequence rather than something a reader can run later: the
# port's answers are mutated on ONE key in a SCRATCH COPY, and the run requires that this makes the
# comparison go red. A comparison that still reports no mismatch after a value it agreed on has
# changed is blind, and a differential that cannot say so is not evidence of anything.
control_log="$build/mutation.log"
if compare auto > "$control_log" 2>&1; then
    echo "RED CONTROL FAILED: the comparison was run against a mutated port and still reported no"
    echo "  mismatch, so it would pass a port that is wrong. Its output:"
    sed 's/^/    /' "$control_log"
    exit 1
fi
grep -q "^MUTATION planted on " "$control_log" || {
    echo "RED CONTROL FAILED: the mutated run went non-zero without saying which key it planted,"
    echo "  so the failure is not the control's. Its output:"
    sed 's/^/    /' "$control_log"
    exit 1
}
echo "RED CONTROL ok: the comparison goes red on a mutated port, and names the key:"
grep "^MUTATION planted on " "$control_log" | sed 's/^/    /'
grep "^  DIFFER " "$control_log" | sed 's/^/    /' | head -4
