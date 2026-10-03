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
# the DICTIONARY-OBJECT fixtures, for the families that read a nested dictionary rather than one
# annotation's flat keys: PDFBorder over /Border and /BS, PDFAppearanceCharacteristics over /MK, and
# the actions and destinations of the families after them.
python3 "$here/tools/make-object-fixtures.py" "$build/fixtures" > /dev/null
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
# PDFKitConstants11.m joins the list because the class files now READ the port's own exported string
# constants rather than repeating their values, and a constant this process does not define is an
# Undefined symbol at link time.  That file imports the SDK's PDFKit.h for its values' types and
# defines them itself, so the port binary carries its own copies and links no host PDFKit.
xcrun clang -fobjc-arc -Wall -Werror=incomplete-implementation -I "$port" "$here/port.m" \
    "$port/PDFDocument11.m" "$port/PDFPage11.m" "$port/PDFView11.m" "$port/PDFAnnotation11.m" \
    "$port/PDFBorder11.m" "$port/PDFAppearanceCharacteristics11.m" \
    "$port/PDFDestination11.m" "$port/PDFAction11.m" \
    "$port/PDFKitConstants11.m" \
    -framework Foundation -framework CoreGraphics -o "$build/port-side" 2> "$build/port.log" || {
    echo "BUILD the port side did not compile:"; head -8 "$build/port.log" | sed 's/^/    /'; exit 1; }

# side C: the port's appearance characteristics in a process that HAS a UIColor.  Mac Catalyst carries
# UIKit in a macOS process, which is the only way both platforms' own colour class can answer the two
# colour members - see color.m's header for why this is a third binary and not part of port.m.
catalyst_sdk=$(xcrun --show-sdk-path)
xcrun clang -fobjc-arc -Wall -Werror=incomplete-implementation \
    -target arm64-apple-ios15.0-macabi -isysroot "$catalyst_sdk" \
    -iframework "$catalyst_sdk/System/iOSSupport/System/Library/Frameworks" \
    -I "$port" "$here/color.m" \
    "$port/PDFDocument11.m" "$port/PDFPage11.m" "$port/PDFView11.m" "$port/PDFAnnotation11.m" \
    "$port/PDFBorder11.m" "$port/PDFAppearanceCharacteristics11.m" \
    "$port/PDFDestination11.m" "$port/PDFAction11.m" \
    "$port/PDFKitConstants11.m" \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    -o "$build/port-color-side" 2> "$build/color.log" || {
    echo "BUILD the Catalyst side did not compile:"; head -8 "$build/color.log" | sed 's/^/    /'; exit 1; }

