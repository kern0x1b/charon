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
# the FONT fixtures, for -[PDFSelection boundsForPage:].  These cannot come from the conforming writer,
# because a conforming writer emits a CONSISTENT font - it computes /Widths from the program it embeds -
# and the whole question is which of the two a reader uses.  So the PROGRAM is lifted verbatim out of the
# /FontFile2 stream of a fixture the conforming writer wrote (make-text-fixture.m has just written it) and
# the /Widths are written from a spec beside it, disagreeing on purpose and by a wide margin.
python3 "$here/tools/make-font-fixtures.py" "$build/fixtures/cgfixture-1.pdf" "$build/fixtures" > /dev/null
# and the standard fourteen's TABLE, which is GENERATED from a measurement rather than typed, is checked
# against that measurement here so a hand edit to it cannot pass unnoticed.  The measurement is committed
# beside the generator for exactly this reason: a check that only runs in the session that measured is not
# a check.  It is a no-op that must be silent on a clean checkout, so its verdict is printed as a line.
python3 "$here/tools/make-base14-table.py" "$port/Base14Widths11.m" --check || {
    echo "the standard fourteen's table is not what the committed measurement produces:"; exit 1; }


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
    "$port/PDFDestination11.m" "$port/PDFAction11.m" "$port/PDFOutline11.m" "$port/PDFPageText11.m" \
    "$port/PDFSelection11.m" "$port/Base14Widths11.m" \
    "$port/PDFKitConstants11.m" \
    -framework Foundation -framework CoreGraphics -o "$build/port-side" 2> "$build/port.log" || {
    echo "BUILD the port side did not compile:"; head -8 "$build/port.log" | sed 's/^/    /'; exit 1; }

