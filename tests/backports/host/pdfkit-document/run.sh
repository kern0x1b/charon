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
"$build/make-pdf" "$build/fixtures" > /dev/null


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
xcrun clang -fobjc-arc -Wall "$here/host.m" -framework Foundation -framework PDFKit \
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
    "$port/PDFDocument11.m" "$port/PDFPage11.m" \
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
compared_expected=$((fixtures_expected * 3 + 1))
skipped_expected=$((fixtures_expected * 5))

# the facts both sides can answer, compared key by key
python3 - "$build/host.txt" "$build/port.txt" "$compared_expected" "$skipped_expected" <<'PYEOF'
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
compared = differences = skipped = 0
for key in sorted(set(host) | set(port)):
    hv, pv = host.get(key), port.get(key)
    if hv is None or pv is None:
        print(f"  MISSING   {key}  host={hv} port={pv}")
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
# A short extraction must be RED: the counts are asserted, not summarised.
print(f"COMPARED {compared} MISMATCHES {differences}  (not compared: {skipped})")
if compared != EXPECTED_COMPARED or skipped != EXPECTED_SKIPPED:
    print(f"  the run compared {compared} and skipped {skipped}, and it must compare {EXPECTED_COMPARED} "
          f"and skip {EXPECTED_SKIPPED}: the extraction is short, so this is not a verdict")
    sys.exit(1)
sys.exit(1 if differences else 0)
PYEOF