# the rows are truncated FIRST: a stale verdict in this file once made a crash look like a pass
: > "$build/host.txt"; : > "$build/port.txt"
set +e
"$build/host-side" "$build"/fixtures/*.pdf > "$build/host.txt" 2>&1; hoststatus=$?
"$build/port-side" "$build"/fixtures/*.pdf > "$build/port.txt" 2>&1; portstatus=$?
: > "$build/color.txt"
"$build/port-color-side" > "$build/color.txt" 2>&1; colorstatus=$?
set -e
# each side's own status, not a pipeline's: a crash is a failure whatever the file says
if [ "$hoststatus" -ne 0 ] || [ "$portstatus" -ne 0 ] || [ "$colorstatus" -ne 0 ]; then
    echo "a side crashed: host=$hoststatus port=$portstatus color=$colorstatus - a crash is not a verdict"
    exit 1
fi
# The Catalyst side must have answered something, or the merge below would silently leave the
# appearance keys to a port side that cannot compile the type they hold.
if ! grep -q '^appearance.full.key.BG=' "$build/color.txt"; then
    echo "the Catalyst side printed no appearance key values; its output:"
    head -5 "$build/color.txt" | sed 's/^/    /'
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
python3 - "$build/host.txt" "$build/port.txt" "$build/color.txt" "$compared_expected" "$skipped_expected" "$1" <<'PYEOF'
import sys
# argv: 1 host, 2 port, 3 the Catalyst colour side, 4 the compared count, 5 the skipped count, 6 the
# mutation.  The colour file sits third because it is read by the extraction below, next to the two
# files it merges into - and the two counts come after it so that nothing reads a count as a path.
EXPECTED_COMPARED = int(sys.argv[4])     # the compared facts both sides must produce
EXPECTED_SKIPPED = int(sys.argv[5])      # the ones the host cannot answer, which must be named

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

# The appearance keys come from the CATALYST side, which is the only one of the three that has a
# UIColor.  Its answers override the macOS port side's for those keys and only those, and the count is
# printed in the verdict so a reader can see how much of the comparison came from the third binary.
# Everything the Catalyst side prints is an appearance key: it prints nothing else by construction
# (color.m has no other printf), which is the check that this override cannot reach anything else.
catalyst = read(sys.argv[3], "portcolor")
unwanted = [k for k in catalyst if not k.startswith("appearance.")]
if unwanted:
    print(f"MERGE REFUSED: the Catalyst side printed {len(unwanted)} key(s) that are not appearance"
          f" keys, so overriding the port's answers with them would reach facts it was not built for:"
          f" {unwanted[:4]}")
    sys.exit(1)
if not catalyst:
    print("MERGE REFUSED: the Catalyst side printed nothing, so every appearance key would be compared"
          " against a port side that has no UIColor to answer it")
    sys.exit(1)
port.update(catalyst)
catalyst_facts = len(catalyst)

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
MUTATION = sys.argv[6] if len(sys.argv) > 6 else ""

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
    parts = host[key].split(",")
    if len(parts) == 4:
        try:                                  # a rect or a colour: move the first component a whole
            numbers = [float(x) for x in parts]   # unit, far outside the 0.001
        except ValueError:
            numbers = None
        if numbers:
            numbers[0] = numbers[0] + 1.0
            planted = ",".join(f"{x:g}" for x in numbers)
        else:
            planted = host[key] + "-PLANTED"
    else:
        planted = host[key] + "-PLANTED"
    # WHERE the key is planted is the file that printed it, not a fixed one: the appearance facts come
    # from the Catalyst side and the rest from the macOS port side, and a mutation written into
    # port.txt would never be read for a key port.txt does not hold.  The prefix each file writes is
    # the side name it is read under, so the scratch copy keeps that prefix and is read the same way.
    in_port = key in read(sys.argv[2], "port")
    source_index, source_prefix, scratch_prefix = (
        (2, "port.", "port.") if in_port else (3, "portcolor.", "portcolor."))
    scratch = os.path.join(tempfile.mkdtemp(prefix="pdfkit-mutation-"), "planted.txt")
    with open(sys.argv[source_index]) as original, open(scratch, "w") as copy:
        for line in original:
            if line.startswith(source_prefix) and line.partition("=")[0][len(source_prefix):].strip() == key:
                copy.write(f"{scratch_prefix}{key}={planted}\n")
            else:
                copy.write(line)
    if in_port:
        port = read(scratch, "port")
    else:
        catalyst = read(scratch, "portcolor")
        port.update(catalyst)
    print(f"MUTATION planted on {key!r}, a key the two sides agreed on"
          f" (host={host[key]!r} port={read(sys.argv[2], 'port').get(key, read(sys.argv[3], 'portcolor').get(key))!r}),"
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
      f", expected to differ: {divergent}, of which {catalyst_facts} compared from the Catalyst side)")
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

# THE FAMILY'S OWN RED CONTROLS, one per rule this series added.  The control above plants on the first
# key the two sides agree on, which is a document fact and would go red even if the border comparison
# were blind.  Each key below is a border or appearance fact, and each is required to be a key both
# sides print with the SAME value (compare() refuses anything else), so planting on it and going red is
# a statement about that key and not about the harness.
for key in \
    border-plain.pdf.page0.annotation0.border.lineWidth \
    border-bs.pdf.page0.annotation0.border.style \
    border-bs.pdf.page0.annotation0.border.dash.values \
    border-none.pdf.page0.annotation0.border.lineWidth \
    border-link.pdf.page0.annotation0.border \
    noborder-widget-bc.pdf.page0.annotation0.border.lineWidth \
    noborder-widget.pdf.page0.annotation0.border \
    appearance.full.key.BG \
    appearance.fresh.key.R \
    appearance.cleared.keys \
    appearance.controlType2.keys \
    border.fresh.lineWidth \
    border.fresh.keys \
    border.all.lineWidth \
    border.all.keys \
    border.pattern.style \
    border.empty.keys \
    border.cleared.lineWidth \
    border.styleonly.keys \
    border.widthzero.keys \
    border-plain.pdf.page0.border.identity.same \
    border-plain.pdf.page0.border.set.same \
    border-plain.pdf.page0.border.set.mutated \
    border-plain.pdf.page0.border.set.nil \
    act-goto-xyz.pdf.page0.annotation0.action.class \
    act-goto-xyz.pdf.page0.annotation0.actionGoTo.destination.pageIndex \
    act-goto-xyz.pdf.page0.annotation0.actionGoTo.destination.point.x \
    act-goto-badpage-xyz.pdf.page0.annotation0.actionGoTo.destination.point.y \
    act-goto-badpage-xyz.pdf.page0.annotation0.actionGoTo.destination.zoom \
    act-goto-fit.pdf.page0.annotation0.actionGoTo.destination.page \
    act-goto-page2.pdf.page0.annotation0.action.pageIndex \
    act-goto-page2.pdf.page0.annotation0.action.URL \
    act-goto-shapes.pdf.page0.annotation3.actionGoTo.destination \
    act-named-all.pdf.page0.annotation1.action.name \
    act-named-all.pdf.page0.annotation0.action \
    act-named-all.pdf.page0.annotation2.action \
    act-uri.pdf.page0.annotation0.action.URL \
    act-gotor.pdf.page0.annotation0.action.URL \
    act-reset-flags.pdf.page0.annotation2.action.cleared \
    act-reset-flags.pdf.page0.annotation3.action.cleared \
    act-reset-flags.pdf.page0.annotation4.action.cleared \
    act-reset.pdf.page0.annotation0.action.fields.values \
    ann-dest-array.pdf.page0.annotation0.destination.point.x \
    ann-dest-dict.pdf.page0.annotation0.destination \
    ann-dest-and-a.pdf.page0.annotation0.destination.point.x \
    init.goto.class \
    init.named.class \
    init.named99.name \
    init.remote.class \
    init.reset.class \
    init.destination.made.zoomAfterSet
do
    family_log="$build/mutation-$key.log"
    if compare "$key" > "$family_log" 2>&1; then
        echo "RED CONTROL FAILED for $key: the comparison was run against a mutated $key and still"
        echo "  reported no mismatch. Its output:"
        sed 's/^/    /' "$family_log"
        exit 1
    fi
    grep -q "^MUTATION planted on " "$family_log" || {
        echo "RED CONTROL FAILED for $key: the mutated run went non-zero without saying which key it"
        echo "  planted, so the failure is not the control's. Its output:"
        sed 's/^/    /' "$family_log"
        exit 1
    }
    echo "RED CONTROL ok for $key:"
    grep "^  DIFFER " "$family_log" | sed 's/^/    /' | head -1
done