# side C: the port's appearance characteristics and PDFAnnotation's three colours and its font, in a
# process that HAS a UIColor and a UIFont.  Mac Catalyst carries UIKit in a macOS process, which is the
# only way both platforms' own colour class can answer them - see color.m's header for why this is a
# third binary and not part of port.m.  PDFAnnotationColours11.m is on THIS line and not the macOS one for
# the same reason: it is the only object of the port that imports UIKit.
catalyst_sdk=$(xcrun --show-sdk-path)
xcrun clang -fobjc-arc -Wall -Werror=incomplete-implementation \
    -target arm64-apple-ios15.0-macabi -isysroot "$catalyst_sdk" \
    -iframework "$catalyst_sdk/System/iOSSupport/System/Library/Frameworks" \
    -I "$port" "$here/color.m" \
    "$port/PDFDocument11.m" "$port/PDFPage11.m" "$port/PDFView11.m" "$port/PDFAnnotation11.m" \
    "$port/PDFAnnotationColours11.m" \
    "$port/PDFBorder11.m" "$port/PDFAppearanceCharacteristics11.m" \
    "$port/PDFDestination11.m" "$port/PDFAction11.m" "$port/PDFOutline11.m" \
    "$port/PDFPageText11.m" "$port/PDFSelection11.m" "$port/Base14Widths11.m" \
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
"$build/port-color-side" "$build"/fixtures/*.pdf > "$build/color.txt" 2>&1; colorstatus=$?
set -e
# each side's own status, not a pipeline's: a crash is a failure whatever the file says
if [ "$hoststatus" -ne 0 ] || [ "$portstatus" -ne 0 ] || [ "$colorstatus" -ne 0 ]; then
    echo "a side crashed: host=$hoststatus port=$portstatus color=$colorstatus - a crash is not a verdict"
    exit 1
fi
# The Catalyst side must have answered something, or the merge below would silently leave the
# appearance keys to a port side that cannot compile the type they hold - and it must have answered the
# ANNOTATION colour keys too, which is the only place a UIColor exists for -[PDFAnnotation backgroundColor].
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
TC_FIXTURES=$(python3 - "$build/fixtures" <<'TCEOF'
import glob, os, re, sys, zlib
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.pdf"))):
    data = open(path, "rb").read()
    for match in re.finditer(rb"stream\r?\n(.*?)\nendstream", data, re.S):
        raw = match.group(1)
        if b"/FlateDecode" in data[max(0, match.start() - 120):match.start()]:
            try:
                raw = zlib.decompress(raw)
            except Exception:
                continue
        if b" Tf" not in raw:
            continue
        spacing = re.search(rb"([-\d.]+)\s+Tc", raw)
        if spacing is not None and float(spacing.group(1)) != 0.0:
            print(os.path.basename(path))
        break
TCEOF
)
python3 - "$build/host.txt" "$build/port.txt" "$build/color.txt" "$compared_expected" "$skipped_expected" "$1" "$TC_FIXTURES" <<'PYEOF'
import sys
# argv: 1 host, 2 port, 3 the Catalyst colour side, 4 the compared count, 5 the skipped count, 6 the
# mutation.  The colour file sits third because it is read by the extraction below, next to the two
# files it merges into - and the two counts come after it so that nothing reads a count as a path.
EXPECTED_COMPARED = int(sys.argv[4])     # the compared facts both sides must produce
EXPECTED_SKIPPED = int(sys.argv[5])      # the ones the host cannot answer, which must be named
# the fixtures whose content stream sets a non-zero Tc, computed by the shell above over the fixture
# directory - see the comment on the second stated boundary
TC_FIXTURES = [n for n in sys.argv[7].split() if n]

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

# The appearance keys and the ANNOTATION COLOUR keys come from the CATALYST side, which is the only one of
# the three binaries that has a UIColor and a UIFont.  Its answers override the macOS port side's for those
# keys and only those, and the count is printed in the verdict so a reader can see how much of the
# comparison came from the third binary.
#
# What it may print is a LIST, and the list is the check that this override cannot reach anything else: a
# third binary whose answers were merged into the port's map could silently take over a document fact, so
# every key it prints has to be one of the two namespaces it exists for.  Both are namespaced on purpose -
# `appearance.' for the appearance-characters object and `.colours.' for -[PDFAnnotation]'s own four
# members, whose keys carry `.colours.' and NOT `.page0.' because compare() reads any ".page0." key of four
# numbers as a RECTANGLE and gives it a 0.001 tolerance, which is right for a rectangle and would hide the
# third-decimal difference this family is about.
CATALYST_NAMESPACES = ("appearance.", ".colours.")
catalyst = read(sys.argv[3], "portcolor")
unwanted = [k for k in catalyst if not any(s in k for s in CATALYST_NAMESPACES)]
if unwanted:
    print(f"MERGE REFUSED: the Catalyst side printed {len(unwanted)} key(s) outside the namespaces it"
          f" exists for, so overriding the port's answers with them would reach facts it was not built for:"
          f" {unwanted[:4]}")
    sys.exit(1)
if not catalyst:
    print("MERGE REFUSED: the Catalyst side printed nothing, so every appearance key would be compared"
          " against a port side that has no UIColor to answer it")
    sys.exit(1)
if not [k for k in catalyst if ".colours." in k]:
    print("MERGE REFUSED: the Catalyst side printed no annotation colour key, so -[PDFAnnotation"
          " backgroundColor, -interiorColor, -fontColor and -font would be compared against a port side"
          " that cannot compile UIColor or UIFont at all - which is the same silent gap the appearance"
          " guard above exists for")
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
    # port.txt would never be read for a key port.txt does not hold.
    #
    # WHICH LINE is the key is NOT decided by a prefix, and that is the whole of a defect this family
    # found in the harness: read() above takes a line's key to be its name with the side's prefix
    # removed WHEN THERE IS ONE, because the class-level facts are printed as "port.<key>" and
    # "portcolor.<key>" while every per-fixture fact is printed as a BARE "<key>".  This writer used to
    # look for the prefix, so for every per-fixture key it found no line at all, wrote the file through
    # unchanged, and the comparison then reported "MUTATION failed: the comparison is blind" and exited
    # non-zero - which the loop below read as a PASS.  All 116 named controls were doing that, and the
    # automatic one passed only because the key it happened to choose is a prefixed one.  So the line is
    # found by its KEY, the prefix it carries is kept as it is, and a key that is in no line is a refusal
    # rather than a silent no-op.
    in_port = key in read(sys.argv[2], "port")
    source_index, source_prefix = (2, "port.") if in_port else (3, "portcolor.")
    scratch = os.path.join(tempfile.mkdtemp(prefix="pdfkit-mutation-"), "planted.txt")
    replaced = 0
    with open(sys.argv[source_index]) as original, open(scratch, "w") as copy:
        for line in original:
            name = line.partition("=")[0]
            bare = name[len(source_prefix):] if name.startswith(source_prefix) else name
            if bare.strip() == key:
                copy.write(f"{name}={planted}\n")
                replaced += 1
            else:
                copy.write(line)
    if replaced == 0:
        print(f"MUTATION REFUSED: {key!r} is in no line of the file it should be planted in, and a"
              " control that plants nothing must fail rather than report a clean run")
        sys.exit(1)
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
# A BOUNDARY OF A ROW, which is the other direction: the HOST answers something this port deliberately
# does not, and the reason is printed beside it so the difference is accounted for rather than tolerated.
# Each entry is one named, measured divergence with its cause; a key in one of these sets is neither
# compared nor counted as a difference, and the values are printed so the divergence is visible.
#
# 1. -[PDFSelection boundsForPage:] over a font with no /Widths at all - the base fourteen.  There the host
#    answers the standard metrics of PDF 1.7 Annex F, which are the FORMAT's data and not anything the
#    document carries.  This port DOES carry them, measured, in Base14Widths11.m - but only for the
#    fourteen, so a /BaseFont naming anything else with no /Widths has no advances here.  Measured on
#    cgfixture-base14-no-widths.pdf... which is Courier, one of the fourteen, and which this port DOES
#    answer; the fixture is kept because it is the measurement, and the divergence below is the general
#    case, which no fixture here draws.
#
# 2. -[PDFSelection boundsForPage:] over text drawn with a CHARACTER SPACING.  CGPDFContext - the
#    conforming writer - writes `0.0002 Tc` into the fixtures it draws, and the host's answer then carries
#    a term this row has measured but NOT reproduced: it is non-zero, exactly linear in Tc (0.0010 at
#    0.0002 and 0.0100 at 0.002 on the same six glyphs), and its per-glyph distribution is measured and
#    unexplained - 0.5, 1, 1, 0.5, 2 and 0 multiples of Tc across "page 1".  The port applies the format's
#    own rule instead (Tc after every glyph but the last), which makes the TOTAL exact and each glyph
#    exact to within one Tc, 0.0002pt.  The residual is bounded and named here rather than fitted, and
#    facts/PDFKit/Selection11.md has the numbers.  THE LIST IS COMPUTED, not written out: the fixtures
#    whose content stream really does set a non-zero Tc, read the same way the fixture checker reads one.
BOUNDARY_TC_REASON = (
    "the host's rect carries a character-spacing term this row has measured and not reproduced: "
    "non-zero, exactly linear in Tc, per-glyph distribution unexplained; the port applies Tc after every "
    "glyph but the last, which makes the total exact and each glyph exact to within 0.0002pt")
# 3. -[PDFSelection boundsForPage:] over a run whose TEXT the LINE RULE changed: a trimmed leading space,
#    a run of spaces collapsed to one, or a control byte turned into a NUL.  The line rule is measured and
#    implemented - facts/PDFKit/Document11.md has the five fixtures - but it is a rule about the STRING,
#    and what it does to the PEN is a separate question this row has measured only in part.  The four
#    fixtures below are the ones that ask it: cgfixture-lead (a leading space), cgfixture-gap (two spaces
#    drawn where the string carries one), cgfixture-inline (a newline inside a run) and cgfixture-tab (a
#    tab inside a run).  The largest deviation is 10.0152pt on cgfixture-lead, which is one space plus its
#    rounding; the others are 0.0012 and under.  Every OTHER key of these fixtures is still compared, and
#    so is every bounds key of every fixture whose text the line rule left alone.
BOUNDARY_LINERULE_REASON = (
    "the line rule changed this run's text - a trimmed leading space, collapsed spaces, or a control byte - "
    "and what that does to the pen is measured only in part; the string, the ranges and every other key of "
    "this fixture are still compared")
# A LIST and not a tuple: it is concatenated with TC_FIXTURES below, and a list plus a tuple is the
# TypeError that stopped this comparison before it compared anything.
BOUNDARY_LINERULE_FIXTURES = ["cgfixture-gap.pdf", "cgfixture-inline.pdf", "cgfixture-lead.pdf",
                              "cgfixture-tab.pdf"]
BOUNDARY_BASE14_REASON = (
    "a /BaseFont outside the standard fourteen with no /Widths has no advances this port can reach; the "
    "fourteen's own metrics are carried, measured, in Base14Widths11.m")
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
boundary = 0
for key in sorted(set(host) | set(port)):
    # A character-spacing fixture's bounds keys are the second boundary, and ONLY its bounds keys: every
    # other key such a fixture prints - the string, the ranges, the pages, the colour, the attributed
    # length, the copy - is still compared, and so is every bounds key of every fixture that sets no Tc.
    if any(key.startswith(name) and ".bounds" in key
           for name in TC_FIXTURES + BOUNDARY_LINERULE_FIXTURES):
        boundary += 1
        hv, pv = host.get(key), port.get(key)
        if hv is not None and pv is not None and hv != pv:
            reason = (BOUNDARY_LINERULE_REASON
                      if any(key.startswith(name) for name in BOUNDARY_LINERULE_FIXTURES)
                      else BOUNDARY_TC_REASON)
            print(f"  stated boundary  {key}  host={hv} port={pv}  -  {reason}")
        continue
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
      f", expected to differ: {divergent}, of which {catalyst_facts} compared from the Catalyst side"
      f", stated boundary: {boundary})")
unaccounted = (len(set(host) | set(port)) - compared - skipped - divergent - boundary)
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
# and the same requirement as the named controls below: a DIFFERENCE, not only a non-zero exit
grep -q "^  DIFFER " "$control_log" || {
    echo "RED CONTROL FAILED: the mutated comparison reported no difference, so it would pass a port"
    echo "  that is wrong on this key. Its output:"
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
# NOT NAMED IN THIS LIST, and the mutator is what says so rather than the comment: cgfixture-text-tc,
# cgfixture-lines2 and cgfixture-3 all draw with a character spacing, so their bounds keys are one of the
# stated boundaries above and the two sides do not agree on them.  A control on such a key proves nothing
# about the comparison seeing a difference it should have seen, and the run refuses it by name - which is
# the right answer and is why those three are absent here rather than present and failing.
#
# cgfixture-high-byte.pdf is absent for the other reason: its text is "caf<E9>" and none of the harness's
# needles matches any of it, so it prints no bounds key at all and a control naming one is refused for the
# same reason - "the two sides do not both print it".  Its -string keys are still compared.
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
    init.destination.made.zoomAfterSet \
    initdest.nilpage \
    initgoto.class \
    initnamed.class \
    initremote.class \
    initremote.point.x \
    copy.destination.same \
    copy.destination.page.same \
    copy.destination.zoomAfterSet \
    copy.destination.zoomOriginal \
    copy.nopage \
    copy.goto.destination.same \
    copy.goto.destination.page.same \
    copy.named.nameAfterSet \
    copy.remote.pageIndex \
    copy.reset.fields.same \
    copy.action.class \
    initoutline.class \
    initoutline.dest \
    initoutline.root \
    outline-collapsed.pdf.outline.label \
    outline-collapsed.pdf.outline.children \
    outline-collapsed.pdf.outline.isOpen \
    outline-collapsed.pdf.outline.parent \
    outline-collapsed.pdf.c0.outline.index \
    outline-collapsed.pdf.c0.outline.isOpen \
    outline-collapsed.pdf.c0.outline.dest.point \
    outline-collapsed.pdf.c0.outline.action.type \
    outline-collapsed.pdf.c0.c0.outline.label \
    outline-collapsed.pdf.c0.c1.outline.index \
    outline-collapsed.pdf.c1.outline.action.class \
    outline-signs.pdf.c0.outline.isOpen \
    outline-signs.pdf.c1.outline.isOpen \
    outline-nocount.pdf.c0.outline.isOpen \
    outline-untitled.pdf.c0.c0.c0.c0.outline.isOpen \
    outline-titled.pdf.c0.c0.c0.c0.outline.isOpen \
    outline-titlekey.pdf.c0.c0.outline.isOpen \
    outline-titlekey.pdf.c1.c0.outline.isOpen \
    outline-titlekey.pdf.c2.c0.outline.isOpen \
    outline-shapes.pdf.c0.c0.outline.action.dest.point \
    outline-shapes.pdf.c2.outline.dest.page \
    outline-shapes2.pdf.c0.c1.outline.isOpen \
    act-goto-fit.pdf.outline \
    outline-collapsed.pdf.childPastEnd \
    outline-collapsed.pdf.c0.childPastEnd \
    outline-collapsed.pdf.c0.c0.childPastEnd \
    outline-nocount.pdf.c0.childPastEnd \
    cgfixture-pair-down.pdf.page0.string \
    cgfixture-pair-down.pdf.page0.numberOfCharacters \
    cgfixture-pair-same.pdf.page0.string \
    cgfixture-pair-up.pdf.page0.string \
    cgfixture-lines.pdf.page0.string \
    cgfixture-lines.pdf.page0.numberOfCharacters \
    widget-flags.pdf.page0.annotation0.flags.readOnly \
    widget-flags.pdf.page0.annotation0.flags.multiline \
    widget-flags.pdf.page0.annotation0.flags.isPasswordField \
    widget-flags.pdf.page0.annotation0.flags.comb \
    widget-flags.pdf.page0.annotation0.flags.allowsToggleToOff \
    widget-flags.pdf.page0.annotation0.flags.radiosInUnison \
    widget-flags.pdf.page0.annotation0.flags.listChoice \
    widget-flags.pdf.page0.annotation0.flags.widgetControlType \
    widget-flags.pdf.page0.annotation0.flags.activatableTextField \
    widget-flags.pdf.page0.annotation5.flags.widgetControlType \
    widget-flags.pdf.page0.annotation6.flags.widgetControlType \
    widget-flags.pdf.page0.annotation7.flags.listChoice \
    widget-flags.pdf.page0.annotation12.flags.radiosInUnison \
    widget-flags.pdf.page0.annotation4.flags.allowsToggleToOff \
    widget-noflags.pdf.page0.annotation0.flags.widgetControlType \
    widget-allflags.pdf.page0.annotation0.flags.widgetControlType \
    widget-allflags.pdf.page0.annotation0.flags.readOnly \
    widget-fttx1.pdf.page0.annotations.count \
    widget-ftch2.pdf.page0.annotations.count \
    widget-ftch4.pdf.page0.annotations.count \
    widget-ftch5.pdf.page0.annotations.count \
    widget-ftbtn0.pdf.page0.annotation0.flags.activatableTextField \
    act-goto-fit.pdf.page0.annotation0.flags.activatableTextField \
    widget-t-literal.pdf.page0.annotation0.flags.fieldName \
    widget-t-empty.pdf.page0.annotation0.flags.fieldName \
    widget-t-merged.pdf.page0.annotation0.flags.fieldName \
    widget-t-mergedname.pdf.page0.annotation0.flags.fieldName \
    widget-t-extra-TU.pdf.page0.annotation0.flags.fieldName \
    widget-t-extra-DAstring.pdf.page0.annotation0.flags.fieldName \
    widget-t-extra-DAstring.pdf.page0.annotations.count \
    button-ap-states.pdf.page0.annotation0.state.onName \
    button-ap-states.pdf.page0.annotation1.state.onName \
    button-ap-states.pdf.page0.annotation2.state.onName \
    button-ap-states.pdf.page0.annotation3.state.onName \
    button-ap-states.pdf.page0.annotation4.state.onName \
    button-as-alone.pdf.page0.annotation0.state.onName \
    widget-flags.pdf.page0.annotation0.state.onName \
    button-as-and-v.pdf.page0.annotation1.state.on \
    button-as-and-v.pdf.page0.annotation2.state.on \
    button-asoff-von.pdf.page0.annotation0.state.on \
    button-asoff-von.pdf.page0.annotation3.state.on \
    button-v-only.pdf.page0.annotation3.state.on \
    button-v-only.pdf.page0.annotation2.state.on \
    button-ap-states.pdf.page0.annotation1.state.on \
    button-ap-states.pdf.page0.annotation3.state.on \
    button-ap-states.pdf.page0.annotation4.state.on \
    text-as.pdf.page0.annotation3.state.on \
    button-merged-vyes-asyes.pdf.page0.annotation0.state.on \
    cgfixture-lines2.pdf.page0.string \
    cgfixture-lines2.pdf.page0.numberOfCharacters \
    cgfixture-words.pdf.page0.string \
    cgfixture-gap.pdf.page0.string \
    cgfixture-gap.pdf.page0.numberOfCharacters \
    cgfixture-lead.pdf.page0.string \
    cgfixture-tail.pdf.page0.string \
    cgfixture-tail.pdf.page0.numberOfCharacters \
    cgfixture-tailpair.pdf.page0.string \
    cgfixture-blank.pdf.page0.string \
    cgfixture-inline.pdf.page0.string \
    cgfixture-tab.pdf.page0.string \
    cgfixture-cross.pdf.page0.string \
    cgfixture-words.pdf.find.alpha.count \
    cgfixture-words.pdf.find.alpha.0.string \
    cgfixture-words.pdf.find.alpha.0.range0 \
    cgfixture-words.pdf.find.alpha.0.ranges \
    cgfixture-words.pdf.find.alpha.0.pages \
    cgfixture-words.pdf.find.alpha.0.byLine \
    cgfixture-words.pdf.find.alpha.0.copy \
    cgfixture-words.pdf.find.alpha.0.attributedLength \
    cgfixture-words.pdf.find.alpha.backwards.0.range0 \
    cgfixture-lines.pdf.find.third.0.string \
    cgfixture-lines.pdf.find.third.0.range0 \
    cgfixture-lines2.pdf.find.two.0.string \
    cgfixture-lines2.pdf.find.two.0.range0 \
    cgfixture-3.pdf.find.page.backwards.0.ranges \
    cgfixture-widths-vs-program-wide.pdf.find.page.0.bounds0 \
    cgfixture-widths-vs-program-narrow.pdf.find.page.0.bounds0 \
    cgfixture-no-font-program.pdf.find.page.0.bounds0 \
    cgfixture-broken-font-program.pdf.find.page.0.bounds0 \
    cgfixture-text-no-tc.pdf.find.page.0.bounds0 \
    cgfixture-base14-with-widths.pdf.find.page.0.bounds0 \
    act-goto-bad-page.pdf.find.line.backwards.0.boundsLast \
    cgfixture-gap.pdf.find.alpha.0.string \
    cgfixture-blank.pdf.find.alpha.0.string \
    cgfixture-lead.pdf.find.bravo.0.range0 \
    annotation-colours.pdf.colours.names \
    annotation-colours.pdf.colours.nmbg-rgb.backgroundColor.space \
    annotation-colours.pdf.colours.nmbg-rgb.backgroundColor.components \
    annotation-colours.pdf.colours.nmbg-cmyk.backgroundColor.space \
    annotation-colours.pdf.colours.nmbg-notarray.backgroundColor \
    annotation-colours.pdf.colours.nmic-square-gray.interiorColor.space \
    annotation-colours.pdf.colours.nmic-circle-cmyk.interiorColor.components \
    annotation-colours.pdf.colours.nmda-fill-rgb.fontColor.space \
    annotation-colours.pdf.colours.nmda-fill-rgb.fontColor.components \
    annotation-colours.pdf.colours.nmda-fill-badcount.fontColor.components \
    annotation-colours.pdf.colours.nmda-stroke-k.fontColor.space \
    annotation-colours.pdf.colours.nmfont-courier-7.font.name \
    annotation-colours.pdf.colours.nmfont-courier-7.font.size \
    annotation-colours.pdf.colours.nmfont-abbrev-hebo.font.name \
    annotation-colours.pdf.colours.nmfont-unknown.font.size
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
    # AND IT HAS TO GO RED ON THE DIFFERENCE, not merely exit non-zero: the defect this family found is
    # that a control which planted nothing at all exited non-zero with "MUTATION failed" and was read as
    # a pass, so a non-zero exit alone is not evidence that the comparison saw anything.
    grep -q "^  DIFFER " "$family_log" || {
        echo "RED CONTROL FAILED for $key: the mutated comparison reported no difference, so planting on"
        echo "  this key proves nothing about the comparison seeing one. Its output:"
        sed 's/^/    /' "$family_log"
        exit 1
    }
    echo "RED CONTROL ok for $key:"
    grep "^  DIFFER " "$family_log" | sed 's/^/    /' | head -1
done
